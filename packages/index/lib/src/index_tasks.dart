import 'dart:isolate';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'local_index.dart';

// Writes of the index, each in a background isolate through its own
// connection (SPEC §7.1): the UI isolate only reads the index, read-only
// ([LocalIndex.open]), and refreshes what it shows when the future
// completes.

/// Creates the index at [indexPath], or rebuilds it if its schema changed,
/// before a read-only connection opens it.
Future<void> createIndex(String indexPath) =>
    Isolate.run(() => LocalIndex.open(indexPath).close());

/// Scans [root] following [library] ([scan]), incrementally from the scan
/// stored at [indexPath] unless [full], and stores the result. Returns the
/// issues found, corrupted and orphan node files included, with paths
/// relative to [root]. Nothing is stored if the scan fails.
Future<Report> scanIntoIndex(
  String indexPath,
  String root,
  Library library, {
  bool full = false,
  bool writeNodes = true,
}) => _withIndex(indexPath, (index) async {
  final previous = full ? null : index.scanResult(library.id);
  final result = await scan(
    MountedFolderStorage(root),
    library,
    previous: previous,
    journalPosition: previous?.journalPosition,
    writeNodes: writeNodes,
  );
  index.update(library, result);
  return result.issues +
      Report({
        ReportKind.corrupted: [for (final p in result.corrupted) ReportItem(p)],
        ReportKind.orphanNode: [
          for (final p in result.orphanNodes) ReportItem(p),
        ],
      });
});

/// Scans again the title folder [titlePath] of [library] at [root] only
/// ([scanTitle]), from its rows stored at [indexPath], and stores the
/// result. False, with nothing stored, when the title is not indexed or the
/// folder is no longer a title: the whole library must be scanned instead.
Future<bool> scanTitleIntoIndex(
  String indexPath,
  String root,
  Library library,
  String titlePath,
) => _withIndex(indexPath, (index) async {
  final stored = index.storedTitle(library.id, titlePath);
  if (stored == null) return false;
  final result = await scanTitle(
    MountedFolderStorage(root),
    library,
    stored.titles.single,
    stored: stored,
  );
  if (result.title == null) return false;
  index.updateTitle(library, titlePath, result);
  return true;
});

/// Removes the library [id] and everything indexed for it.
Future<void> removeLibraryFromIndex(String indexPath, LibraryId id) =>
    _withIndex(indexPath, (index) async => index.removeLibrary(id));

/// Runs [task] in a background isolate on a writing connection to the
/// index at [indexPath], closed at the end.
Future<T> _withIndex<T>(
  String indexPath,
  Future<T> Function(LocalIndex index) task,
) => Isolate.run(() async {
  final index = LocalIndex.open(indexPath);
  try {
    return await task(index);
  } finally {
    index.close();
  }
});
