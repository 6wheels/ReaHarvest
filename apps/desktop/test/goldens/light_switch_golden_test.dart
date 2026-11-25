@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';

import 'golden_harness.dart';

void main() {
  goldenTest(
    'light_switch',
    (context) => Row(
      spacing: Space.m,
      children: [
        LightSwitch(value: true, onChanged: (_) {}),
        LightSwitch(value: false, onChanged: (_) {}),
        const LightSwitch(value: true, onChanged: null),
        const LightSwitch(value: false, onChanged: null),
      ],
    ),
  );
}
