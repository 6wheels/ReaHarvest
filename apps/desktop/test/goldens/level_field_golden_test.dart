@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';

import 'golden_harness.dart';

void main() {
  final filled = TextEditingController(text: 'Sample Artist');
  final empty = TextEditingController();
  final compact = TextEditingController();
  final created = TextEditingController(text: 'New Artist');
  tearDownAll(() {
    created.dispose();
    filled.dispose();
    empty.dispose();
    compact.dispose();
  });
  goldenTest(
    'level_field',
    (context) => Column(
      spacing: Space.m,
      children: [
        LevelField(
          label: 'Artist',
          controller: filled,
          options: () => const ['Sample Artist'],
          error: null,
          onChanged: () {},
        ),
        LevelField(
          label: 'Artist',
          controller: created,
          options: () => const ['Sample Artist'],
          error: null,
          newValueHint: 'This level will be created',
          onChanged: () {},
        ),
        LevelField(
          label: 'Add a tag',
          controller: compact,
          options: () => const [],
          error: null,
          compact: true,
          onChanged: () {},
        ),
        LevelField(
          label: 'Album',
          hint: 'Album name',
          controller: empty,
          options: () => const [],
          error: 'Invalid folder name',
          onChanged: () {},
        ),
      ],
    ),
  );
}
