// Runs the test suites with line coverage and fails below the threshold
// (SPEC §8, #65). Reports are written as lcov files to `coverage/`.
//
// Usage (repository root): dart tool/coverage.dart [suite...]
//   suite: a package folder name (e.g. `domain`) or `app`; all by default.
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

Future<void> main(List<String> args) async {
  if (!File('$_root/pubspec.yaml').existsSync() ||
      !Directory('$_root/packages').existsSync()) {
    _fail('Run from the repository root.');
  }
  final packages = Directory('$_root/packages')
      .listSync()
      .whereType<Directory>()
      .map((dir) => _name(dir.path))
      .toList()
    ..sort();
  final all = [...packages, 'app'];
  final suites = args.isEmpty ? all : args;
  for (final suite in suites) {
    if (!all.contains(suite)) _fail('Unknown suite "$suite" (one of $all).');
  }

  Directory(_out).createSync(recursive: true);
  final failures = <String>[];
  for (final suite in suites) {
    final lcovs = suite == 'app' ? await _runApp() : [await _runPackage(suite)];
    final coverage = _parse(lcovs, _owner(suite));
    final percent = _report(suite, coverage);
    if (percent < _target) {
      failures.add('$suite: ${_format(percent)} < ${_format(_target)}');
    }
  }

  stdout.writeln();
  if (failures.isNotEmpty) {
    _fail('Coverage below threshold:\n  ${failures.join('\n  ')}');
  }
  stdout.writeln('Coverage OK.');
}

/// Runs the tests of package [name], returns its lcov path.
Future<String> _runPackage(String name) async {
  final lcov = '$_out${Platform.pathSeparator}$name.lcov';
  // The running Dart executable: same SDK, no shell lookup.
  await _run(Platform.resolvedExecutable, ['test', '--coverage-path=$lcov'],
      'packages/$name', lcov);
  return lcov;
}

/// Runs the widget tests and, on Windows, the integration tests of the app.
Future<List<String>> _runApp() async {
  final widget = '$_out${Platform.pathSeparator}app.lcov';
  await _run('flutter', ['test', '--coverage', '--coverage-path=$widget'],
      'apps/desktop', widget);
  if (!Platform.isWindows) {
    stdout.writeln('Integration tests skipped (Windows only).');
    return [widget];
  }
  // One `flutter test` per file: a second app launch in the same run does
  // not connect ("Unable to start the app on the device").
  final files = Directory('$_root/apps/desktop/integration_test')
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => name.endsWith('_test.dart'))
      .toList()
    ..sort();
  final lcovs = [widget];
  for (final name in files) {
    final integration = '$_out${Platform.pathSeparator}integration-$name.lcov';
    await _run(
      'flutter',
      [
        'test',
        'integration_test/$name',
        '-d',
        'windows',
        '--coverage',
        '--coverage-path=$integration',
      ],
      'apps/desktop',
      integration,
    );
    lcovs.add(integration);
  }
  return lcovs;
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
bool Function(String) _owner(String suite) => suite == 'app'
    ? (path) =>
        path.contains('/apps/desktop/lib/') &&
        !path.contains('/apps/desktop/lib/l10n/')
    : (path) => path.contains('/packages/$suite/lib/');

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
        var path = line.substring(3).replaceAll(r'\', '/');
        // Flutter writes paths relative to the app folder.
        if (path.startsWith('lib/')) {
          path = '${_root.replaceAll(r'\', '/')}/apps/desktop/$path';
        }
        lines = owned(path) ? coverage.putIfAbsent(path, () => {}) : null;
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
  final root = '${_root.replaceAll(r'\', '/')}/';
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
      details.add('    ${_format(100 * covered / lines.length).padLeft(6)}  '
          '${path.replaceFirst(root, '')}  ${_ranges(missed)}');
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
