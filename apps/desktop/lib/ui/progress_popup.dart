import 'dart:async';

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

/// How long a foreground task runs before its popup shows: a quick action
/// never flashes it, while the interface is blocked from its start. Long
/// enough for the quick version actions (a copy, a rename), short enough
/// for the wait not to feel dead.
const foregroundPopupDelay = Duration(milliseconds: 200);

/// Whether the popup of a foreground task is shown: the glass pane over the
/// tasks zone follows it ([ForegroundLock]).
final foregroundPopupShownProvider = NotifierProvider<_PopupShown, bool>(
  _PopupShown.new,
);

class _PopupShown extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool shown) => state = shown;
}

/// Blocks the navigator [child] while a foreground task waits for its popup
/// ([foregroundPopupDelay]): from then on the barrier of the popup blocks
/// it, so that a quick action never lets a click through nor flashes. The
/// focus stays where it is.
class ForegroundWait extends ConsumerWidget {
  const ForegroundWait({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting =
        ref.watch(foregroundLockedProvider) &&
        !ref.watch(foregroundPopupShownProvider);
    // The pointer only: excluding the focus would drop the focus of the page,
    // which the keyboard needs back when the action is over.
    return AbsorbPointer(absorbing: waiting, child: child);
  }
}

/// Blocks [child], the part of the interface outside of the navigator (the
/// tasks zone and the interrupted fix prompt), while a foreground task
/// waits or runs: nothing in it can be clicked or focused, and the glass
/// pane of the popup covers it once the popup shows (SPEC §5.2).
class ForegroundLock extends ConsumerWidget {
  const ForegroundLock({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(foregroundLockedProvider);
    final shown = ref.watch(foregroundPopupShownProvider);
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: locked,
          child: ExcludeFocus(excluding: locked, child: child),
        ),
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: locked && shown ? 1.0 : 0.0),
            duration: Motion.medium,
            curve: Motion.curve,
            builder: (context, amount, _) => amount == 0
                ? const SizedBox.shrink()
                : IgnorePointer(
                    child: GlassPane(AlwaysStoppedAnimation(amount)),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Shows the foreground tasks ([BackgroundTask.foreground]) one after the
/// other, each in a popup over the glass pane that blocks the interface
/// until the task ends (SPEC §5.2). The popup shows after
/// [foregroundPopupDelay], and never once its task has ended. Takes no
/// room.
class ForegroundTaskHost extends ConsumerStatefulWidget {
  const ForegroundTaskHost({super.key});

  @override
  ConsumerState<ForegroundTaskHost> createState() => _ForegroundTaskHostState();
}

class _ForegroundTaskHostState extends ConsumerState<ForegroundTaskHost> {
  /// The task waited for or shown, the delay before its popup, and the
  /// route of its popup.
  int? _shown;
  Timer? _delay;
  Route<void>? _route;

  Iterable<BackgroundTask> _active(List<BackgroundTask> tasks) =>
      tasks.where((t) => t.foreground && !t.isFinished);

  void _sync(List<BackgroundTask> tasks) {
    final active = _active(tasks);
    if (_shown case final id? when !active.any((t) => t.id == id)) {
      _delay?.cancel();
      // Removed, not popped: the popup may not be the top route when a
      // report opens at the same time.
      if (_route case final route? when route.isActive) {
        appNavigatorKey.currentState?.removeRoute(route);
      }
      _shown = _route = null;
      ref.read(foregroundPopupShownProvider.notifier).set(false);
    }
    if (_shown != null || active.isEmpty) return;
    final id = _shown = active.first.id;
    _delay = Timer(foregroundPopupDelay, () => _show(id));
  }

  /// Pushes the popup of [id] if its task is still there.
  void _show(int id) {
    if (_shown != id) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      // The navigator is not there yet: try again, the task stays locked.
      _delay = Timer(foregroundPopupDelay, () => _show(id));
      return;
    }
    if (!_active(ref.read(tasksProvider)).any((t) => t.id == id)) return;
    final route = _route = glassDialogRoute<void>(
      navigator.context,
      (_) => _ProgressPopup(id),
      barrierDismissible: false,
    );
    navigator.push(route);
    ref.read(foregroundPopupShownProvider.notifier).set(true);
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tasksProvider, (_, tasks) => _sync(tasks));
    return const SizedBox.shrink();
  }
}

/// Popup of the task [id]: Cancel and Escape ask for a confirmation first.
class _ProgressPopup extends ConsumerStatefulWidget {
  const _ProgressPopup(this.id);

  final int id;

  @override
  ConsumerState<_ProgressPopup> createState() => _ProgressPopupState();
}

class _ProgressPopupState extends ConsumerState<_ProgressPopup> {
  /// The route of the confirmation while it is open.
  Route<bool>? _confirmation;

  Future<void> _cancel() async {
    final task = ref
        .read(tasksProvider)
        .where((t) => t.id == widget.id)
        .firstOrNull;
    if (_confirmation != null || task == null || !task.canCancel) return;
    final route = _confirmation = glassDialogRoute<bool>(
      context,
      (_) => const CancelTaskDialog(),
    );
    final stop = await Navigator.of(context).push(route);
    if (!mounted) return;
    _confirmation = null;
    if (stop ?? false) ref.read(tasksProvider.notifier).cancel(widget.id);
  }

  /// The task ended: its confirmation goes with its popup.
  void _closeConfirmation() {
    if (_confirmation case final route? when route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = ref
        .watch(tasksProvider)
        .where((t) => t.id == widget.id)
        .firstOrNull;
    // Ended: the host removes the popup.
    if (task == null) return const SizedBox.shrink();
    ref.listen(tasksProvider, (_, tasks) {
      if (tasks.where((t) => t.id == widget.id).every((t) => t.isFinished)) {
        _closeConfirmation();
      }
    });
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: Focus(
          autofocus: true,
          child: ProgressPopup(task, onCancel: _cancel),
        ),
      ),
    );
  }
}

/// The popup of [task]: its label, its step or its waiting, its progress
/// and Cancel ([onCancel]).
class ProgressPopup extends ConsumerWidget {
  const ProgressPopup(this.task, {required this.onCancel, super.key});

  final BackgroundTask task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final action = taskAction(context, ref, task, onCancel: onCancel);
    return AlertDialog(
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
    );
  }
}

/// Confirmation of the cancel of a foreground task: pops true to stop it,
/// false to keep it running.
class CancelTaskDialog extends StatelessWidget {
  const CancelTaskDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.taskCancelTitle),
      content: Text(l10n.taskCancelBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.taskKeepRunning),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.taskStop),
        ),
      ],
    );
  }
}
