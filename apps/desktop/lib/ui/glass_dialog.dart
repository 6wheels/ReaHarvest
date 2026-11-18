import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Opens [builder] as a popup over the blurred application: the glass pane
/// of the settings, with its opening and closing animation (SPEC §5.2).
Future<T?> showGlassDialog<T>(BuildContext context, WidgetBuilder builder) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppLocalizations.of(context).close,
      barrierColor: Colors.transparent,
      transitionDuration: Motion.medium,
      pageBuilder: (context, _, _) => builder(context),
      transitionBuilder: (context, animation, _, child) {
        final t = CurvedAnimation(
          parent: animation,
          curve: Motion.curve,
          reverseCurve: Curves.easeInCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: t,
                  builder: (context, _) => BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 16 * t.value,
                      sigmaY: 16 * t.value,
                    ),
                    child: ColoredBox(
                      color: context.colors.scrim.withValues(
                        alpha: 0.45 * t.value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: t,
              child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(t),
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(t),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
