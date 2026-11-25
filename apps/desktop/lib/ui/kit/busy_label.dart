import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';
import 'led.dart';

/// Button label hidden behind a breathing light while [busy], keeping the
/// button size.
class BusyLabel extends StatelessWidget {
  const BusyLabel(this.label, {super.key, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Opacity(opacity: busy ? 0 : 1, child: Text(label)),
      if (busy)
        Led(context.colors.ledAmber, size: IconSize.ledM, mode: LedMode.pulse),
    ],
  );
}
