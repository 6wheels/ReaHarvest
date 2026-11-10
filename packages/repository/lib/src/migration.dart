import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'conventions.dart';
import 'mounted_folder_storage.dart';

/// Library description (`libraryFileName` of the library package), left out
/// of the inventory: the application rewrites it during a migration (known
/// values), it is not a file of the user.
const _libraryFile = '.library.json';

/// A file of the inventory: its state before the first change.
typedef InventoryEntry = ({int size, DateTime modified, String hash});

/// No-loss guard of a migration (SPEC §5.8, steps 2 and 5), kept in
/// `.migration/<stamp>/`:
/// - `inventory.json`: every file before the first change (size,
///   modification date, XXH3 hash), saved as it goes so that an interrupted
///   inventory resumes from the files already hashed;
/// - `moves.json`: every move made through [move], in order;
/// - `originals/<path>`: raw copy of each file kept by [keepOriginal]
///   before it is rewritten, under its inventory path.
///
/// [check] then proves that no inventoried file was lost.
final class Migration {
  Migration._(
    this._storage,
    this.folder,
    this._files,
    this._moves,
    this._complete,
  );

  /// Inventory, saved every this many hashed files.
  static const _saveEvery = 50;

  final RepositoryStorage _storage;

  /// Library path of this migration's folder: `.migration/<stamp>`.
  final String folder;

  final Map<String, InventoryEntry> _files;
  final List<(String, String)> _moves;
  bool _complete;

  /// Inventoried files, by library path.
  Map<String, InventoryEntry> get files => Map.unmodifiable(_files);

  /// Whether the inventory is complete: changes are allowed from then on.
  bool get inventoryComplete => _complete;

  String get _inventoryPath => '$folder/inventory.json';

  String get _movesPath => '$folder/moves.json';

  String _originalPath(String path) => '$folder/originals/$path';

  /// A new migration, stamped with [now]; nothing is written before
  /// [takeInventory]. The inventory of a [previous] migration seeds it, at
  /// the current paths of its files: those unchanged since are not hashed
  /// again.
  static Migration start(
    RepositoryStorage storage, {
    DateTime? now,
    Migration? previous,
  }) => Migration._(
    storage,
    '$migrationFolderName/${_stamp(now ?? DateTime.now())}',
    {
      if (previous != null)
        for (final MapEntry(:key, :value) in previous._files.entries)
          previous.locate(key): value,
    },
    [],
    false,
  );

  /// The latest migration of [storage], with its inventory complete or not,
  /// or null if there is none.
  static Future<Migration?> latest(RepositoryStorage storage) async {
    if (await storage.stat(migrationFolderName) == null) return null;
    final stamps = [
      for (final e in await storage.list(migrationFolderName))
        if (e.isDirectory) e.path,
    ]..sort();
    for (final folder in stamps.reversed) {
      final inventory = await _readJson(storage, '$folder/inventory.json');
      if (inventory == null) continue;
      final moves = await _readJson(storage, '$folder/moves.json');
      return Migration._(
        storage,
        folder,
        {
          for (final MapEntry(:key, :value)
              in (inventory['files'] as Map<String, dynamic>).entries)
            key: (
              size: value['size'] as int,
              modified: DateTime.fromMicrosecondsSinceEpoch(
                value['modified'] as int,
              ),
              hash: value['hash'] as String,
            ),
        },
        [
          for (final m in (moves?['moves'] as List<dynamic>?) ?? const [])
            (m[0] as String, m[1] as String),
        ],
        inventory['complete'] as bool,
      );
    }
    return null;
  }

  /// Takes the inventory of every file of the library, outside
  /// `.migration/`, hashing each with [hash]. A file already inventoried
  /// with the same size and modification date is not hashed again (resumed
  /// inventory). [checkCancelled] is called between two files and stops the
  /// inventory by throwing; what is hashed so far is saved. [onProgress]
  /// receives the share of bytes hashed, from 0 to 1.
  Future<void> takeInventory(
    Future<String> Function(String path) hash, {
    void Function()? checkCancelled,
    void Function(double progress)? onProgress,
  }) async {
    if (_complete) throw StateError('Inventory already complete');
    final current = await _currentFiles();
    _files.removeWhere((path, _) => !current.containsKey(path));
    final pending = [
      for (final e in current.values)
        if (_files[e.path] case final f
            when f == null || f.size != e.size || f.modified != e.modified)
          e,
    ];
    final total = pending.fold(0, (sum, e) => sum + e.size);
    var done = 0;
    var unsaved = 0;
    try {
      for (final e in pending) {
        checkCancelled?.call();
        _files[e.path] = (
          size: e.size,
          modified: e.modified,
          hash: await hash(e.path),
        );
        done += e.size;
        onProgress?.call(total == 0 ? 1 : done / total);
        if (++unsaved == _saveEvery) {
          await _saveInventory();
          unsaved = 0;
        }
      }
      _complete = true;
    } finally {
      await _saveInventory();
    }
  }

