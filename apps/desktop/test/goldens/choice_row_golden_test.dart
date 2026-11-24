@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/ui/kit/kit.dart';

import 'golden_harness.dart';

void main() {
  goldenTest(
    'choice_row',
    (context) => Column(
      children: [
        ChoiceRow(
          selected: true,
          label: 'Blank project',
          hint: 'An empty project',
          onTap: () {},
        ),
        ChoiceRow(
          selected: false,
          label: 'From a template',
          hint: 'A project template',
          trailing: const Text('Trailing'),
          onTap: () {},
        ),
        CheckRow(value: true, label: 'Show in the tray', onChanged: (_) {}),
        CheckRow(value: false, label: 'Show in the tray', onChanged: (_) {}),
        const ChoiceRow(
          selected: false,
          label: 'Duplicate',
          hint: 'Not available',
          onTap: null,
        ),
      ],
    ),
  );
}
