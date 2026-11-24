// Runs every benchmark of docs/performance.md (B1 to B7) on the reference
// library and prints each measure against its budget. Exits 1 when a measure
// is over its budget or could not be measured.
//
// Usage: dart tool/perf/bench.dart [--ci] [--runs=<n>]
//
//   --ci        compare with the CI column of the budgets (twice the reference)
//   --runs=<n>  counted runs per measure (default 5), after one warm-up run
//
// Everything is built and written under `tmp/perf` (ignored by git). Needs
// `flutter` and the Windows toolchain: B1 and B7 are measured on a release
// build of the application, B2 and B3 on the scan compiled ahead of time,
// B4 to B6 on a profile-mode integration test.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'budgets.dart';

final _root = p.dirname(p.dirname(p.dirname(Platform.script.toFilePath())));
final _work = p.join(_root, 'tmp', 'perf');
final _library = p.join(_work, 'library');
final _data = p.join(_work, 'data');
final _app = p.join(_root, 'apps', 'desktop');

Future<void> main(List<String> args) async {
  if (!Platform.isWindows) {
    stderr.writeln('The benchmarks run on Windows only.');
    exitCode = 64;
    return;
  }
  final ci = args.contains('--ci');
  final runsOption = args
      .where((a) => a.startsWith('--runs='))
      .map((a) => int.parse(a.substring(7)))
      .firstOrNull;
  final runs = runsOption ?? 5;

  final results = <String, double?>{};
  await _scan(runs, results);
  await _interface(runs, results);
  await _startAndQuit(runs, results);

  final (:table, :ok) = formatTable(results, ci: ci);
  stdout
    ..writeln()
    ..writeln(table);
  File(p.join(_work, 'results.txt')).writeAsStringSync('$table\n');
  exitCode = ok ? 0 : 1;
}

/// Median of [runs] counted runs of [once], after one warm-up run.
Future<List<Map<String, double>>> _repeat(
  String what,
  int runs,
  Future<Map<String, double>> Function() once,
) async {
  final all = <Map<String, double>>[];
  for (var i = 0; i <= runs; i++) {
    stdout.writeln('$what: ${i == 0 ? 'warm-up' : 'run $i of $runs'}');
    final result = await once();
    if (i > 0) all.add(result);
  }
  return all;
}

void _medians(List<Map<String, double>> all, Results results) {
  for (final key in all.first.keys) {
    results[key] = median([for (final r in all) r[key]!]);
  }
}

/// Builds the reference library in [_library] and its data folder.
Future<void> _makeLibrary({bool tray = false, bool indexed = false}) =>
    _run('dart', [
      'run',
      'tool/perf/make_library.dart',
      _library,
      '--data=$_data',
      if (!indexed) '--no-index',
      if (tray) '--tray',
    ], _root);

/// B2 and B3, on the scan compiled ahead of time.
Future<void> _scan(int runs, Results results) async {
  await _makeLibrary();
  final build = p.join(_work, 'bench_scan');
  await _run('dart', [
    'build',
    'cli',
    '-t',
    'bin/bench_scan.dart',
    '-o',
    build,
  ], p.join(_root, 'packages', 'index'));
  final exe = p.join(build, 'bundle', 'bin', 'bench_scan.exe');
  final all = await _repeat('B2, B3', runs, () async {
    final out = await _run(exe, [
      _library,
      p.join(_data, 'index.sqlite'),
    ], _root);
    final json = jsonDecode(out.trim().split('\n').last) as Map;
    final reads = json['contentReads'] as int;
    if (reads != 0) throw StateError('The rescan read $reads file contents.');
    return {
      'B2': (json['b2'] as num).toDouble(),
      'B3': (json['b3'] as num).toDouble(),
    };
  });
  _medians(all, results);
}

/// B4 to B6, in profile mode.
Future<void> _interface(int runs, Results results) async {
  await _makeLibrary();
  final out = p.join(_work, 'frames.json');
  final all = await _repeat('B4, B5, B6', runs, () async {
    if (File(out).existsSync()) File(out).deleteSync();
    await _run(
      'flutter',
      [
        'drive',
        '--profile',
        '-d',
        'windows',
        '--driver=test_driver/perf_driver.dart',
        '--target=integration_test/perf/perf_test.dart',
        '--dart-define=REAHARVEST_PERF_LIBRARY=$_library',
      ],
      _app,
      environment: {'REAHARVEST_PERF_OUT': out},
    );
    final json = jsonDecode(File(out).readAsStringSync()) as Map;
    return {
      for (final e in json.entries)
        e.key as String: (e.value as num).toDouble(),
    };
  });
  _medians(all, results);
}

/// B1 and B7, on the release build, with the tray icon shown then hidden.
Future<void> _startAndQuit(int runs, Results results) async {
  // Indexed, so that the first frame shows the titles.
  await _makeLibrary(indexed: true);
  await _run('flutter', [
    'build',
    'windows',
    '--release',
    '--dart-define=REAHARVEST_PERF=true',
    '--dart-define=REAHARVEST_DATA_DIR=$_data',
  ], _app);
  final exe = p.join(
    _app,
    'build',
    'windows',
    'x64',
    'runner',
    'Release',
    'reaharvest.exe',
  );
  final settings = File(p.join(_data, 'settings.json'));
  final marks = File(p.join(_data, 'perf-marks.txt'));
  final starts = <double>[];
  for (final tray in [true, false]) {
    final json = jsonDecode(settings.readAsStringSync()) as Map;
    json['showInTray'] = tray;
    settings.writeAsStringSync(jsonEncode(json));
    final all = await _repeat(
      'B1, B7 (tray ${tray ? 'shown' : 'hidden'})',
      runs,
      () async {
        if (marks.existsSync()) marks.deleteSync();
        final started = DateTime.now();
        final process = await Process.start(exe, const []);
        // A hung quit must not hang the benchmark.
        var hung = false;
        final code = await process.exitCode.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            hung = true;
            process.kill();
            return -1;
          },
        );
        final exited = DateTime.now();
        final read = parseMarks(marks.readAsStringSync());
        final first = read['first-frame'];
        final quit = read['quit'];
        if (hung || first == null || quit == null) {
          throw StateError('The application did not run to its end.');
        }
        // The time counts to the end of the process, whatever its exit code.
        if (code != 0) stdout.writeln('  (exit code $code)');
        return {
          'B1': first.difference(started).inMicroseconds / 1000,
          'B7': exited.difference(quit).inMicroseconds / 1000,
        };
      },
    );
    final medians = <String, double?>{};
    _medians(all, medians);
    starts.add(medians['B1']!);
    results[tray ? 'B7 tray' : 'B7 no tray'] = medians['B7'];
  }
  // B1 is the same measure with the icon shown or hidden: the worst counts.
  results['B1'] = starts.reduce((a, b) => a > b ? a : b);
}

/// Runs [executable], returns its output; throws with it on failure.
Future<String> _run(
  String executable,
  List<String> args,
  String workingDirectory, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: true,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${args.join(' ')} failed (${result.exitCode}):\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return result.stdout as String;
}
