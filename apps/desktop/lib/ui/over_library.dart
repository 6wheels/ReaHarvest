import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Title;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/tasks.dart';
import '../theme/app_theme.dart';

/// Slide of a page over the library at its entrance, in its own size.
const _slideFrom = Offset(0.02, 0);

/// Route of a page shown over the library (title detail, "To sort").
PageRouteBuilder<void> overLibraryRoute(WidgetBuilder builder) =>
    PageRouteBuilder<void>(
      transitionDuration: Motion.medium,
      reverseTransitionDuration: Motion.medium,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, animation, _, child) {
        final t = CurvedAnimation(parent: animation, curve: Motion.curve);
        return FadeTransition(
          opacity: t,
          child: SlideTransition(
            position: Tween(begin: _slideFrom, end: Offset.zero).animate(t),
            child: child,
          ),
        );
      },
    );

/// Goes back from a page over the library with Escape (once the tasks zone
/// is folded) or the mouse back button.
class BackNavigation extends ConsumerWidget {
  const BackNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void back() => Navigator.of(context).maybePop();
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) back();
      },
      child: CallbackShortcuts(
        // Escape folds the tasks zone first.
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!ref.read(tasksZoneUnfoldedProvider.notifier).fold()) back();
          },
        },
        // A scope: when a focused field leaves (an adoption form), the
        // focus falls back here and Escape still goes back.
        child: FocusScope(autofocus: true, child: child),
      ),
    );
  }
}
