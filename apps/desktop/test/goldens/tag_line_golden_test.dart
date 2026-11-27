@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';

import 'golden_harness.dart';

void main() {
  const tags = [
    'live',
    'standard tuning',
    'rehearsal',
    'a very long tag that cannot fit',
    'demo',
  ];
  goldenTest(
    'tag_line',
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s,
      children: [
        for (final width in [100.0, 200.0, 340.0])
          SizedBox(width: width, child: const TagLine(tags)),
        const TagLine(['live']),
      ],
    ),
  );
}
