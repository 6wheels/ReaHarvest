@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reaharvest/main_showcase.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest_library/reaharvest_library.dart'
    show AccentPreference;

import 'golden_harness.dart';

/// Fixed window of the golden tests.
const _window = Size(1280, 1600);

/// The section drawn in every accent: the one that uses the accent the most.
const _accentSection = 'buttons';

/// One golden image per section of the showcase and per theme, in the
/// neutral accent; the buttons section also in the other accents. Names:
/// `<section>_<theme>_<accent>.png`.
void main() {
  setUpAll(loadFonts);
  setUp(() => currentTime = () => DateTime(2026, 11, 20));
  tearDown(() => currentTime = DateTime.now);

  void golden(String section, Brightness brightness, AccentPreference accent) {
    final name = '${section}_${brightness.name}_${accent.name}';
    testWidgets(name, (tester) async {
      tester.view
        ..physicalSize = _window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: showcaseOverrides(),
          child: UiShowcaseApp(
            section: section,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            accent: accent,
          ),
        ),
      );
      // Not `pumpAndSettle`: the meters and lights never settle. The fake
      // clock gives every looping animation the same frame at 2 s.
      await tester.pump(const Duration(seconds: 2));
      await expectLater(
        find.byKey(showcaseSectionKey),
        matchesGoldenFile('$name.png'),
      );
    });
  }

  for (final section in showcaseSectionIds) {
    for (final brightness in Brightness.values) {
      golden(section, brightness, AccentPreference.neutral);
    }
  }
  for (final accent in AccentPreference.values) {
    if (accent == AccentPreference.neutral) continue;
    for (final brightness in Brightness.values) {
      golden(_accentSection, brightness, accent);
    }
  }
}
