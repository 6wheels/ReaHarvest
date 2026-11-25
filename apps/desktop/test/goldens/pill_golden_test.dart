@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';

import 'golden_harness.dart';

void main() {
  goldenTest(
    'pill',
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s,
      children: [
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            Pill('Mixing', color: context.colors.accent),
            Pill('Missing plugins', color: context.colors.ledAmber),
            Pill('Corrupted', color: context.colors.ledRed),
            const Pill('Not adopted'),
            Pill(
              'First album',
              uppercase: false,
              deleteTooltip: 'Remove',
              onDeleted: () {},
            ),
          ],
        ),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            Pill('Artist', onPressed: () {}),
            Pill('Status', menuOpen: false, active: true, onPressed: () {}),
            Pill(
              'To sort',
              icon: Icons.move_down_rounded,
              count: 14,
              onPressed: () {},
            ),
          ],
        ),
      ],
    ),
  );
}
