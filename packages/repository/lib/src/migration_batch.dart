import 'dart:async';
import 'dart:isolate';

import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'fixes.dart';
import 'migration.dart';
import 'mounted_folder_storage.dart';
import 'undo.dart';

/// Outcome of a batch of migration fixes: its [report] (library paths), the
/// folders to add to the known values, and whether it was cancelled.
typedef BatchResult = ({
  Report report,
  List<String> knownPaths,
  bool cancelled,
});

/// Thrown by the batch when its reporter tells it was cancelled.
final class _Cancelled implements Exception {
  const _Cancelled();
}

/// Runs [fixes] on [storage] so that no file is lost (SPEC §5.8 step 5),
/// telling each step to [reporter]: first a new inventory (or the
/// interrupted one resumed), reusing the hashes of the previous one; then
/// the fixes one by one, one log line each; then the inventory check, whose
/// gaps are reported as errors. A folder "moved" to its own place is only
/// declared; with nothing else, no inventory is taken. Cancellable between
/// two files and between two fixes: the result then tells what was done,
/// with `cancelled: true`. [usage] tells the projects referencing each
/// media ([mediaUsage]). Runs in the calling isolate.
///
/// A fix that fails is undone at once ([undoFix], SPEC §5.8 step 5) and
/// reported under [ReportKind.fixFailed] and [ReportKind.fixUndone]; the
/// batch goes on, and the fix gives no known value. If its undo fails too,
/// it is reported under [ReportKind.undoFailed] and the batch stops there,
/// without check: the fix stays to undo. Throws [FixToUndo] before any
/// change while a fix of the library is left to undo.
Future<BatchResult> runMigrationBatch(
  RepositoryStorage storage,
  List<MigrationFix> fixes, {
  required Map<String, List<String>> usage,
  required Future<String> Function(String path) hash,
  required TaskReporter reporter,
  DateTime? now,
}) async {
  bool inPlace(MigrationFix fix) => fix is MoveFolder && fix.target == fix.path;
  final declared = [for (final f in fixes.where(inPlace)) f.path];
  final moves = [...fixes.where((f) => !inPlace(f))];
  final applied = <MigrationFix>[];
  var report = Report({
    ReportKind.valueDeclared: [for (final path in declared) ReportItem(path)],
  });
  for (final path in declared) {
    reporter.log('folder $path kept in place');
  }
  BatchResult result({required bool cancelled}) => (
    report: report,
    knownPaths: [
      ...declared,
      for (final f in applied)
        ?switch (f) {
          MoveFolder(:final target) => target,
          MoveProject(:final titleDir) ||
          LiftProject(:final titleDir) => titleDir,
          // The title stays where it is.
          NormalizeMedia() => null,
        },
    ],
    cancelled: cancelled,
  );
  void checkCancelled() {
    if (reporter.isCancelled) throw const _Cancelled();
  }

  if (moves.isEmpty) return result(cancelled: false);
  try {
    // A fresh inventory for each batch, unless one was interrupted: files
    // changed or added since the previous one are covered.
    final previous = await Migration.latest(storage);
    if (previous?.journal.unfinishedFix case final fix?) {
      throw FixToUndo(previous!.journal.pathOf(fix) ?? '');
    }
    var migration = previous != null && !previous.inventory.isComplete
        ? previous
        : Migration.start(storage, now: now, previous: previous);
    reporter.step(TaskStep.inventory);
    await migration.inventory.take(
      hash,
      checkCancelled: checkCancelled,
      onProgress: reporter.progress,
    );
    for (final (i, fix) in moves.indexed) {
      checkCancelled();
      reporter.step(TaskStep.fix, index: i + 1, total: moves.length);
      reporter.progress(i / moves.length);
      final previousFix = migration.journal.lastFix;
      Report done;
      var threw = false;
      try {
        done = await applyFixes(migration, [fix], usage: usage, hash: hash);
      } on Object catch (error) {
        // A line of its journal could not be written.
        threw = true;
        done = Report({
          ReportKind.fixFailed: [ReportItem(fix.path, '$error')],
        });
      }
      if (!threw && migration.journal.unfinishedFix == null) {
        applied.add(fix);
      } else {
        try {
          // Read again: a line whose append threw may be on disk (#92),
          // its end line included. This fix is undone if its start line
          // is there, whether it ended or not.
          migration = await migration.reread();
          final failed = migration.journal.lastFix;
          if (failed != null && failed != previousFix) {
            done += await undoFix(storage, migration, failed);
            migration = await migration.reread();
          }
        } on Object catch (error) {
          done += Report({
            ReportKind.undoFailed: [ReportItem(fix.path, '$error')],
          });
          reporter.log('$fix\n$done', warning: true);
          report += done;
          return result(cancelled: false);
        }
      }
      reporter.log('$fix\n$done', warning: done.hasErrors);
      report += done;
    }
    checkCancelled();
    reporter.step(TaskStep.check);
    final check = await migration.inventory.check(
      hash,
      locate: migration.journal.locate,
      checkCancelled: checkCancelled,
      onProgress: reporter.progress,
    );
    reporter.log(
      'inventory checked${check.isEmpty ? ', no file lost' : '\n$check'}',
      warning: check.hasErrors,
    );
    report += check;
  } on _Cancelled {
    reporter.log(
      'cancelled after ${applied.length} of ${moves.length} fixes',
      warning: true,
    );
    return result(cancelled: true);
  }
  return result(cancelled: false);
}

