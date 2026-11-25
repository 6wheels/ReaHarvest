@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';

import 'golden_harness.dart';

void main() {
  goldenTest('pressable_surface', (context) {
    final c = context.colors;
    Widget strip(String label, {required bool selected, bool enabled = true}) =>
        PressableSurface(
          onTap: enabled ? () {} : null,
          selected: selected,
          color: c.surface,
          side: BorderSide(color: c.border),
          child: Padding(
            padding: const EdgeInsets.all(Space.s),
            child: Row(
              children: [
                Container(
                  width: Space.xxs,
                  height: Space.m,
                  color: selected ? c.accent : c.muted,
                ),
                const SizedBox(width: Space.s),
                Text(label, style: context.legend),
              ],
            ),
          ),
        );
    return Column(
      spacing: Space.s,
      children: [
        strip('IDLE', selected: false),
        strip('SELECTED', selected: true),
        strip('DISABLED', selected: false, enabled: false),
        const Surface.panel(
          child: Padding(
            padding: EdgeInsets.all(Space.s),
            child: Text('Plain panel'),
          ),
        ),
        const Surface.panel(
          elevation: Elevation.menu,
          child: Padding(
            padding: EdgeInsets.all(Space.s),
            child: Text('Raised panel'),
          ),
        ),
      ],
    );
  });
}
