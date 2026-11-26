import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' show Report;

import '../l10n/app_localizations.dart';
import '../state/tasks.dart';
import '../theme/app_theme.dart';
import 'kit/kit.dart';
import 'report_dialog.dart';

/// Layout of a task: height of the list and of a row, widths of the light,
/// of the percentage and of the meter.
const _listHeight = 220.0;
const _rowHeight = 34.0;
const _lightWidth = 20.0;
const _percentWidth = 36.0;
const _meterWidth = 120.0;

/// Navigator of the application, for the tasks zone which sits outside of
/// it.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Opens [report] over the pages of the application.
void _openReport(String title, Report report) {
  if (appNavigatorKey.currentContext case final context?) {
    showReport(context, title, report);
  }
}

/// Background tasks zone at the bottom of the application (SPEC §5.2): the
/// latest task, expandable into the list of all of them. Hidden when there
/// is no task.
class TasksZone extends ConsumerWidget {
  const TasksZone({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final expanded = ref.watch(tasksZoneUnfoldedProvider);
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    // Reports of the actions launched by the user open when they end.
    ref.listen(tasksProvider, (previous, next) {
      final running = {
        for (final t in previous ?? const <BackgroundTask>[])
          if (t.isRunning) t.id,
      };
      for (final t in next) {
        if (t.openReport && !t.isRunning && running.contains(t.id)) {
          if (t.report case final report?) {
            _openReport(t.label(l10n), report);
          }
        }
      }
    });
    final Widget content;
    if (tasks.isEmpty) {
      content = const SizedBox(width: double.infinity);
    } else {
      final headline = tasks.lastWhere(
        (t) => t.isRunning,
        orElse: () => tasks.last,
      );
      final toggle = TextButton.icon(
        onPressed: ref.read(tasksZoneUnfoldedProvider.notifier).toggle,
        iconAlignment: IconAlignment.end,
        // The zone unfolds upwards.
        icon: Disclosure(expanded ? Disclosure.down : Disclosure.up),
        label: Text(
          // The counter only tells something with several tasks.
          tasks.length > 1
              ? '${l10n.tasks.toUpperCase()}$labelSeparator${tasks.length}'
              : l10n.tasks.toUpperCase(),
          style: context.legend.copyWith(color: c.text),
        ),
      );
      content = Surface(
        color: c.surface,
        shape: Border(top: BorderSide(color: c.border)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        if (tasks.any((t) => t.isFinished))
                          TextButton(
                            onPressed: ref
                                .read(tasksProvider.notifier)
                                .clearFinished,
                            child: Text(l10n.clearFinishedTasks),
                          ),
                        toggle,
                      ],
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: _listHeight),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in tasks.reversed)
                            _TaskRow(t, detailed: true),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _TaskRow(headline)),
                    const SizedBox(width: Space.m),
                    if (tasks.any((t) => t.isFinished))
                      // No tooltip: the zone sits outside of the navigator, so
                      // without overlay.
                      IconButton(
                        icon: Semantics(
                          label: l10n.clearFinishedTasks,
                          child: const Icon(Icons.clear_all),
                        ),
                        onPressed: ref
                            .read(tasksProvider.notifier)
                            .clearFinished,
                      ),
                    toggle,
                  ],
                ),
        ),
      );
    }
    return AnimatedSize(
      duration: Motion.medium,
      curve: Motion.curve,
      alignment: Alignment.bottomCenter,
      child: content,
    );
  }
}

/// Sub-step of [task] while it is not finished: its waiting while queued.
/// Shared by the tasks zone and the popup ([ForegroundTaskHost]).
String? taskStep(BackgroundTask task, AppLocalizations l10n) => task.isQueued
    ? l10n.taskWaiting
    : task.isRunning
    ? task.step?.call(l10n)
    : null;