  /// Moves [from] to [to] (a file or a folder) and records the move.
  Future<void> move(String from, String to) async {
    _requireInventory();
    await _storage.move(from, to);
    _moves.add((from, to));
    await _write(_movesPath, {
      'moves': [
        for (final (a, b) in _moves) [a, b],
      ],
    });
  }

  /// Copies the raw file at [path] into `originals/` under its inventory
  /// path, before it is rewritten. Does nothing for a file that is not
  /// inventoried or already kept.
  Future<void> keepOriginal(String path) async {
    _requireInventory();
    final original = _origin(path);
    if (!_files.containsKey(original)) return;
    final copy = _originalPath(original);
    if (await _storage.stat(copy) != null) return;
    await _storage.write(copy, _storage.read(path));
  }

  /// [RepositoryStorage] for the fixes of this migration: moves are
  /// recorded ([move]), an existing file is kept ([keepOriginal]) before
  /// it is overwritten, and deletion is refused (SPEC §5.8 step 5).
  RepositoryStorage get storage {
    _requireInventory();
    return _GuardedStorage(this);
  }

  /// Path before the recorded moves of the file now at [path] (reverse of
  /// [locate]).
  String _origin(String path) {
    var current = path;
    for (final (from, to) in _moves.reversed) {
      if (current == to) {
        current = from;
      } else if (current.startsWith('$to/')) {
        current = '$from${current.substring(to.length)}';
      }
    }
    return current;
  }

  /// Current library path of the inventoried file [path], following the
  /// recorded moves.
  String locate(String path) {
    var current = path;
    for (final (from, to) in _moves) {
      if (current == from) {
        current = to;
      } else if (current.startsWith('$from/')) {
        current = '$to${current.substring(from.length)}';
      }
    }
    return current;
  }

  /// Checks that every inventoried file is still there, unchanged: at the
  /// path given by the recorded moves, or as its raw copy in `originals/`
  /// if it was rewritten. A file whose size and modification date are
  /// unchanged is not hashed again. Returns the gaps as
  /// [ReportKind.fileLost] items (inventory path, reason): any gap blocks
  /// the conversion.
  Future<Report> check(
    Future<String> Function(String path) hash, {
    void Function()? checkCancelled,
    void Function(double progress)? onProgress,
  }) async {
    _requireInventory();
    final lost = <ReportItem>[];
    var done = 0;
    for (final MapEntry(key: path, value: entry) in _files.entries) {
      checkCancelled?.call();
      // Inventories taken before the library description was left out.
      if (path == _libraryFile) continue;
      final copy = _originalPath(path);
      final found =
          await _storage.stat(copy) ?? await _storage.stat(locate(path));
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

  void _requireInventory() {
    if (!_complete) throw StateError('Inventory not complete');
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

  Future<void> _saveInventory() => _write(_inventoryPath, {
    'complete': _complete,
    'files': {
      for (final MapEntry(:key, :value) in _files.entries)
        key: {
          'size': value.size,
          'modified': value.modified.microsecondsSinceEpoch,
          'hash': value.hash,
        },
    },
  });

  Future<void> _write(String path, Object json) => _storage.write(
    path,
    Stream.value(utf8.encode(const JsonEncoder.withIndent(' ').convert(json))),
  );

  static Future<Map<String, dynamic>?> _readJson(
    RepositoryStorage storage,
    String path,
  ) async {
    if (await storage.stat(path) == null) return null;
    final text = await utf8.decodeStream(storage.read(path));
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// `yyyy-MM-dd_HHmmss_SSS`, sortable; the milliseconds keep apart two
  /// migrations started in the same second.
  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}_'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }
}

final class _GuardedStorage implements RepositoryStorage {
  _GuardedStorage(this._migration);

  final Migration _migration;

  RepositoryStorage get _inner => _migration._storage;

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) =>
      _inner.list(dir, recursive: recursive);

  @override
  Future<StorageEntry?> stat(String path) => _inner.stat(path);

  @override
  Stream<List<int>> read(String path) => _inner.read(path);

  @override
  Future<void> write(String path, Stream<List<int>> content) async {
    if (await _inner.stat(path) != null) await _migration.keepOriginal(path);
    await _inner.write(path, content);
  }

  @override
  Future<void> move(String from, String to) => _migration.move(from, to);

  @override
  Future<void> createDirectory(String path) => _inner.createDirectory(path);

  @override
  Future<void> delete(String path) async =>
      throw UnsupportedError('No file is deleted during a migration: $path');
}
