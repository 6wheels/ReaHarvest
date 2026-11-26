import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart'
    show LibraryId, Report;

import '../l10n/app_localizations.dart';
import 'library_turns.dart';

/// [queued]: waiting for the turn of its library ([LibraryTurns]).
/// [warning]: finished, its report holds warnings and no error.
enum TaskState { queued, running, done, warning, failed, cancelled }

/// Severity of an instant entry of the notification zone
/// ([TasksNotifier.notify]).
enum NoticeLevel { info, warning, error }

/// Thrown by [TaskControl.checkCancelled] to stop a cancelled task; a task
/// rethrows it with the [report] of what it did before stopping.
final class TaskCancelled implements Exception {
  const TaskCancelled([this.report]);

  final Report? report;
}

/// Handle given to a running task: reports progress and tells whether the
/// task was cancelled. Cancellation is cooperative, between two steps.
final class TaskControl {
  TaskControl._(this._notifier, this._id);

  final TasksNotifier _notifier;
  final int _id;

  /// Whether the task was asked to stop.
  bool get isCancelled => _notifier._task(_id).cancelling;

  /// Completes when the task is asked to stop.
  Future<void> get whenCancelled => _notifier._cancels[_id]!.future;

  /// Throws [TaskCancelled] if the task was asked to stop.
  void checkCancelled() {
    if (isCancelled) throw const TaskCancelled();
  }

  /// Sets the progress, from 0 to 1.
  void progress(double value) =>
      _notifier._update(_id, (t) => t._with(progress: value));

  /// Starts the sub-step [label], shown under the task; its progress is
  /// unknown until [progress] is called.
  void step(String Function(AppLocalizations l10n) label) {
    _notifier._update(_id, (t) => t._atStep(label));
    final task = _notifier._task(_id);
    _log.info('${task.label(_english)}: ${label(_english)}');
  }
}

/// A long action shown in the background tasks zone (SPEC §5.2).
@immutable
final class BackgroundTask {
  const BackgroundTask({
    required this.id,
    required this.label,
    this.state = TaskState.running,
    this.progress,
    this.cancelling = false,
    this.error,
    this.report,
    this.openReport = false,
    this.foreground = false,
    this.quiet = false,
    this.cancellable = true,
    this.step,
  });

  final int id;
  final String Function(AppLocalizations l10n) label;
  final TaskState state;

  /// From 0 to 1; null while unknown.
  final double? progress;

  /// Asked to stop, at its next step.
  final bool cancelling;

  /// Why the task failed.
  final String? error;

  /// Report of the finished task, if it produces one.
  final Report? report;

  /// Whether the report is shown as soon as the task ends.
  final bool openReport;

  /// Shown in a popup that blocks the interface until it ends (SPEC §5.2).
  final bool foreground;

  /// Its caller tells the outcome itself: [TasksNotifier.run] rethrows the
  /// failure and throws [TaskCancelled]. Listed like the others.
  final bool quiet;

  /// Stops at its steps when asked; otherwise, Cancel only takes it out of
  /// the queue.
  final bool cancellable;

  /// Current sub-step of a running task, if it tells it.
  final String Function(AppLocalizations l10n)? step;

  bool get isRunning => state == TaskState.running;

  bool get isQueued => state == TaskState.queued;

  /// Done, with warnings, failed or cancelled.
  bool get isFinished => !isRunning && !isQueued;

  /// Whether Cancel applies: queued, or running, cancellable and not asked
  /// to stop yet.
  bool get canCancel => isQueued || (isRunning && cancellable && !cancelling);

  BackgroundTask _with({
    TaskState? state,
    double? progress,
    bool? cancelling,
    String? error,
    Report? report,
  }) => BackgroundTask(
    id: id,
    label: label,
    state: state ?? this.state,
    progress: progress ?? this.progress,
    cancelling: cancelling ?? this.cancelling,
    error: error ?? this.error,
    report: report ?? this.report,
    openReport: openReport,
    foreground: foreground,
    quiet: quiet,
    cancellable: cancellable,
    step: step,
  );

  /// This task at the sub-step [step], with an unknown progress.
  BackgroundTask _atStep(String Function(AppLocalizations l10n) step) =>
      BackgroundTask(
        id: id,
        label: label,
        state: state,
        cancelling: cancelling,
        openReport: openReport,
        foreground: foreground,
        quiet: quiet,
        cancellable: cancellable,
        step: step,
      );
}

final _log = Logger('tasks');

/// Logs are in English, whatever the language of the interface.
final _english = lookupAppLocalizations(const Locale('en'));

/// Background tasks, oldest first.
class TasksNotifier extends Notifier<List<BackgroundTask>> {
  var _next = 0;

  /// Completed by [cancel], for each running or queued task.
  final _cancels = <int, Completer<void>>{};

  /// Completed by [cancel], for each queued task: it leaves the queue.
  final _queued = <int, Completer<void>>{};

  @override
  List<BackgroundTask> build() => const [];

