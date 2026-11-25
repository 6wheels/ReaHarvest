import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/tasks.dart';
import '../theme/app_theme.dart';
import 'kit/kit.dart';
import 'tasks_zone.dart';

/// Width of the popup.
const _width = 360.0;

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
    // Known at once, before the popup is built: a task ending before the
    // next frame still removes it.
    final route = _route = glassDialogRoute<void>(
      navigator.context,
      (_) => _ProgressPopup(id),
      barrierDismissible: false,
    );
    navigator.push(route);
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
    // Ended: the host removes the popup.
    if (task == null) return const SizedBox.shrink();
    void cancel() => ref.read(tasksProvider.notifier).cancel(id);
    final action = taskAction(context, ref, task);
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
              width: _width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taskStep(task, l10n) ?? '',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.colors.muted),
                  ),
                  const SizedBox(height: Space.s),
                  TaskProgress(task),
                ],
              ),
            ),
            actions: [?action],
          ),
        ),
      ),
    );
  }
}
