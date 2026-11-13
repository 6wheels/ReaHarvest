import 'dart:isolate';

import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'content_hash.dart';
import 'free_names.dart';
import 'library_path.dart';
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
/// batch refuses to run while there is one: it can only be there. Reads
/// the journal only, not the inventory.
Future<UnfinishedFix?> unfinishedFixIn(RepositoryStorage storage) async {
  final folder = await Migration.latestFolder(storage);
  if (folder == null) return null;
  final journal = await MigrationJournal.read(storage, folder);
  final fix = journal.unfinishedFix;
  if (fix == null) return null;
  return (folder: folder, fix: fix, path: journal.pathOf(fix) ?? '');
}

/// Throws unless [path], read from a journal, is a path inside the library:
/// a journal in a shared folder is not trusted to name any file.
void _checkInLibrary(String path) {
  if (path.isEmpty ||
      isAbsoluteReference(path) ||
      path.replaceAll(r'\', '/').split('/').contains('..')) {
    throw StateError('Path outside the library in the journal: $path');
  }
}

/// Whether the files [a] and [b] have the same content.
Future<bool> _sameContent(RepositoryStorage storage, String a, String b) async {
  if ((await storage.stat(a))?.size != (await storage.stat(b))?.size) {
    return false;
  }
  final bytesA = await storage.read(a).expand((c) => c).toList();
  final bytesB = await storage.read(b).expand((c) => c).toList();
  if (bytesA.length != bytesB.length) return false;
  for (var i = 0; i < bytesA.length; i++) {
    if (bytesA[i] != bytesB[i]) return false;
  }
  return true;
}

/// Undoes the fix [fix] of [migration] (SPEC §5.8 step 5, #94), on the
/// [storage] of the library (not the guarded one: the steps of an undo are
/// not journaled), between an `undoStart` and an `undoEnd` line. Its
/// operations, read again from the journal (an append that threw may have
/// reached the disk), are reversed from the last one:
/// - a move is moved back when its target exists and its source does not;
///   with no target, it was not made or is already undone; with both, the
///   source came back since (REAPER, a sync client) and the undo stops;
/// - a rewritten file still there gets back the copy named by its line,
///   with the date of the line; the content it had, unless it is already
///   the one of the copy, is kept first under `<migration>/replaced/`;
/// - a created file still there is moved to `<migration>/undone/`, unless
///   an earlier move of the fix, already undone, put a file back there.
///
/// Nothing is deleted. Each step can be repeated: an interrupted undo is
/// run again from the start. Throws before any change if a rewrite has no
/// copy or a line names a path outside the library (a copy outside the
/// migration folder); throws, leaving the fix to undo, if a step fails.
/// Returns the fix as [ReportKind.fixUndone].
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
      case {'op': 'move', 'from': final String from, 'to': final String to}:
        _checkInLibrary(from);
        _checkInLibrary(to);
      case {'op': 'create', 'path': final String path}:
        _checkInLibrary(path);
      case {
        'op': 'rewrite',
        'path': final String path,
        'copy': final String copy,
      }:
        _checkInLibrary(path);
        _checkInLibrary(copy);
        if (!isWithin(copy, migration.folder, caseSensitive: true)) {
          throw StateError('Copy of $path outside the migration: $copy');
        }
        if (await storage.stat(copy) == null) {
          throw StateError('Copy of $path missing: $copy');
        }
      case {'op': 'rewrite', 'path': final String path}:
        throw StateError('No copy recorded to restore $path');
    }
  }
  await journal.startUndo(fix);
  for (final (i, op) in operations.indexed.toList().reversed) {
    switch (op) {
      case {'op': 'move', 'from': final String from, 'to': final String to}:
        if (await storage.stat(to) == null) continue;
        if (await storage.stat(from) != null) {
          throw StateError('Cannot move $to back: $from exists again');
        }
        await storage.move(to, from);
      case {
        'op': 'rewrite',
        'path': final String path,
        'modified': final int modified,
        'copy': final String copy,
      }:
        // Absent: moved back already by an interrupted undo.
        if (await storage.stat(path) == null) continue;
        // What the copy replaces may hold work saved since the fix.
        if (!await _sameContent(storage, path, copy)) {
          await storage.write(
            await freePath(storage, '${migration.folder}/replaced/$path'),
            storage.read(path),
          );
          await storage.write(path, storage.read(copy));
        }
        await storage.setModified(
          path,
          DateTime.fromMicrosecondsSinceEpoch(modified),
        );
      case {'op': 'create', 'path': final String path}:
        // On a resumed undo, the file there may be the one a move of the
        // fix took away, already moved back.
        var movedBack = false;
        for (final before in operations.take(i)) {
          if (before
              case {
                'op': 'move',
                'from': final String from,
                'to': final String to,
              }
              when from == path && await storage.stat(to) == null) {
            movedBack = true;
          }
        }
        if (movedBack) continue;
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
