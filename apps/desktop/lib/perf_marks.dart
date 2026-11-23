// coverage:ignore-file
// Only built with `--dart-define=REAHARVEST_PERF=true` and exercised by the
// release-build benchmark (tool/perf/bench.dart, B1 and B7), which needs the
// real process, window and exit: no test can run it.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'state/tasks.dart';
import 'state/window_behavior.dart';

/// Build option of the benchmark build (docs/performance.md, B1 and B7).
const perfMode = bool.fromEnvironment('REAHARVEST_PERF');

/// Name of the marks file, in the data folder.
const perfMarksFile = 'perf-marks.txt';

/// Writes the timestamped marks of the benchmark: `first-frame` once the
/// first frame, with the titles served from the index, is shown; then, one
/// second later and once no task runs (the scan of startup, B7 is measured
/// with no task running), `quit` just before the quit request, made through
/// [WindowBehavior.quit] like "Quit" in the tray and the close button.
/// One line per mark: `<name> <microseconds since the epoch>`.
void startPerfMarks(ProviderContainer container, String dataFolder) {
  final file = File(p.join(dataFolder, perfMarksFile));
  void mark(String name) => file.writeAsStringSync(
    '$name ${DateTime.now().microsecondsSinceEpoch}\n',
    mode: FileMode.append,
    flush: true,
  );
  file.writeAsStringSync('');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    mark('first-frame');
    Timer(const Duration(seconds: 1), () {
      bool busy() =>
          container.read(tasksProvider).any((t) => t.isRunning || t.isQueued);
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (busy()) return;
        timer.cancel();
        mark('quit');
        container.read(windowBehaviorProvider).quit();
      });
    });
  });
}
