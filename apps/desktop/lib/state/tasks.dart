import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  bool get isRunning => state == TaskState.running;

  BackgroundTask _with({
    TaskState? state,
    double? progress,
    bool? cancelling,
    String? error,
  }) => BackgroundTask(
    id: id,
    label: label,
    state: state ?? this.state,
    progress: progress ?? this.progress,
    cancelling: cancelling ?? this.cancelling,
    error: error ?? this.error,
  );
}

/// Background tasks, oldest first.
class TasksNotifier extends Notifier<List<BackgroundTask>> {
  var _next = 0;

  @override
  List<BackgroundTask> build() => const [];

  /// Runs [body] as a task labelled [label]. Returns its result, or null if
  /// it failed or was cancelled (the outcome stays in the task).
  Future<T?> run<T>(
    String Function(AppLocalizations l10n) label,
    Future<T> Function(TaskControl task) body,
  ) async {
    final id = _next++;
    state = [...state, BackgroundTask(id: id, label: label)];
    try {
      final result = await body(TaskControl._(this, id));
      _update(id, (t) => t._with(state: TaskState.done, progress: 1));
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
