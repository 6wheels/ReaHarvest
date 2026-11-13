import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_turns.dart';
import 'providers.dart';
import 'report_paths.dart';
import 'tasks.dart';

final _log = Logger('library.scans');

/// Scans of the libraries into the local index (SPEC §5.1, §5.2, §8).
class LibraryScans {
  LibraryScans(this.ref);

  final Ref ref;

  /// Scans every configured library, one after the other, as a background
  /// task cancellable between two libraries (SPEC §5.2), each in the turn
  /// of its library ([LibraryTurns]). A failed library does not stop the
  /// others; it is reported. A [full] scan reads every file again, changed
  /// or not.
  Future<void> scanAll({bool full = false}) async {
    final entries = ref.read(settingsProvider).libraries;
    if (entries.isEmpty) return;
    await ref.read(tasksProvider.notifier).run(
      (l10n) => full ? l10n.taskFullScan : l10n.taskScanAll,
      (task) async {
        var report = const Report();
        for (final (i, entry) in entries.indexed) {
          task.checkCancelled();
          try {
            report += await ref
                .read(libraryTurnsProvider)
                .run(entry.id, () => _scanReport(entry, full: full));
          } on Object catch (error) {
            report += Report({
              ReportKind.scanFailed: [ReportItem(entry.libraryRoot, '$error')],
            });
          }
          task.progress((i + 1) / entries.length);
        }
        return report;
      },
    );
  }

  /// Scans [entry]; failures are only logged, the library stays configured
  /// and is scanned again on next start. Takes no turn: for the rescan that
  /// ends a change, inside the turn of [entry] ([LibraryTurns]).
  Future<void> scan(LibraryEntry entry) async {
    try {
      await _scanReport(entry);
    } on Object catch (error) {
      _log.warning('Scan of ${entry.displayName} failed', error);
    }
  }

  /// Scans again the folder of [title] of [entry] only, in an isolate,
  /// after an action on one of its versions (SPEC §8); the whole library is
  /// scanned instead when it was never indexed, or when the folder is no
  /// longer a title (the folders around it may have changed). Failures are
  /// only logged, like [scan]. Takes no turn: inside the turn of [entry].
  Future<void> rescanTitle(LibraryEntry entry, Title title) async {
    try {
      final root = entry.libraryRoot;
      final library = await readLibrary(MountedFolderStorage(root));
      final index = ref.read(localIndexProvider);
      final stored = library == null ? null : index.scanResult(library.id);
      final result = stored == null
          ? null
          : await scanTitleFolder(root, library!, title, stored: stored);
      if (result?.title == null) {
        await _scanReport(entry);
        return;
      }
      index.updateTitle(library!, title.path, result!);
      ref.read(indexRevisionProvider.notifier).bump();
      _log.info('Rescanned ${title.path} of ${entry.displayName}');
    } on Object catch (error) {
      _log.warning(
        'Rescan of ${title.path} of ${entry.displayName} failed',
        error,
      );
    }
  }

  /// Scans [entry] as a task whose report is shown at the end, in the turn
  /// of its library.
  Future<void> scanTask(LibraryEntry entry) => ref
      .read(tasksProvider.notifier)
      .run(
        (l10n) => l10n.taskScan(entry.displayName),
        (_) => _scanReport(entry),
        openReport: true,
        library: entry.id,
      );

  /// Scans [entry] in an isolate, incrementally from the stored scan unless
  /// [full] (the files rewritten by a migration since read again), and
  /// updates the index.
  /// Unavailable libraries are skipped. Reports the problems found (SPEC
  /// §5.2).
  Future<Report> _scanReport(LibraryEntry entry, {bool full = false}) async {
    final root = entry.libraryRoot;
    final storage = MountedFolderStorage(root);
    final library = await readLibrary(storage);
    if (library == null) {
      _log.warning('Library ${entry.displayName} unavailable at $root');
      return Report({
        ReportKind.libraryUnavailable: [ReportItem(root)],
      });
    }
    final index = ref.read(localIndexProvider);
    final result = await scanFolder(
      root,
      library,
      previous: full ? null : index.scanResult(library.id),
      journalPosition: full ? null : index.journalPosition(library.id),
    );
    index.update(library, result);
    ref.read(indexRevisionProvider.notifier).bump();
    _log.info(
      'Scanned ${entry.displayName}: ${result.titles.length} titles, '
      '${result.issues.items.values.fold(0, (n, i) => n + i.length)} '
      'to sort, ${result.corrupted.length} corrupted',
    );
    return Report({
          ReportKind.libraryScanned: [ReportItem(root)],
          ReportKind.corrupted: absoluteItems(root, result.corrupted),
          ReportKind.orphanNode: absoluteItems(root, result.orphanNodes),
        }) +
        rootedReport(root, result.issues);
  }
}

final libraryScansProvider = Provider<LibraryScans>(LibraryScans.new);

extension LibraryScan on Ref {
  /// Scans [entry], failures only logged ([LibraryScans.scan]), inside the
  /// turn of [entry].
  Future<void> scanLibrary(LibraryEntry entry) =>
      read(libraryScansProvider).scan(entry);

  /// Scans again the folder of [title] of [entry] only, failures only
  /// logged ([LibraryScans.rescanTitle]), inside the turn of [entry].
  Future<void> rescanTitle(LibraryEntry entry, Title title) =>
      read(libraryScansProvider).rescanTitle(entry, title);
}
