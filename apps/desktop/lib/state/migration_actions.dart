import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart' show xxh3Hasher;
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import 'library_catalog.dart';
import 'library_scans.dart';
import 'providers.dart';
import 'report_paths.dart';
import 'tasks.dart';

final _log = Logger('library');

/// Migration of a library: fixes, guided move, orphan node deletion and
/// undo of an interrupted fix (SPEC §5.8).
class MigrationActions {
  MigrationActions(this.ref);

  final Ref ref;

  /// End of the last change of each library ([_exclusive]).
  final _changes = <LibraryId, Future<void>>{};

  /// Number of changes of each library running or waiting.
  final _pending = <LibraryId, int>{};

  LibraryEntry _entry(LibraryId id) =>
      ref.read(libraryCatalogProvider).entry(id);

  Future<void> _scan(LibraryEntry entry) =>
      ref.read(libraryScansProvider).scan(entry);

  /// Runs [change] once the previous changes of [library] have ended: a
  /// batch of fixes, an undo and the search for a fix left to undo never
  /// run together on a library (a fix being applied looks interrupted).
  Future<T> _exclusive<T>(LibraryId library, Future<T> Function() change) {
    _pending[library] = (_pending[library] ?? 0) + 1;
    final done = (_changes[library] ?? Future.value())
        .then((_) => change())
        .whenComplete(() => _pending[library] = _pending[library]! - 1);
    _changes[library] = done.then((_) {}, onError: (_) {});
    return done;
  }

  /// Moves the misplaced project [path] of [library] into the title at
  /// [folders] (one folder name per layout level), with its media ("To
  /// sort", SPEC §5.2), as a task whose report is shown at the end. Then
  /// rescans. Returns the report, or null if the move failed.
  Future<Report?> moveToTitle(
    LibraryId library,
    String path,
    List<String> folders,
  ) {
    return _fix(_entry(library), [
      MoveProject(path, folders.join('/')),
    ], (l10n) => l10n.taskMove(p.posix.basename(path)));
  }

  /// Plans of the media normalization of the [titles] of [library] (dry
  /// run of the fix, SPEC §5.8 step 4), by title, computed in an isolate
  /// that can be cancelled ([planNormalizationOn]).
  PlanPreview previewNormalization(LibraryId library, List<String> titles) {
    final entry = _entry(library);
    return planNormalizationOn(
      entry.libraryRoot,
      titles,
      usage: mediaUsage(
        ref.read(localIndexProvider).scanResult(library) ?? const ScanResult(),
      ),
    );
  }

  /// Applies the migration [fixes] to [library] (SPEC §5.8 step 4), as a
  /// task whose report is shown at the end. Then rescans.
  Future<Report?> fix(LibraryId library, List<MigrationFix> fixes) =>
      _fix(_entry(library), fixes, (l10n) => l10n.taskFix(fixes.length));

  /// Runs [fixes] on [entry] as a batch in one isolate, so that no file is
  /// lost (SPEC §5.8 step 5, [runMigrationBatchOn]), its steps shown under
  /// the task. Then, also after a cancellation, the values of the folders
  /// moved or declared join the known values and the library is rescanned.
  /// A cancelled batch ends the task with the report of what was done.
  /// While a fix of the library is left to undo, runs nothing and offers
  /// to undo it instead ([_offerUndo]). Waits for the changes of the
  /// library already running ([_exclusive]): its task is then shown at
  /// once, waiting, and ends cancelled if a fix is left to undo.
  Future<Report?> _fix(
    LibraryEntry entry,
    List<MigrationFix> fixes,
    String Function(AppLocalizations l10n) label,
  ) {
    final tasks = ref.read(tasksProvider.notifier);
    if ((_pending[entry.id] ?? 0) == 0) {
      return _exclusive(entry.id, () async {
        if (await _offerUndo(entry)) return null;
        return tasks.run(
          label,
          (task) => _batch(entry, fixes, task),
          openReport: true,
        );
      });
    }
    return tasks.run(label, (task) {
      task.step((l10n) => l10n.taskStepWaiting);
      return _exclusive(entry.id, () async {
        if (await _offerUndo(entry)) throw const TaskCancelled();
        return _batch(entry, fixes, task);
      });
    }, openReport: true);
  }

  /// The batch of [_fix], under its [task].
  Future<Report> _batch(
    LibraryEntry entry,
    List<MigrationFix> fixes,
    TaskControl task,
  ) async {
    final root = entry.libraryRoot;
    // From the index: stale for the titles changed by the previous fixes
    // of the batch, which can only block more (SPEC §5.8).
    final usage = mediaUsage(
      ref.read(localIndexProvider).scanResult(entry.id) ?? const ScanResult(),
    );
    BatchResult? result;
    try {
      result = await runMigrationBatchOn(
        root,
        fixes,
        usage: usage,
        hasherOf: xxh3Hasher,
        reporter: _TaskReporter(task, entry.displayName),
      );
    } finally {
      // Also after a cancellation: the library shows what was moved.
      task.step((l10n) => l10n.taskStepScan);
      if (result != null) {
        final added = await addKnownPaths(
          MountedFolderStorage(root),
          result.knownPaths,
        );
        if (added.isNotEmpty) {
          _log.info(
            'Known values of ${entry.displayName} added: '
            '${added.join(', ')}',
          );
        }
      }
      await _scan(entry);
    }
    final report = rootedReport(root, result.report);
    // What was done before stopping is kept: the report tells it.
    if (result.cancelled) throw TaskCancelled(report);
    return report;
  }

