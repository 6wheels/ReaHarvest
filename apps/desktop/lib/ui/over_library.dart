import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Title;
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

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
            position: Tween(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(t),
            child: child,
          ),
        );
      },
    );

/// Goes back from a page over the library with Escape or the mouse back
/// button.
class BackNavigation extends StatelessWidget {
  const BackNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) back();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): back},
        // A scope: when a focused field leaves (an adoption form), the
        // focus falls back here and Escape still goes back.
        child: FocusScope(autofocus: true, child: child),
      ),
    );
  }
}
