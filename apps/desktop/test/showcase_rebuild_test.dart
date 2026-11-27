import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reaharvest/main_showcase.dart';
import 'package:reaharvest/ui/kit/kit.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest_library/reaharvest_library.dart'
    show AccentPreference;

import 'goldens/golden_harness.dart';

Future<void> _pumpShowcase(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: showcaseOverrides(), child: const UiShowcaseApp()),
  );
  await tester.pump(const Duration(seconds: 2));
}

/// The PROGRESS slider of the controls bar, found by its value at the start:
/// the same element afterwards, whatever its value.
Finder _progressSlider() {
  final element = find
      .byWidgetPredicate(
        (w) => w is Slider && w.min == 0 && (w.value - 0.65).abs() < 1e-9,
      )
      .evaluate()
      .first;
  return find.byElementPredicate((e) => e == element);
}

/// Scrolls the page itself by [delta], never by a drag: a drag would land on
/// the lists of the specimens (library views) that scroll on their own.
void _scrollPage(WidgetTester tester, double delta) {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  position.jumpTo((position.pixels + delta).clamp(0, position.maxScrollExtent));
}

/// Scrolls the page by [step] until [finder] is built, then brings it in.
Future<void> _scrollPageUntilVisible(
  WidgetTester tester,
  Finder finder,
  double step,
) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    _scrollPage(tester, step);
    await tester.pump();
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  setUpAll(loadFonts);
  setUp(() => currentTime = () => DateTime(2026, 11, 20));
  tearDown(() => currentTime = DateTime.now);

  test('the theme of a brightness and an accent is built once', () {
    for (final brightness in Brightness.values) {
      for (final accent in AccentPreference.values) {
        expect(
          buildTheme(brightness, accent: accent),
          same(buildTheme(brightness, accent: accent)),
        );
      }
    }
    expect(
      buildTheme(Brightness.dark),
      isNot(same(buildTheme(Brightness.light))),
    );
    expect(
      buildTheme(Brightness.dark),
      isNot(same(buildTheme(Brightness.dark, accent: AccentPreference.teal))),
    );
  });

  testWidgets('a hot reload rebuilds the themes', (tester) async {
    await _pumpShowcase(tester);
    final before = buildTheme(Brightness.dark);
    tester.binding.reassembleApplication();
    await tester.pump();
    expect(buildTheme(Brightness.dark), isNot(same(before)));
  });

  testWidgets('a slider tick rebuilds only what depends on it', (tester) async {
    await _pumpShowcase(tester);
    final progress = _progressSlider();
    // The sections are built as they come near the viewport.
    await _scrollPageUntilVisible(tester, find.text('METER — TALL'), 500);
    final rebuilt = <String, int>{};
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final name = element.widget.runtimeType.toString();
      rebuilt[name] = (rebuilt[name] ?? 0) + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await tester.drag(progress, const Offset(-40, 0));
    await tester.pump();

    // What reads the value follows it: the two meters and their labels...
    expect(rebuilt['Meter'], 2);
    expect(rebuilt['_Specimen'], 2);
    // ...no section is rebuilt, nor the application.
    expect(rebuilt['_SectionView'], isNull);
    expect(rebuilt['MaterialApp'], isNull);
  });

  testWidgets('a rebuild with an unchanged theme plays no theme animation', (
    tester,
  ) async {
    await _pumpShowcase(tester);
    // A theme animation builds a new set of tokens on every frame.
    AppColors tokens() =>
        Theme.of(tester.element(find.byType(Scaffold).first))
            .extension<AppColors>()!;
    final before = tokens();
    // The root rebuilds with the same accent: nothing animates.
    await tester.tap(find.text('Neutral'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tokens(), same(before));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tokens(), same(before));
  });

  testWidgets('what grows with use stays bounded', (tester) async {
    await _pumpShowcase(tester);
    final progress = _progressSlider();

    Future<void> cycle() async {
      await tester.drag(progress, const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(progress, const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('EN'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('FR'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Light / dark'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('Light / dark'));
      await tester.pump(const Duration(milliseconds: 500));
      for (final accent in ['Orange', 'Teal', 'Neutral']) {
        await tester.tap(find.text(accent));
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    int listeners() => tester.binding.transientCallbackCount;
    int elements() {
      var count = 0;
      void visit(Element e) {
        count++;
        e.visitChildren(visit);
      }

      tester.binding.rootElement!.visitChildren(visit);
      return count;
    }

    await cycle();
    final tickers = listeners();
    final size = elements();
    for (var i = 0; i < 10; i++) {
      await cycle();
    }
    expect(listeners(), lessThanOrEqualTo(tickers));
    expect(elements(), size);
    // No timer is left pending: the test fails at its end otherwise.
  });

  testWidgets('LOADING off stops the loops, not the one-off animations', (
    tester,
  ) async {
    await _pumpShowcase(tester);
    final scrollable = find.byType(Scrollable).first;
    // Build every section: the list keeps them once built.
    for (var i = 0; i < 60; i++) {
      _scrollPage(tester, 900);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(showcaseLoadingKey));
    // Fails when an animation keeps running: LEDs, meters, busy labels.
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    // The one-off animations still play: a checkbox lights up on its tap.
    final label = find.text('LIGHTCHECKBOX — SELECT ALL: NONE, SOME, ALL');
    await _scrollPageUntilVisible(tester, label, -500);
    final checkbox = find
        .descendant(
          of: find.ancestor(of: label, matching: find.byType(SizedBox)).first,
          matching: find.byType(LightCheckbox),
        )
        .first;
    await tester.ensureVisible(checkbox);
    await tester.pump();
    await tester.tap(checkbox);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    // Scrolling stays animated too.
    final position = tester.state<ScrollableState>(scrollable).position;
    final before = position.pixels;
    position.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    expect(before, greaterThan(0));
    expect(position.pixels, 0);
  });
}
