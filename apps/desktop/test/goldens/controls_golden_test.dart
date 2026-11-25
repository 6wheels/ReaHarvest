@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';

import 'golden_harness.dart';

/// The Material controls styled by the theme: segmented button, slider.
void main() {
  goldenTest(
    'controls',
    (context) => Column(
      spacing: Space.s,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('System')),
            ButtonSegment(value: 1, label: Text('Light')),
            ButtonSegment(value: 2, label: Text('Dark')),
            ButtonSegment(value: 3, label: Text('Off'), enabled: false),
          ],
          selected: const {1},
          onSelectionChanged: (_) {},
        ),
        Slider(value: 0.4, onChanged: (_) {}),
        const Slider(value: 0.4, onChanged: null),
      ],
    ),
  );
}