  /// Offers to undo the fix left to undo in [entry], if any (SPEC §5.8 step
  /// 5, #94): the dialog of [interruptedFixesProvider]. Returns whether
  /// there is one. Waits for the changes of the library already running.
  Future<bool> offerUndo(LibraryEntry entry) =>
      _exclusive(entry.id, () => _offerUndo(entry));

  /// [offerUndo], for a change of the library already running.
  Future<bool> _offerUndo(LibraryEntry entry) async {
    final fix = await unfinishedFixOn(entry.libraryRoot);
    if (fix == null) return false;
    _log.warning(
      'Fix of ${fix.path} in ${entry.displayName} left to undo '
      '(${fix.folder}, fix ${fix.fix})',
    );
    ref.read(interruptedFixesProvider.notifier).offer((
      library: entry.id,
      name: entry.displayName,
      path: fix.path,
    ));
    return true;
  }

  /// Scans every library, then offers to undo the fixes left to undo
  /// ([offerUndo]): what the application does when it starts.
  Future<void> startup() async {
    await ref.read(libraryScansProvider).scanAll();
    for (final entry in ref.read(settingsProvider).libraries) {
      try {
        await offerUndo(entry);
      } on Object catch (error) {
        _log.warning('Journal of ${entry.displayName} unreadable', error);
      }
    }
  }

  /// Undoes the fix left to undo in [library] (SPEC §5.8 step 5,
  /// [undoUnfinishedFixOn]), as a task whose report opens at the end. Then
  /// rescans. Waits for the changes of the library already running.
  Future<Report?> undoInterruptedFix(LibraryId library) {
    final entry = _entry(library);
    final root = entry.libraryRoot;
    return _exclusive(
      library,
      () => ref.read(tasksProvider.notifier).run((l10n) => l10n.taskUndoFix, (
        task,
      ) async {
        try {
          return rootedReport(
            root,
            await undoUnfinishedFixOn(root, hasherOf: xxh3Hasher),
          );
        } finally {
          task.step((l10n) => l10n.taskStepScan);
          await _scan(entry);
        }
      }, openReport: true),
    );
  }

  /// Deletes the `.node.json` file [path] of [library], found in a folder
  /// without project (#54). Then rescans. Throws [ArgumentError] for any
  /// other file.
  Future<void> deleteOrphanNode(LibraryId library, String path) async {
    if (p.posix.basename(path) != nodeFileName) {
      throw ArgumentError.value(path, 'path', 'Not a node file');
    }
    final entry = _entry(library);
    final root = entry.libraryRoot;
    final known = ref.read(localIndexProvider).scanResult(library);
    if (!(known?.orphanNodes.contains(path) ?? false)) {
      throw ArgumentError.value(path, 'path', 'Not an orphan node file');
    }
    await MountedFolderStorage(root).delete(path);
    _log.info('Orphan node file $path of ${entry.displayName} deleted');
    await _scan(entry);
  }
}

/// [TaskReporter] of a batch over the [task] of the library [name]: steps
/// shown with their labels, log lines prefixed with the library.
final class _TaskReporter implements TaskReporter {
  _TaskReporter(this.task, this.name);

  final TaskControl task;
  final String name;

  @override
  void step(TaskStep step, {int? index, int? total}) => task.step(
    (l10n) => switch (step) {
      TaskStep.inventory => l10n.taskStepInventory,
      TaskStep.fix => l10n.taskStepFix(index!, total!),
      TaskStep.check => l10n.taskStepCheck,
    },
  );

  @override
  void progress(double value) => task.progress(value);

  @override
  bool get isCancelled => task.isCancelled;

  @override
  Future<void> get whenCancelled => task.whenCancelled;

  @override
  void log(String message, {bool warning = false}) =>
      _log.log(warning ? Level.WARNING : Level.INFO, '$name: $message');
}

final migrationActionsProvider = Provider<MigrationActions>(
  MigrationActions.new,
);

/// A fix left to undo in a library, offered to be undone: the library, its
/// display name and the library path of the fix.
typedef InterruptedFix = ({LibraryId library, String name, String path});

/// Fixes offered to be undone, one per library, oldest first; the
/// interface shows them one after the other (SPEC §5.8 step 5, #94).
class InterruptedFixes extends Notifier<List<InterruptedFix>> {
  @override
  List<InterruptedFix> build() => const [];

  /// Offers [fix], unless its library already has one offered.
  void offer(InterruptedFix fix) {
    if (state.any((f) => f.library == fix.library)) return;
    state = [...state, fix];
  }

  /// Removes the offer of [library], answered.
  void answered(LibraryId library) =>
      state = [...state.where((f) => f.library != library)];
}

final interruptedFixesProvider =
    NotifierProvider<InterruptedFixes, List<InterruptedFix>>(
      InterruptedFixes.new,
    );
