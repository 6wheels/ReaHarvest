import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';

/// Blur of the pane at full amount.
const _blur = 16.0;

/// The acrylic glass pane (blur and scrim) over what is behind it, SPEC
/// §5.2: [amount], from 0 to 1, drives its opening and closing. Fills its
/// parent and does not catch the pointer: wrap it to block the interface.
class GlassPane extends StatelessWidget {
  const GlassPane(this.amount, {super.key});

  final Animation<double> amount;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: amount,
    builder: (context, _) => BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: _blur * amount.value,
        sigmaY: _blur * amount.value,
      ),
      child: ColoredBox(
        color: context.colors.scrim.withValues(
          alpha: Alpha.medium * amount.value,
        ),
      ),
    ),
  );
}
