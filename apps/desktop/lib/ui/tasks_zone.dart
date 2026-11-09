import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/tasks.dart';
import '../theme/app_theme.dart';

/// Background tasks zone at the bottom of the application (SPEC §5.2): the
/// latest task, expandable into the list of all of them. Hidden when there
/// is no task.
class TasksZone extends ConsumerStatefulWidget {
  const TasksZone({super.key});

  @override
  ConsumerState<TasksZone> createState() => _TasksZoneState();
}

class _TasksZoneState extends ConsumerState<TasksZone> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final Widget content;
    if (tasks.isEmpty) {
      content = const SizedBox(width: double.infinity);
    } else {
      final headline = tasks.lastWhere(
        (t) => t.isRunning,
        orElse: () => tasks.last,
      );
      final toggle = TextButton.icon(
        onPressed: () => setState(() => _expanded = !_expanded),
        iconAlignment: IconAlignment.end,
        icon: Icon(
          _expanded ? Icons.expand_more_rounded : Icons.expand_less_rounded,
          size: 18,
        ),
        label: Text('${l10n.tasks} · ${tasks.length}'),
      );
      content = Material(
        color: c.surface,
        shape: Border(top: BorderSide(color: c.border)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.xl,
            vertical: Space.xs,
          ),
          child: _expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        if (tasks.any((t) => !t.isRunning))
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
                      constraints: const BoxConstraints(maxHeight: 220),
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

class _TaskRow extends ConsumerWidget {
  const _TaskRow(this.task, {this.detailed = false});

  final BackgroundTask task;

  /// Shows the error of a failed task.
  final bool detailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: c.muted);
    final error = Theme.of(context).colorScheme.error;
    final icon = switch (task.state) {
      TaskState.running => SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
      ),
      TaskState.done => Icon(
        Icons.check_circle_outline_rounded,
        size: 16,
        color: c.accent,
      ),
      TaskState.failed => Icon(
        Icons.error_outline_rounded,
        size: 16,
        color: error,
      ),
      TaskState.cancelled => Icon(
        Icons.block_rounded,
        size: 16,
        color: c.muted,
      ),
    };
    final Widget trailing = switch (task.state) {
      TaskState.running when task.cancelling => Text(
        l10n.taskCancelling,
        style: muted,
      ),
      TaskState.running => TextButton(
        onPressed: () => ref.read(tasksProvider.notifier).cancel(task.id),
        child: Text(l10n.cancel),
      ),
      TaskState.done => Text(l10n.taskDone, style: muted),
      TaskState.failed => Text(
        l10n.taskFailed,
        style: muted?.copyWith(color: error),
      ),
      TaskState.cancelled => Text(l10n.taskCancelled, style: muted),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          SizedBox(width: 20, child: Center(child: icon)),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.label(l10n),
                  style: text.bodyMedium,
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
              width: 160,
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
                color: c.accent,
                backgroundColor: c.border,
              ),
            ),
          ],
          const SizedBox(width: Space.m),
          trailing,
        ],
      ),
    );
  }
}