/// Cancel of [task] while it applies, or its stop state; null when done or
/// failed.
///
/// [onCancel] replaces the plain cancel of the task (the popup asks for a
/// confirmation first).
Widget? taskAction(
  BuildContext context,
  WidgetRef ref,
  BackgroundTask task, {
  VoidCallback? onCancel,
}) {
  final l10n = AppLocalizations.of(context);
  final muted = Theme.of(context).textTheme.bodySmall
      ?.copyWith(color: context.colors.muted);
  if (task.canCancel) {
    return TextButton(
      onPressed:
          onCancel ?? () => ref.read(tasksProvider.notifier).cancel(task.id),
      child: Text(l10n.cancel),
    );
  }
  return switch (task.state) {
    TaskState.running when task.cancelling => Text(
      l10n.taskCancelling,
      style: muted,
    ),
    TaskState.cancelled => Text(l10n.taskCancelled, style: muted),
    _ => null,
  };
}

/// Progress of a running [task] and its readout; empty while it waits.
class TaskProgress extends StatelessWidget {
  const TaskProgress(this.task, {super.key});

  final BackgroundTask task;

  @override
  Widget build(BuildContext context) {
    final progress = task.isQueued ? 0.0 : task.progress;
    return Row(
      children: [
        Expanded(child: Meter(progress)),
        const SizedBox(width: Space.s),
        SizedBox(
          width: _percentWidth,
          child: Text(
            progress == null
                ? '---'
                : '${(progress * 100).round()}%'.padLeft(4),
            textAlign: TextAlign.end,
            style: context.readout.copyWith(color: context.colors.text),
          ),
        ),
      ],
    );
  }
}

/// Width of the state and report columns of a task, with room for the
/// longer labels of the supported languages.
const _actionWidth = 104.0;

class _TaskRow extends ConsumerWidget {
  const _TaskRow(this.task, {this.detailed = false});

  final BackgroundTask task;

  /// Unfolded list: the sub-step under the label, and the error of a failed
  /// task.
  final bool detailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: c.muted);
    // A queued task shows that it waits in place of its step.
    final step = taskStep(task, l10n);
    // Status light: dark while waiting or cancelled, breathing while
    // running, blinking when failed, steady with its color otherwise.
    final light = switch (task.state) {
      TaskState.queued || TaskState.cancelled => Led(c.muted, lit: false),
      TaskState.running => Led(c.ledAmber, mode: LedMode.pulse),
      TaskState.done => Led(c.ledGreen),
      TaskState.warning => Led(c.ledAmber),
      TaskState.failed => Led(c.ledRed, mode: LedMode.blink),
    };
    final trailing = taskAction(context, ref, task);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _rowHeight),
      child: Row(
        children: [
          SizedBox(
            width: _lightWidth,
            child: Center(child: light),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The sub-step follows the label on one line, folded; under
                // it, unfolded.
                Text.rich(
                  TextSpan(
                    text: task.label(l10n),
                    children: [
                      if (step != null && !detailed)
                        TextSpan(text: '  ·  $step', style: muted),
                    ],
                  ),
                  style: text.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (step != null && detailed)
                  Text(
                    step,
                    style: muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (detailed && task.error != null)
                  Text(task.error!, style: muted, maxLines: 3),
              ],
            ),
          ),
          if (task.isRunning) ...[
            const SizedBox(width: Space.m),
            SizedBox(
              width: _meterWidth + Space.s + _percentWidth,
              child: TaskProgress(task),
            ),
          ],
          const SizedBox(width: Space.m),
          // State and report in columns of one width, the report slot kept
          // empty: the rows line up whatever the state or the language.
          SizedBox(
            width: _actionWidth,
            // A button fills its column, a state is centered in it.
            child: switch (trailing) {
              null => null,
              ButtonStyleButton() => trailing,
              _ => Center(child: trailing),
            },
          ),
          const SizedBox(width: Space.xs),
          SizedBox(
            width: _actionWidth,
            child: switch (task.report) {
              final report? => TextButton(
                onPressed: () => _openReport(task.label(l10n), report),
                child: Text(l10n.report),
              ),
              null => null,
            },
          ),
        ],
      ),
    );
  }
}
