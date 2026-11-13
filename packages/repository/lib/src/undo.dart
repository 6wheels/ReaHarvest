import 'dart:isolate';

import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'content_hash.dart';
import 'free_names.dart';
import 'migration.dart';
import 'migration_journal.dart';
import 'mounted_folder_storage.dart';

/// A fix left to undo (SPEC §5.8 step 5, #94): failed and not undone, or
/// interrupted. [folder] is its migration folder, [path] the library path
/// of the folder or project it was fixing.
typedef UnfinishedFix = ({String folder, int fix, String path});

/// Thrown by a batch of fixes while a fix of the library is left to undo.
final class FixToUndo implements Exception {
  const FixToUndo(this.path);

  /// Library path of the fix to undo.
  final String path;

  @override
  String toString() => 'The fix of $path must be undone first';
}

/// The fix left to undo in the latest migration of [storage], or null. A
/// batch refuses to run while there is one: it can only be there.
Future<UnfinishedFix?> unfinishedFixIn(RepositoryStorage storage) async {
  final migration = await Migration.latest(storage);
  final fix = migration?.journal.unfinishedFix;
  if (fix == null) return null;
  return (
    folder: migration!.folder,
    fix: fix,
    path: migration.journal.pathOf(fix) ?? '',
  );
}

/// Undoes the fix [fix] of [migration] (SPEC §5.8 step 5, #94), on the
/// [storage] of the library (not the guarded one: the steps of an undo are
/// not journaled), between an `undoStart` and an `undoEnd` line. Its
/// operations, read again from the journal (an append that threw may have
/// reached the disk), are reversed from the last one:
/// - a move is moved back when its target exists and its source does not;
///   otherwise it was not made, or is already undone;
/// - a rewritten file still there gets back the copy named by its line,
///   with the date of the line; the content it had is kept first under
///   `<migration>/replaced/`;
/// - a created file still there is moved to `<migration>/undone/`.
///
/// Nothing is deleted. Each step can be repeated: an interrupted undo is
/// run again from the start. Throws before any change if a rewrite has no
/// copy; throws, leaving the fix to undo, if a step fails. Returns the fix
/// as [ReportKind.fixUndone].
Future<Report> undoFix(
  RepositoryStorage storage,
  Migration migration,
  int fix,
) async {
  final journal = await MigrationJournal.read(storage, migration.folder);
  final operations = journal.operationsOf(fix);
  // Checked before the first change: no undo stopped halfway for good.
  for (final op in operations) {
    switch (op) {
      case {
        'op': 'rewrite',
        'path': final String path,
        'copy': final String copy,
      }:
        if (await storage.stat(copy) == null) {
          throw StateError('Copy of $path missing: $copy');
        }
      case {'op': 'rewrite', 'path': final String path}:
        throw StateError('No copy recorded to restore $path');
    }
  }
  await journal.startUndo(fix);
  for (final op in operations.reversed) {
    switch (op) {
      case {'op': 'move', 'from': final String from, 'to': final String to}:
        if (await storage.stat(to) != null &&
            await storage.stat(from) == null) {
          await storage.move(to, from);
        }
      case {
        'op': 'rewrite',
        'path': final String path,
        'modified': final int modified,
        'copy': final String copy,
      }:
        // Absent: moved back already by an interrupted undo.
        if (await storage.stat(path) == null) continue;
        // What the copy replaces may hold work saved since the fix.
        await storage.write(
          await freePath(storage, '${migration.folder}/replaced/$path'),
          storage.read(path),
        );
        await storage.write(path, storage.read(copy));
        await storage.setModified(
          path,
          DateTime.fromMicrosecondsSinceEpoch(modified),
        );
      case {'op': 'create', 'path': final String path}:
        if (await storage.stat(path) case StorageEntry(isDirectory: false)) {
          await storage.move(
            path,
            await freePath(storage, '${migration.folder}/undone/$path'),
          );
        }
    }
  }
  await journal.endUndo(fix);
  return Report({
    ReportKind.fixUndone: [ReportItem(journal.pathOf(fix) ?? '')],
  });
}

/// Undoes the fix left to undo in [storage] ([unfinishedFixIn], [undoFix]),
/// then checks the inventory of its migration, hashing with [hash]. Returns
/// the undo and the gaps of the check; empty when there is nothing to undo.
Future<Report> undoUnfinishedFix(
  RepositoryStorage storage, {
  required ContentHash hash,
}) async {
  final migration = await Migration.latest(storage);
  final fix = migration?.journal.unfinishedFix;
  if (fix == null) return const Report();
  final undone = await undoFix(storage, migration!, fix);
  final journal = await MigrationJournal.read(storage, migration.folder);
  return undone + await migration.inventory.check(hash, locate: journal.locate);
}

/// [unfinishedFixIn] of the library folder [root], in an isolate.
Future<UnfinishedFix?> unfinishedFixOn(String root) =>
    Isolate.run(() => unfinishedFixIn(MountedFolderStorage(root)));

/// [undoUnfinishedFix] of the library folder [root], in an isolate,
/// hashing with `hasherOf(storage)` ([hasherOf] must be a top-level
/// function).
Future<Report> undoUnfinishedFixOn(
  String root, {
  required ContentHash Function(RepositoryStorage) hasherOf,
}) => Isolate.run(() {
  final storage = MountedFolderStorage(root);
  return undoUnfinishedFix(storage, hash: hasherOf(storage));
});
