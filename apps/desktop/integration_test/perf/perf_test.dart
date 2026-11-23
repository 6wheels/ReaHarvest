// coverage:ignore-file
// Benchmarks B4 to B6 of docs/performance.md, on the reference library, from
// the frame timings of the engine. Not a test of the app: it lives in a
// subfolder so that the coverage batches of tool/coverage.dart never take it.
// Run by tool/perf/bench.dart:
//   flutter drive --profile -d windows --driver=test_driver/perf_driver.dart
//     --target=integration_test/perf/perf_test.dart
//     --dart-define=REAHARVEST_PERF_LIBRARY=<reference library folder>

import 'dart:developer' show Timeline;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/ui/library_page.dart';
import 'package:reaharvest/ui/title_views.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../harness.dart';

const _library = String.fromEnvironment('REAHARVEST_PERF_LIBRARY');

/// Time of a frame: its slowest side, build or raster, in milliseconds.
double _frameMs(FrameTiming t) =>
    (t.buildDuration > t.rasterDuration ? t.buildDuration : t.rasterDuration)
        .inMicroseconds /
    1000;

double _percentile(List<double> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[(fraction * sorted.length).ceil().clamp(1, sorted.length) - 1];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('B4 to B6', (tester) async {
    expect(_library, isNotEmpty, reason: 'REAHARVEST_PERF_LIBRARY not set');
    final h = Harness();
    addTearDown(h.dispose);
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');

    var frames = <double>[];
    final timed = <FrameTiming>[];
    void onTimings(List<FrameTiming> timings) {
      timed.addAll(timings);
      frames.addAll(timings.map(_frameMs));
    }

    binding.addTimingsCallback(onTimings);
    addTearDown(() => binding.removeTimingsCallback(onTimings));

    // The timings reach the callback some time after their frames.
    Future<List<double>> collect(Future<void> Function() action) async {
      frames = [];
      await action();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      return frames;
    }

    // B6: the frames built while the first scan runs, the library having no
    // index yet. The window is on the clock of the engine, like B5.
    final before = h.tasks.length;
    timed.clear();
    var scanStart = 0;
    var scanEnd = 0;
    await collect(() async {
      scanStart = Timeline.now;
      final adding = h.catalog.addLocal(
        folder: _library,
        displayName: 'Reference',
        layout: Layout.classic(),
      );
      final end = DateTime.now().add(const Duration(minutes: 2));
      while (h.tasks.length <= before || h.tasks.last.isRunning) {
        if (DateTime.now().isAfter(end)) fail('The scan did not end');
        await tester.pump(const Duration(milliseconds: 16));
      }
      scanEnd = Timeline.now;
      await adding;
      await tester.pumpAndSettle();
    });
    final scanFrames = [
      for (final t in timed)
        if (t.timestampInMicroseconds(FramePhase.buildStart) >= scanStart &&
            t.timestampInMicroseconds(FramePhase.buildStart) <= scanEnd)
          _frameMs(t),
    ];
    await tapText(tester, 'Close');
    expect(h.container.read(titlesProvider), hasLength(1000));

    // B4: the list scrolled from top to bottom, one step per frame.
    h.container
        .read(navigationProvider.notifier)
        .setDisplayMode(DisplayMode.list);
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(TitleList),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final scrollFrames = await collect(() async {
      const steps = 200;
      for (var i = 1; i <= steps; i++) {
        position.jumpTo(position.maxScrollExtent * i / steps);
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    position.jumpTo(0);
    await tester.pumpAndSettle();

    // B5: one character added to the search, from the keystroke to the end
    // of the raster of the first frame built after it.
    final field = find.descendant(
      of: find.byType(LibrarySearchField),
      matching: find.byType(TextField),
    );
    final typing = <double>[];
    const query = 'title 00';
    for (var i = 1; i <= query.length; i++) {
      timed.clear();
      // The engine stamps its frames on the clock of Timeline.now.
      final keystroke = Timeline.now;
      await tester.enterText(field, query.substring(0, i));
      await tester.pump();
      // The timings reach the callback some time after their frames.
      final end = DateTime.now().add(const Duration(seconds: 5));
      FrameTiming? shown;
      while (shown == null) {
        if (DateTime.now().isAfter(end)) fail('No frame timing for B5');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        for (final t in timed) {
          if (t.timestampInMicroseconds(FramePhase.buildStart) >= keystroke) {
            shown = t;
            break;
          }
        }
      }
      typing.add(
        (shown.timestampInMicroseconds(FramePhase.rasterFinish) - keystroke) /
            1000,
      );
      await tester.pumpAndSettle();
    }
    typing.sort();

    expect(scanFrames, isNotEmpty);
    expect(scrollFrames, isNotEmpty);
    binding.reportData = {
      'B4 p90': _percentile(scrollFrames, 0.9),
      'B4 max': _percentile(scrollFrames, 1),
      'B5': typing[typing.length ~/ 2],
      'B6': _percentile(scanFrames, 1),
    };
  });
}
