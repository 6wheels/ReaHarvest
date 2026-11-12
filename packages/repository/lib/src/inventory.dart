import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'conventions.dart';
import 'json_lines.dart';
import 'mounted_folder_storage.dart';

/// Library description (`libraryFileName` of the library package), left out
/// of the inventory: the application rewrites it during a migration (known
/// values), it is not a file of the user.
const _libraryFile = '.library.json';

/// A file of the inventory: its state before the first change.
typedef InventoryEntry = ({int size, DateTime modified, String hash});

/// Inventory of a migration (SPEC §5.8 steps 2 and 5): every file of the
/// library before the first change, with its size, modification date and
/// XXH3 hash, appended line by line to `<folder>/inventory.jsonl`:
/// ```
/// {"path":"Band/Song/a.wav","size":1234,"modified":1731300000000000,"hash":"0123456789abcdef"}
/// {"complete":true,"files":1}
/// ```
/// `modified` is in microseconds since the epoch; the last line of a path
/// wins, `{"path":…,"removed":true}` drops it (gone before the inventory
/// was complete). Raw copies of the files rewritten are kept in
/// `<folder>/originals/`, under their inventory path ([originalPath]).
final class Inventory {
  /// A new inventory in the migration [folder]; nothing is written before
  /// [take]. The entries of [reuse] (by current path) are taken without
  /// hashing for the files whose size and date are unchanged.
  Inventory(
    RepositoryStorage storage,
    String folder, {
    Map<String, InventoryEntry> reuse = const {},
  }) : this._(
         storage,
         folder,
         {},
         false,
         reuse,
         JsonLinesFile(storage, '$folder/$fileName'),
       );

  Inventory._(
    this._storage,
    this.folder,
    this._files,
    this._complete,
    this._reuse,
    this._file,
  );

  static const fileName = 'inventory.jsonl';

  final RepositoryStorage _storage;

  /// Library path of the migration folder: `.migration/<stamp>`.
  final String folder;

  final Map<String, InventoryEntry> _files;
  bool _complete;
  final Map<String, InventoryEntry> _reuse;
  final JsonLinesFile _file;

  /// The inventory of the migration [folder], complete or not, or null if
  /// it has none.
  static Future<Inventory?> read(
    RepositoryStorage storage,
    String folder,
  ) async {
    final path = '$folder/$fileName';
    final read = await readJsonLines(storage, path);
    if (read == null) return null;
    final files = <String, InventoryEntry>{};
    var complete = false;
    for (final line in read.lines) {
      switch (line) {
        case {'complete': true}:
          complete = true;
        case {'path': final String path, 'removed': true}:
          files.remove(path);
        case {
          'path': final String path,
          'size': final int size,
          'modified': final int modified,
          'hash': final String hash,
        }:
          files[path] = (
            size: size,
            modified: DateTime.fromMicrosecondsSinceEpoch(modified),
            hash: hash,
          );
      }
    }
    return Inventory._(
      storage,
      folder,
      files,
      complete,
      const {},
      JsonLinesFile(storage, path, length: read.lines.length, cut: read.cut),
    );
  }

  /// Inventoried files, by library path.
  Map<String, InventoryEntry> get files => Map.unmodifiable(_files);

  /// Whether the inventory is complete: changes are allowed from then on.
  bool get isComplete => _complete;

  /// Library path of the raw copy of the inventoried file [path].
  String originalPath(String path) => '$folder/originals/$path';

  /// Takes the inventory of every file of the library, outside
  /// `.migration/`, hashing each with [hash]. A file already inventoried
  /// (resumed inventory) or given to reuse, with the same size and
  /// modification date, is not hashed again. [checkCancelled] is called
  /// between two files and stops the inventory by throwing; every file
  /// hashed so far is already written. [onProgress] receives the share of
  /// bytes hashed, from 0 to 1.
  Future<void> take(
    Future<String> Function(String path) hash, {
    void Function()? checkCancelled,
    void Function(double progress)? onProgress,
  }) async {
    if (_complete) throw StateError('Inventory already complete');
    final current = await _currentFiles();
    bool same(InventoryEntry? entry, StorageEntry e) =>
        entry != null && entry.size == e.size && entry.modified == e.modified;
    final first = <Map<String, Object?>>[
      for (final path in _files.keys)
        if (!current.containsKey(path)) {'path': path, 'removed': true},
    ];
    _files.removeWhere((path, _) => !current.containsKey(path));
    final pending = <StorageEntry>[];
    for (final e in current.values) {
      if (same(_files[e.path], e)) continue;
      if (_reuse[e.path] case final reused? when same(reused, e)) {
        first.add(_line(e.path, reused));
        _files[e.path] = reused;
      } else {
        pending.add(e);
      }
    }
    // Also creates the file: an inventory cancelled before its first hash
    // is resumed.
    await _file.append(first);
    final total = pending.fold(0, (sum, e) => sum + e.size);
    var done = 0;
    for (final e in pending) {
      checkCancelled?.call();
      final entry = (
        size: e.size,
        modified: e.modified,
        hash: await hash(e.path),
      );
      await _file.append([_line(e.path, entry)]);
      _files[e.path] = entry;
      done += e.size;
      onProgress?.call(total == 0 ? 1 : done / total);
    }
    await _file.append([
      {'complete': true, 'files': _files.length},
    ]);
    _complete = true;
  }

  static Map<String, Object?> _line(String path, InventoryEntry entry) => {
    'path': path,
    'size': entry.size,
    'modified': entry.modified.microsecondsSinceEpoch,
    'hash': entry.hash,
  };

  /// Checks that every inventoried file is still there, unchanged: at the
  /// path given by [locate] (following the moves of the migration), or as
  /// its raw copy in `originals/` if it was rewritten. A file whose size and
  /// modification date are unchanged is not hashed again. Returns the gaps
  /// as [ReportKind.fileLost] items (inventory path, reason): any gap
  /// blocks the conversion.
  Future<Report> check(
    Future<String> Function(String path) hash, {
    required String Function(String path) locate,
    void Function()? checkCancelled,
    void Function(double progress)? onProgress,
  }) async {
    if (!_complete) throw StateError('Inventory not complete');
    final lost = <ReportItem>[];
    var done = 0;
    for (final MapEntry(key: path, value: entry) in _files.entries) {
      checkCancelled?.call();
      final found =
          await _storage.stat(originalPath(path)) ??
          await _storage.stat(locate(path));
      if (found == null || found.isDirectory) {
        lost.add(ReportItem(path, 'missing'));
      } else if (found.size != entry.size ||
          (found.modified != entry.modified &&
              await hash(found.path) != entry.hash)) {
        lost.add(ReportItem(path, 'changed'));
      }
      onProgress?.call(++done / _files.length);
    }
    return Report({if (lost.isNotEmpty) ReportKind.fileLost: lost});
  }

  /// Files of the library outside `.migration/`, by path.
  Future<Map<String, StorageEntry>> _currentFiles() async => {
    for (final e in await _storage.list('', recursive: true))
      if (!e.isDirectory &&
          e.path.split('/').first != migrationFolderName &&
          e.path != _libraryFile &&
          !e.path.endsWith(MountedFolderStorage.tempSuffix))
        e.path: e,
  };
}
