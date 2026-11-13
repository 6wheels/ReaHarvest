import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'content_hash.dart';
import 'conventions.dart';
import 'guarded_storage.dart';
import 'inventory.dart';
import 'migration_journal.dart';

/// A position in the migration journals: the migration folder and the
/// number of lines of its journal already taken into account.
typedef JournalPosition = ({String folder, int line});

/// A migration of a library (SPEC §5.8, steps 2 and 5), kept in
/// `.migration/<stamp>/`: its [inventory], its [journal] and the guarded
/// [storage] given to its fixes. Folders in the former format
/// (`inventory.json`, `moves.json`) are ignored.
final class Migration {
  Migration._(this._storage, this.inventory, this.journal);

  final RepositoryStorage _storage;

  /// Every file before the first change.
  final Inventory inventory;

  /// Every change made through [storage].
  final MigrationJournal journal;

  /// Library path of this migration's folder: `.migration/<stamp>`.
  String get folder => inventory.folder;

  /// [RepositoryStorage] for the fixes of this migration ([GuardedStorage]);
  /// requires a complete inventory.
  RepositoryStorage get storage => GuardedStorage(_storage, inventory, journal);

  /// [hash], answered from the inventory for a file other than a project
  /// (projects are rewritten in place, keeping their date) found at its
  /// inventory place, following the moves, with its size and date
  /// unchanged.
  ContentHash inventoryHash(ContentHash hash) => (path) async {
    if (!isProjectFile(path)) {
      final origin = journal.origin(path);
      final entry = origin == null ? null : inventory.entryOf(origin);
      if (entry != null) {
        final found = await _storage.stat(path);
        if (found != null &&
            found.size == entry.size &&
            found.modified == entry.modified) {
          return entry.hash;
        }
      }
    }
    return hash(path);
  };

  /// This migration, its journal read again from the storage: a line whose
  /// append threw may be on disk.
  Future<Migration> reread() async => Migration._(
    _storage,
    inventory,
    await MigrationJournal.read(_storage, folder),
  );

  /// A new migration, stamped with [now]; nothing is written before its
  /// inventory is taken. The inventory of a [previous] migration seeds it,
  /// at the current paths of its files: those unchanged since are not
  /// hashed again.
  static Migration start(
    RepositoryStorage storage, {
    DateTime? now,
    Migration? previous,
  }) {
    final folder = '$migrationFolderName/${_stamp(now ?? DateTime.now())}';
    return Migration._(
      storage,
      Inventory(
        storage,
        folder,
        reuse: {
          if (previous != null)
            for (final MapEntry(:key, :value)
                in previous.inventory.files.entries)
              previous.journal.locate(key): value,
        },
      ),
      MigrationJournal(storage, folder),
    );
  }

  /// The latest migration of [storage], with its inventory complete or not,
  /// or null if there is none.
  static Future<Migration?> latest(RepositoryStorage storage) async {
    for (final folder in (await _folders(storage)).reversed) {
      final inventory = await Inventory.read(storage, folder);
      if (inventory == null) continue;
      return Migration._(
        storage,
        inventory,
        await MigrationJournal.read(storage, folder),
      );
    }
    return null;
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

/// Migration folders of [storage], oldest first.
Future<List<String>> _folders(RepositoryStorage storage) async {
  if (await storage.stat(migrationFolderName) == null) return [];
  return [
    for (final e in await storage.list(migrationFolderName))
      if (e.isDirectory) e.path,
  ]..sort();
}

/// Current paths of the files rewritten by a migration (or restored by an
/// undo) after [position], over every migration folder from
/// `position.folder` on, and the position of the end of the latest journal.
/// A rewritten project may keep its size and date (SPEC §4.2): the scan
/// reads these paths again. A null [position] gives no path; with no
/// migration at all, the position returned is before any journal.
Future<({Set<String> paths, JournalPosition position})> rewrittenSince(
  RepositoryStorage storage,
  JournalPosition? position,
) async {
  final folders = await _folders(storage);
  if (folders.isEmpty) {
    return (paths: <String>{}, position: position ?? (folder: '', line: 0));
  }
  if (position == null) {
    final journal = await MigrationJournal.read(storage, folders.last);
    return (
      paths: <String>{},
      position: (folder: folders.last, line: journal.length),
    );
  }
  var paths = <String>{};
  var end = position;
  for (final folder in folders) {
    final order = folder.compareTo(position.folder);
    if (order < 0) continue;
    final journal = await MigrationJournal.read(storage, folder);
    paths = {
      for (final path in paths) journal.locate(path),
      ...journal.rewrittenAfter(order == 0 ? position.line : 0),
    };
    end = (folder: folder, line: journal.length);
  }
  return (paths: paths, position: end);
}
