import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';
import 'led.dart';

/// Waiting for content: an amber light breathing in the middle.
class BusyLight extends StatelessWidget {
  const BusyLight({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Led(
      context.colors.ledAmber,
      size: IconSize.ledL,
      mode: LedMode.pulse,
    ),
  );
}
