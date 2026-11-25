import 'package:material_ui/material_ui.dart' hide Title;

import '../../theme/app_theme.dart';

/// Small filled triangle telling whether something is open, turning to
/// its new direction: [right] then [down] for a fold, [down] then [up] for
/// a menu.
class Disclosure extends StatelessWidget {
  const Disclosure(
    this.turns, {
    super.key,
    this.size = IconSize.xl,
    this.color,
  });

  static const right = 0.0;
  static const down = 0.25;
  static const up = 0.75;

  /// Direction, in turns from pointing right.
  final double turns;
  final double size;

  /// Muted when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: turns,
    duration: Motion.fast,
    curve: Motion.curve,
    child: Icon(
      Icons.arrow_right_rounded,
      size: size,
      color: color ?? context.colors.muted,
    ),
  );
}
