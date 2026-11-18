import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/tasks.dart';
import '../theme/app_theme.dart';
import 'glass_dialog.dart';
import 'tasks_zone.dart' show appNavigatorKey;
import 'widgets.dart';

/// Shows the foreground tasks ([BackgroundTask.foreground]) one after the
/// other, each in a popup over the glass pane that blocks the interface
/// until the task ends (SPEC §5.2). Takes no room.
class ForegroundTaskHost extends ConsumerStatefulWidget {
  const ForegroundTaskHost({super.key});

  @override
  ConsumerState<ForegroundTaskHost> createState() => _ForegroundTaskHostState();
}

class _ForegroundTaskHostState extends ConsumerState<ForegroundTaskHost> {
  /// The task shown, and the route of its popup.
  int? _shown;
  Route<void>? _route;

  void _sync(List<BackgroundTask> tasks) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    final active = tasks.where((t) => t.foreground && !t.isFinished);
    if (_shown case final id? when !active.any((t) => t.id == id)) {
      // Removed, not popped: the popup may not be the top route when a
      // report opens at the same time.
      if (_route case final route? when route.isActive) {
        navigator.removeRoute(route);
      }
      _shown = _route = null;
    }
    if (_shown != null || active.isEmpty) return;
    final id = _shown = active.first.id;
    showGlassDialog<void>(navigator.context, (context) {
      _route = ModalRoute.of(context) as Route<void>?;
      return _ProgressPopup(id);
    }, barrierDismissible: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tasksProvider, (_, tasks) => _sync(tasks));
    return const SizedBox.shrink();
  }
}

/// Popup of the task [id]: its label, its step or its waiting, its progress
/// and Cancel; Escape cancels too.
class _ProgressPopup extends ConsumerWidget {
  const _ProgressPopup(this.id);

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final task = ref.watch(tasksProvider).where((t) => t.id == id).firstOrNull;
    if (task == null || task.isFinished) {
      // Ended before its popup was first built: the host had no route to
      // remove yet.
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route != null && route.isActive && context.mounted) {
          Navigator.of(context).removeRoute(route);
        }
      });
      return const SizedBox.shrink();
    }
    void cancel() => ref.read(tasksProvider.notifier).cancel(id);
    final step = task.isQueued ? l10n.taskWaiting : task.step?.call(l10n);
    final progress = task.progress;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => cancel(),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): cancel},
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: Text(task.label(l10n)),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step ?? '',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.colors.muted),
                  ),
                  const SizedBox(height: Space.s),
                  Meter(task.isQueued ? 0 : progress),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: task.cancelling ? null : cancel,
                child: Text(
                  task.cancelling ? l10n.taskCancelling : l10n.cancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
