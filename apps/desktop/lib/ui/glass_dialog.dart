import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Geometry of the popup transition: blur of the pane behind, scale and
/// slide the popup starts from, curve of its closing.
const _blur = 16.0;
const _scaleFrom = 0.96;
const _slideFrom = Offset(0, 0.02);
const _closeCurve = Curves.easeInCubic;

/// Opens [builder] as a popup over the blurred application: the glass pane
/// of the settings, with its opening and closing animation (SPEC §5.2).
Future<T?> showGlassDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) => Navigator.of(context).push(
  glassDialogRoute(context, builder, barrierDismissible: barrierDismissible),
);

/// Route of the popup [builder] of [showGlassDialog], for a caller that
/// removes it itself.
RawDialogRoute<T> glassDialogRoute<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) => RawDialogRoute<T>(
  barrierDismissible: barrierDismissible,
  barrierLabel: AppLocalizations.of(context).close,
  barrierColor: Colors.transparent,
  transitionDuration: Motion.medium,
  pageBuilder: (context, _, _) => builder(context),
  transitionBuilder: (context, animation, _, child) {
    final t = CurvedAnimation(
      parent: animation,
      curve: Motion.curve,
      reverseCurve: _closeCurve,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: t,
              builder: (context, _) => BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _blur * t.value,
                  sigmaY: _blur * t.value,
                ),
                child: ColoredBox(
                  color: context.colors.scrim.withValues(
                    alpha: Alpha.medium * t.value,
                  ),
                ),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween(begin: _scaleFrom, end: 1.0).animate(t),
            child: SlideTransition(
              position: Tween(begin: _slideFrom, end: Offset.zero).animate(t),
              child: child,
            ),
          ),
        ),
      ],
    );
  },
);
