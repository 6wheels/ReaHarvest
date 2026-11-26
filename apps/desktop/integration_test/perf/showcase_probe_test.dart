// coverage:ignore-file
// Probe of the showcase (#229): frame times while a control is dragged, and
// what grows over a long session of use. Not a budgeted benchmark: it prints
// the figures. Run in profile mode (debug timings never count):
//   flutter drive --profile -d windows --driver=test_driver/perf_driver.dart
//     --target=integration_test/perf/showcase_probe_test.dart
//     --dart-define=PROBE=progress|size|sample|session
//     [--dart-define=ROUNDS=<n>]
// `session` repeats a mix of interactions (hover, scrolling, clicks, language,
// theme and accent changes) and prints the memory and the pending tickers of
// each round.

import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reaharvest/main_showcase.dart';

const _probe = String.fromEnvironment('PROBE', defaultValue: 'progress');
const _rounds = int.fromEnvironment('ROUNDS', defaultValue: 6);

double _ms(Duration d) => d.inMicroseconds / 1000;

double _percentile(List<double> values, double fraction) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[(fraction * sorted.length).ceil().clamp(1, sorted.length) - 1];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('showcase probe $_probe', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: showcaseOverrides(),
        child: const UiShowcaseApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    var timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    binding.addTimingsCallback(onTimings);
    addTearDown(() => binding.removeTimingsCallback(onTimings));

    Future<void> settle() async {
      // The timings reach the callback some time after their frames.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
    }

    // The sliders are told apart by their value or their range at the start,
    // then followed by their element, whatever their value becomes.
    Finder fixed(Finder finder) {
      final element = finder.evaluate().first;
      return find.byElementPredicate((e) => e == element);
    }

    // Visit every section first (the list builds them as they come near the
    // viewport and keeps them): the figures are those of the whole page.
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 60; i++) {
      await tester.drag(list, const Offset(0, -900), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.drag(list, const Offset(0, 90000), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));

    final progress = fixed(
      find.byWidgetPredicate(
        (w) => w is Slider && w.min == 0 && (w.value - 0.65).abs() < 1e-9,
      ),
    );
    final size = fixed(
      find.byWidgetPredicate((w) => w is Slider && w.min == 0.75),
    );

    // The sample slider is far down the page, which builds its sections as
    // they come near the viewport: scroll to it first.
    Future<Finder> sample() async {
      final label = find.textContaining('SLIDER AND SEGMENTEDBUTTON');
      await tester.scrollUntilVisible(
        label,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      return find
          .descendant(
            of: find.ancestor(of: label, matching: find.byType(SizedBox)).first,
            matching: find.byType(Slider),
          )
          .first;
    }

    Future<void> drag(Finder slider) async {
      final center = tester.getCenter(slider);
      final width = tester.getSize(slider).width - 40;
      final gesture = await tester.startGesture(
        Offset(center.dx - width / 2, center.dy),
      );
      for (var pass = 0; pass < 3; pass++) {
        for (var i = 0; i <= 40; i++) {
          final f = pass.isEven ? i / 40 : 1 - i / 40;
          await gesture.moveTo(
            Offset(center.dx - width / 2 + width * f, center.dy),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      await gesture.up();
    }

    Future<void> tapText(String text) async {
      final finder = find.text(text).first;
      await tester.tap(finder, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> session() async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final scroll = find.byType(Scrollable).first;
      for (var step = 0; step < 6; step++) {
        await tester.drag(scroll, const Offset(0, -700), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
        for (var x = 100.0; x < 1200; x += 150) {
          await mouse.moveTo(Offset(x, 300 + 80 * (step % 3)));
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      await tester.drag(scroll, const Offset(0, 4200), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tapText('EN');
      await tapText('FR');
      await tester.tap(find.byTooltip('Light / dark'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Light / dark'));
      await tester.pump(const Duration(milliseconds: 300));
      for (final accent in ['Orange', 'Teal', 'Violet', 'Neutral']) {
        await tapText(accent);
      }
      await drag(progress);
      await drag(await sample());
      await mouse.removePointer();
    }

    for (var round = 0; round < _rounds; round++) {
      timings = [];
      if (_probe == 'session') {
        await session();
      } else {
        await drag(switch (_probe) {
          'size' => size,
          'sample' => await sample(),
          _ => progress,
        });
      }
      await settle();
      final frames = timings
          .map(
            (t) => _ms(
              t.buildDuration > t.rasterDuration
                  ? t.buildDuration
                  : t.rasterDuration,
            ),
          )
          .toList();
      final build = timings.map((t) => _ms(t.buildDuration)).toList();
      // ignore: avoid_print
      print(
        'PROBE $_probe round=$round frames=${frames.length} '
        'p50=${_percentile(frames, .5).toStringAsFixed(1)} '
        'p90=${_percentile(frames, .9).toStringAsFixed(1)} '
        'max=${_percentile(frames, 1).toStringAsFixed(1)} '
        'buildP90=${_percentile(build, .9).toStringAsFixed(1)} '
        'tickers=${tester.binding.transientCallbackCount} '
        'rssMB=${(ProcessInfo.currentRss / 1048576).toStringAsFixed(0)}',
      );
    }
  });
}