  /// Runs [body] as a task labelled [label]. Returns its result, or null if
  /// it failed or was cancelled (the outcome stays in the task); a [quiet]
  /// one, whose caller tells the outcome, rethrows the failure of [body], or
  /// throws [TaskCancelled]; every task stays listed with its final
  /// state. A [Report] result is kept in the task, which fails if it holds
  /// errors; with [openReport], the tasks zone opens it at the end (actions
  /// launched by the user, SPEC §5.2). A task writing in [library] is added
  /// at once, queued, and runs in the turn of its library ([LibraryTurns]);
  /// cancelled while queued, it ends at once and [body] never runs. A
  /// [foreground] task blocks the interface in a popup while it waits and
  /// runs ([ForegroundTaskHost]). A task not [cancellable] can only be
  /// cancelled while queued.
  Future<T?> run<T>(
    String Function(AppLocalizations l10n) label,
    Future<T> Function(TaskControl task) body, {
    bool openReport = false,
    bool foreground = false,
    bool quiet = false,
    bool cancellable = true,
    LibraryId? library,
  }) async {
    final id = _next++;
    _cancels[id] = Completer<void>();
    state = [
      ...state,
      BackgroundTask(
        id: id,
        label: label,
        state: library == null ? TaskState.running : TaskState.queued,
        openReport: openReport,
        foreground: foreground,
        quiet: quiet,
        cancellable: cancellable,
      ),
    ];
    if (library == null) return _execute(id, body);
    _log.info('${label(_english)}: queued');
    final left = _queued[id] = Completer<void>();
    final turn = ref.read(libraryTurnsProvider).run(library, () async {
      if (_queued.remove(id)!.isCompleted) return null;
      _update(id, (t) => t._with(state: TaskState.running));
      return _execute(id, body);
    });
    final cancelled = left.future.then<T?>(
      (_) => quiet ? throw const TaskCancelled() : null,
    );
    return Future.any([turn, cancelled]);
  }

  /// Runs [body] as the running task [id], to its outcome.
  Future<T?> _execute<T>(
    int id,
    Future<T> Function(TaskControl task) body,
  ) async {
    _log.info('${_task(id).label(_english)}: started');
    final quiet = _task(id).quiet;
    try {
      final result = await body(TaskControl._(this, id));
      final report = result is Report ? result : null;
      _update(
        id,
        (t) => t._with(
          state: switch (report) {
            Report(hasErrors: true) => TaskState.failed,
            Report(hasWarnings: true) => TaskState.warning,
            _ => TaskState.done,
          },
          progress: 1,
          report: report,
        ),
      );
      return result;
    } on TaskCancelled catch (e) {
      _update(id, (t) => t._with(state: TaskState.cancelled, report: e.report));
      if (quiet) rethrow;
    } on Object catch (error, stack) {
      _update(id, (t) => t._with(state: TaskState.failed, error: '$error'));
      _log.severe(_task(id).label(_english), error, stack);
      if (quiet) rethrow;
    } finally {
      _cancels.remove(id);
      _logEnd(_task(id));
    }
    return null;
  }

  /// Writes the outcome of [task] and its report to the log (SPEC §8).
  void _logEnd(BackgroundTask task) {
    // Warnings are in the report: the task itself is done.
    final state = task.state == TaskState.warning ? TaskState.done : task.state;
    _log.log(
      state == TaskState.done ? Level.INFO : Level.WARNING,
      [
        '${task.label(_english)}: ${state.name}',
        if (task.report case final report? when !report.isEmpty) '$report',
      ].join('\n'),
    );
  }

  /// Asks the running task [id] to stop at its next step, if it is
  /// [BackgroundTask.cancellable]. A queued task leaves the queue and ends
  /// cancelled at once.
  void cancel(int id) {
    if (_queued[id] case final left?) {
      // Already left the queue: nothing more to stop.
      if (left.isCompleted) return;
      _update(id, (t) => t._with(state: TaskState.cancelled));
      _cancels.remove(id);
      left.complete();
      _logEnd(_task(id));
      return;
    }
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task == null || !task.canCancel) return;
    _update(id, (t) => t._with(cancelling: true));
    if (_cancels[id] case final c? when !c.isCompleted) c.complete();
  }

  /// Adds the finished entry [message] to the zone, without progress: the
  /// outcome of an instant action.
  void notify(String message, {NoticeLevel level = NoticeLevel.info}) {
    final id = _next++;
    final task = BackgroundTask(
      id: id,
      label: (_) => message,
      state: switch (level) {
        NoticeLevel.info => TaskState.done,
        NoticeLevel.warning => TaskState.warning,
        NoticeLevel.error => TaskState.failed,
      },
      progress: 1,
    );
    state = [...state, task];
    _log.log(level == NoticeLevel.info ? Level.INFO : Level.WARNING, message);
  }

  /// Removes the finished tasks.
  void clearFinished() => state = [...state.where((t) => !t.isFinished)];

  BackgroundTask _task(int id) => state.firstWhere((t) => t.id == id);

  void _update(int id, BackgroundTask Function(BackgroundTask) change) =>
      state = [for (final t in state) t.id == id ? change(t) : t];
}

final libraryTurnsProvider = Provider<LibraryTurns>((ref) => LibraryTurns());

final tasksProvider = NotifierProvider<TasksNotifier, List<BackgroundTask>>(
  TasksNotifier.new,
);

/// Whether a foreground task waits or runs: the interface is blocked
/// (SPEC §5.2).
final foregroundLockedProvider = Provider<bool>(
  (ref) => ref.watch(
    tasksProvider.select((t) => t.any((t) => t.foreground && !t.isFinished)),
  ),
);

/// Whether the tasks zone is unfolded.
final tasksZoneUnfoldedProvider = NotifierProvider<TasksZoneUnfolded, bool>(
  TasksZoneUnfolded.new,
);

class TasksZoneUnfolded extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  /// Folds the zone (Escape). Returns whether it was unfolded and shown.
  bool fold() {
    final shown = state && ref.read(tasksProvider).isNotEmpty;
    state = false;
    return shown;
  }
}
