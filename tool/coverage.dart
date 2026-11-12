// Runs the test suites with line coverage and fails below the threshold
// (SPEC §8, #65). Reports are written as lcov files to `coverage/`.
//
// Usage (repository root): dart tool/coverage.dart [option...] [suite...]
//   suite: a package folder name (e.g. `domain`), `packages` (all of them),
//     `app` (widget + integration tests), or one part of the app: `widget`
//     or `integration`; all packages and `app` by default.
//   --batch=i/n  integration: runs only batch i of n (CI matrix, #126).
//   --no-gate    writes the reports without checking the threshold.
//   --gate-only  runs nothing, checks the threshold on the reports already
//                in `coverage/` (e.g. gathered from several CI jobs).
//
// - A package is measured on its own files with its own tests only.
// - `app` merges the widget tests and the Windows integration tests (the
//   latter run on Windows only), generated localizations excluded.
// - Uncovered lines that cannot be tested carry a justified
//   `// coverage:ignore-line|start|end|file` comment, honored by both runners.

import 'dart:io';

/// Minimum line coverage of every suite, in percent.
const _target = 95.0;

final _root = Directory.current.path;
final _out = '$_root${Platform.pathSeparator}coverage';

/// Generated entry point of an integration batch, in `apps/desktop`.
const _batchEntry = 'integration_test/batch.g.dart';

Future<void> main(List<String> args) async {
  if (!File('$_root/pubspec.yaml').existsSync() ||
      !Directory('$_root/packages').existsSync()) {
    _fail('Run from the repository root.');
  }
  final packages =
      Directory('$_root/packages')
          .listSync()
          .whereType<Directory>()
          .map((dir) => _name(dir.path))
          .toList()
        ..sort();
  final options = args.where((arg) => arg.startsWith('--')).toList();
  final names = args.where((arg) => !arg.startsWith('--')).toList();
  var gate = true;
  var run = true;
  var batch = 1;
  var batches = 1;
  for (final option in options) {
    final match = RegExp(r'^--batch=(\d+)/(\d+)$').firstMatch(option);
    if (option == '--no-gate') {
      gate = false;
    } else if (option == '--gate-only') {
      run = false;
    } else if (match != null) {
      batch = int.parse(match[1]!);
      batches = int.parse(match[2]!);
      if (batch < 1 || batch > batches) _fail('Invalid batch "$option".');
    } else {
      _fail('Unknown option "$option".');
    }
  }
  final known = [...packages, 'packages', 'app', 'widget', 'integration'];
  for (final name in names) {
    if (!known.contains(name)) _fail('Unknown suite "$name" (one of $known).');
  }
  final suites = [
    for (final name in names.isEmpty ? [...packages, 'app'] : names)
      if (name == 'packages') ...packages else name,
  ];

  Directory(_out).createSync(recursive: true);
  final failures = <String>[];
  for (final suite in suites) {
    final lcovs = !run
        ? _reports(suite)
        : switch (suite) {
            'app' => [
              await _runWidget(),
              ...await _runIntegration(batch, batches),
            ],
            'widget' => [await _runWidget()],
            'integration' => await _runIntegration(batch, batches),
            _ => [await _runPackage(suite)],
          };
    if (!gate) continue;
    if (lcovs.isEmpty) _fail('No coverage report for suite "$suite".');
    final coverage = _parse(lcovs, _owner(suite));
    final percent = _report(suite, coverage);
    if (percent < _target) {
      failures.add('$suite: ${_format(percent)} < ${_format(_target)}');
    }
  }

  stdout.writeln();
  if (!gate) {
    stdout.writeln('Reports written, threshold not checked.');
    return;
  }
  if (failures.isNotEmpty) {
    _fail('Coverage below threshold:\n  ${failures.join('\n  ')}');
  }
  stdout.writeln('Coverage OK.');
}

/// Reports of [suite] already in `coverage/`.
List<String> _reports(String suite) {
  bool matches(String name) => switch (suite) {
    'app' => name.startsWith('app-'),
    'widget' => name == 'app-widget.lcov',
    'integration' => name.startsWith('app-integration'),
    _ => name == '$suite.lcov',
  };
  return Directory(_out)
      .listSync()
      .whereType<File>()
      .map((file) => file.path)
      .where((path) => matches(_name(path)))
      .toList()
    ..sort();
}

/// Runs the tests of package [name], returns its lcov path.
Future<String> _runPackage(String name) async {
  final lcov = '$_out${Platform.pathSeparator}$name.lcov';
  // The running Dart executable: same SDK, no shell lookup.
  await _run(
    Platform.resolvedExecutable,
    ['test', '--coverage-path=$lcov'],
    'packages/$name',
    lcov,
  );
  return lcov;
}

/// Runs the widget tests of the app, returns its lcov path.
Future<String> _runWidget() async {
  final lcov = '$_out${Platform.pathSeparator}app-widget.lcov';
  await _run(
    'flutter',
    ['test', '--coverage', '--coverage-path=$lcov'],
    'apps/desktop',
    lcov,
  );
  return lcov;
}

