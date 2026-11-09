import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' show Report;

import '../l10n/app_localizations.dart';

enum TaskState { running, done, failed, cancelled }

/// Thrown by [TaskControl.checkCancelled] to stop a cancelled task.
final class TaskCancelled implements Exception {
  const TaskCancelled();
}

/// Handle given to a running task: reports progress and tells whether the
/// task was cancelled. Cancellation is cooperative, between two steps.
final class TaskControl {
  TaskControl._(this._notifier, this._id);

  final TasksNotifier _notifier;
  final int _id;

  /// Throws [TaskCancelled] if the task was asked to stop.
  void checkCancelled() {
    if (_notifier._task(_id).cancelling) throw const TaskCancelled();
  }

  /// Sets the progress, from 0 to 1.
  void progress(double value) =>
      _notifier._update(_id, (t) => t._with(progress: value));
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

  bool get isRunning => state == TaskState.running;

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
  );
}

/// Background tasks, oldest first.
class TasksNotifier extends Notifier<List<BackgroundTask>> {
  var _next = 0;

  @override
  List<BackgroundTask> build() => const [];

  /// Runs [body] as a task labelled [label]. Returns its result, or null if
  /// it failed or was cancelled (the outcome stays in the task). A [Report]
  /// result is kept in the task, which fails if it holds errors; with
  /// [openReport], the tasks zone opens it at the end (actions launched by
  /// the user, SPEC §5.2).
  Future<T?> run<T>(
    String Function(AppLocalizations l10n) label,
    Future<T> Function(TaskControl task) body, {
    bool openReport = false,
  }) async {
    final id = _next++;
    state = [
      ...state,
      BackgroundTask(id: id, label: label, openReport: openReport),
    ];
    try {
      final result = await body(TaskControl._(this, id));
      final report = result is Report ? result : null;
      _update(
        id,
        (t) => t._with(
          state: report?.hasErrors ?? false ? TaskState.failed : TaskState.done,
          progress: 1,
          report: report,
        ),
      );
      return result;
    } on TaskCancelled {
      _update(id, (t) => t._with(state: TaskState.cancelled));
    } on Object catch (error) {
      _update(id, (t) => t._with(state: TaskState.failed, error: '$error'));
    }
    return null;
  }

  /// Asks the running task [id] to stop at its next step.
  void cancel(int id) => _update(id, (t) => t._with(cancelling: true));

  /// Removes the finished tasks.
  void clearFinished() => state = [...state.where((t) => t.isRunning)];

  BackgroundTask _task(int id) => state.firstWhere((t) => t.id == id);

  void _update(int id, BackgroundTask Function(BackgroundTask) change) =>
      state = [for (final t in state) t.id == id ? change(t) : t];
}

final tasksProvider = NotifierProvider<TasksNotifier, List<BackgroundTask>>(
  TasksNotifier.new,
);
