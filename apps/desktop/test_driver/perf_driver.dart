// coverage:ignore-file
// Driver of the profile-mode benchmarks (integration_test/perf, B4 to B6 of
// docs/performance.md), run by tool/perf/bench.dart through `flutter drive`.
// Writes the data the test reports to the file named by the environment
// variable REAHARVEST_PERF_OUT.

import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final out = Platform.environment['REAHARVEST_PERF_OUT'];
    if (out == null || data == null) return;
    File(out).writeAsStringSync(jsonEncode(data));
  },
);