/// Runs batch [batch] of [batches] of the integration test files of the app,
/// on Windows only. Returns its lcov path, none when skipped.
///
/// The files of a batch run from one generated entry point: one build and
/// one app launch per batch (a second app launch in the same `flutter test`
/// does not connect, "Unable to start the app on the device").
Future<List<String>> _runIntegration(int batch, int batches) async {
  if (!Platform.isWindows) {
    stdout.writeln('Integration tests skipped (Windows only).');
    return [];
  }
  final all =
      Directory('$_root/apps/desktop/integration_test')
          .listSync()
          .whereType<File>()
          .map((file) => _name(file.path))
          .where((name) => name.endsWith('_test.dart'))
          .toList()
        ..sort();
  final files = [
    for (var i = 0; i < all.length; i++)
      if (i % batches == batch - 1) all[i],
  ];
  if (files.isEmpty) return [];
  File('$_root/apps/desktop/$_batchEntry').writeAsStringSync(
    [
      '// Generated by tool/coverage.dart: integration batch $batch/$batches.',
      '',
      "import 'package:flutter_test/flutter_test.dart';",
      '',
      for (var i = 0; i < files.length; i++) "import '${files[i]}' as t$i;",
      '',
      'void main() {',
      for (var i = 0; i < files.length; i++)
        "  group('${files[i]}', t$i.main);",
      '}',
      '',
    ].join('\n'),
  );
  final lcov =
      '$_out${Platform.pathSeparator}app-integration-$batch-of-$batches.lcov';
  await _run(
    'flutter',
    [
      'test',
      _batchEntry,
      '-d',
      'windows',
      '--coverage',
      '--coverage-path=$lcov',
    ],
    'apps/desktop',
    lcov,
  );
  return [lcov];
}

/// Runs [executable] in [directory], writing the lcov report [lcov].
Future<void> _run(
  String executable,
  List<String> args,
  String directory,
  String lcov,
) async {
  final report = File(lcov);
  if (report.existsSync()) report.deleteSync();
  stdout.writeln('\n> $directory: $executable ${args.join(' ')}');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: '$_root/$directory',
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('Tests failed in $directory (exit code $code).');
  if (!report.existsSync()) _fail('No coverage report written by $directory.');
}

/// Whether a source file (path with `/` separators) is measured in [suite].
bool Function(String) _owner(String suite) =>
    const ['app', 'widget', 'integration'].contains(suite)
    ? (path) =>
          path.startsWith('apps/desktop/lib/') &&
          !path.startsWith('apps/desktop/lib/l10n/')
    : (path) => path.startsWith('packages/$suite/lib/');

/// Source file of an lcov `SF:` entry, relative to the repository root with
/// `/` separators, so that the reports of other machines merge; null when it
/// is not a library file of the workspace.
String? _source(String entry) {
  final path = entry.replaceAll(r'\', '/');
  // Flutter writes paths relative to the app folder.
  if (path.startsWith('lib/')) return 'apps/desktop/$path';
  return RegExp(r'(?:^|/)((?:apps/desktop|packages/[^/]+)/lib/.*)$')
      .firstMatch(path)?[1];
}

/// Lines of the owned files in [lcovs]: path → line → covered. A line is
/// covered when any report hits it.
Map<String, Map<int, bool>> _parse(
  List<String> lcovs,
  bool Function(String) owned,
) {
  final coverage = <String, Map<int, bool>>{};
  for (final lcov in lcovs) {
    Map<int, bool>? lines;
    for (final line in File(lcov).readAsLinesSync()) {
      if (line.startsWith('SF:')) {
        final path = _source(line.substring(3));
        lines = path != null && owned(path)
            ? coverage.putIfAbsent(path, () => {})
            : null;
      } else if (line.startsWith('DA:') && lines != null) {
        final fields = line.substring(3).split(',');
        final number = int.parse(fields[0]);
        final hit = int.parse(fields[1]) > 0;
        lines[number] = (lines[number] ?? false) || hit;
      }
    }
  }
  return coverage;
}

/// Prints the coverage of [suite] and its incompletely covered files, with
/// their uncovered lines. Returns the suite coverage in percent.
double _report(String suite, Map<String, Map<int, bool>> coverage) {
  var total = 0;
  var hit = 0;
  final details = <String>[];
  for (final path in coverage.keys.toList()..sort()) {
    final lines = coverage[path]!;
    final covered = lines.values.where((value) => value).length;
    total += lines.length;
    hit += covered;
    if (covered < lines.length) {
      final missed = [
        for (final entry in lines.entries)
          if (!entry.value) entry.key,
      ]..sort();
      details.add(
        '    ${_format(100 * covered / lines.length).padLeft(6)}  '
        '$path  ${_ranges(missed)}',
      );
    }
  }
  if (total == 0) _fail('No measured line in suite "$suite".');
  final percent = 100 * hit / total;
  stdout.writeln('\nCoverage $suite: ${_format(percent)} ($hit/$total)');
  details.forEach(stdout.writeln);
  return percent;
}

/// Sorted line numbers as compact ranges: `3-5, 9`.
String _ranges(List<int> numbers) {
  final ranges = <String>[];
  for (var i = 0; i < numbers.length; i++) {
    final start = numbers[i];
    while (i + 1 < numbers.length && numbers[i + 1] == numbers[i] + 1) {
      i++;
    }
    ranges.add(start == numbers[i] ? '$start' : '$start-${numbers[i]}');
  }
  return ranges.join(', ');
}

String _format(double percent) => '${percent.toStringAsFixed(1)} %';

String _name(String path) => path.split(RegExp(r'[\\/]')).last;

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
