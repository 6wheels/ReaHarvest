@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';

import 'golden_harness.dart';

void main() {
  goldenTest(
    'disclosure_tile',
    (context) => Column(
      children: [
        DisclosureTile(
          initiallyExpanded: true,
          leading: SizedBox(
            width: IconSize.l,
            child: Center(child: Led(context.colors.ledAmber)),
          ),
          title: const Text('Missing plugins · 2'),
          children: const [Text('First plugin'), Text('Second plugin')],
        ),
        DisclosureTile(
          leading: SizedBox(
            width: IconSize.l,
            child: Center(child: Led(context.colors.ledGreen)),
          ),
          title: const Text('Done · 1'),
          children: const [Text('Hidden until opened')],
        ),
      ],
    ),
  );
}
