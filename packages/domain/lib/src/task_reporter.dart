/// A step of a long operation, mapped by the application to its label.
enum TaskStep { inventory, fix, check }

/// Port through which a long operation (a batch of migration fixes, SPEC
/// §7.2) tells its steps, progress and log lines, and learns whether it was
/// cancelled.
abstract interface class TaskReporter {
  /// Starts [step]; [index] (from 1) and [total] for [TaskStep.fix].
  void step(TaskStep step, {int? index, int? total});

  /// Progress of the current step, from 0 to 1.
  void progress(double value);

  /// Whether the operation was asked to stop.
  bool get isCancelled;

  /// A line for the log of the application.
  void log(String message, {bool warning = false});
}