/// Runs [runMigrationBatch] on the library folder [root], in one isolate,
/// hashing with `hasherOf(storage)` ([hasherOf] must be a top-level
/// function). The steps, progress and log lines of the isolate are given to
/// [reporter]; its cancellation is sent to the isolate as a message.
/// Rethrows an error of the batch.
Future<BatchResult> runMigrationBatchOn(
  String root,
  List<MigrationFix> fixes, {
  required Map<String, List<String>> usage,
  required Future<String> Function(String) Function(RepositoryStorage) hasherOf,
  required TaskReporter reporter,
}) async {
  final events = ReceivePort();
  final done = Completer<BatchResult>();
  SendPort? control;
  var cancelled = false;
  // Pushed to the isolate as soon as the reporter is cancelled; before the
  // isolate gives its port, sent when the port arrives.
  unawaited(
    reporter.whenCancelled.then((_) {
      cancelled = true;
      control?.send(null);
    }),
  );
  events.listen((message) {
    switch (message) {
      case final SendPort port:
        control = port;
        if (cancelled) port.send(null);
      case (final TaskStep step, final int? index, final int? total):
        reporter.step(step, index: index, total: total);
      case final double value:
        reporter.progress(value);
      case (final String text, final bool warning):
        reporter.log(text, warning: warning);
      case final BatchResult result:
        done.complete(result);
    }
  });
  try {
    await _spawn(root, fixes, usage, hasherOf, events.sendPort);
    // Sent last on the same port: every event before it was given.
    return await done.future;
  } finally {
    events.close();
  }
}

/// Runs the batch in a new isolate (a separate function: the closure must
/// capture nothing else).
Future<void> _spawn(
  String root,
  List<MigrationFix> fixes,
  Map<String, List<String>> usage,
  Future<String> Function(String) Function(RepositoryStorage) hasherOf,
  SendPort events,
) => Isolate.run(() async {
  final control = ReceivePort();
  final reporter = _PortReporter(events);
  control.listen((_) => reporter.cancel());
  events.send(control.sendPort);
  try {
    final storage = MountedFolderStorage(root);
    events.send(
      await runMigrationBatch(
        storage,
        fixes,
        usage: usage,
        hash: hasherOf(storage),
        reporter: reporter,
      ),
    );
  } finally {
    control.close();
  }
});

/// [TaskReporter] of the isolate: sends the events to [_events].
final class _PortReporter implements TaskReporter {
  _PortReporter(this._events);

  final SendPort _events;

  final _cancelled = Completer<void>();

  /// Called when the cancellation message arrives.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  void step(TaskStep step, {int? index, int? total}) =>
      _events.send((step, index, total));

  @override
  void progress(double value) => _events.send(value);

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  @override
  void log(String message, {bool warning = false}) =>
      _events.send((message, warning));
}
