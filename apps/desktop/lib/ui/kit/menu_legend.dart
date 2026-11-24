import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';

/// Legend heading the entries of a menu; not an entry itself.
class MenuLegend extends StatelessWidget {
  const MenuLegend(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xs),
    child: Text(label.toUpperCase(), style: context.type.legendSmall),
  );
}
