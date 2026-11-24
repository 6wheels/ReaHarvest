import 'package:flutter/material.dart' hide Title;

import 'icon_action.dart';

/// Opens the title detail: the full screen corners.
class OpenDetailAction extends StatelessWidget {
  const OpenDetailAction({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.onAurora = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final bool onAurora;

  @override
  Widget build(BuildContext context) => IconAction(
    icon: const Icon(Icons.fullscreen_rounded),
    tooltip: tooltip,
    onPressed: onPressed,
    onAurora: onAurora,
  );
}
