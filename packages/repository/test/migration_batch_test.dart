import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

/// Test reporter: records the steps (`fix 1/2`), progress and log lines
/// (`I text` or `W text`); cancelled from the step [cancelAt] on; [onStep]
/// runs after each step is recorded.
final class Reporter implements TaskReporter {
  Reporter({this.cancelAt, this.onStep});

  final String? cancelAt;
  final void Function(String step)? onStep;
  final steps = <String>[];
  final progresses = <double>[];
  final logs = <String>[];
  var cancelled = false;

  @override
  void step(TaskStep step, {int? index, int? total}) {
    final label = index == null ? step.name : '${step.name} $index/$total';
    steps.add(label);
    if (label == cancelAt) cancelled = true;
    onStep?.call(label);
  }

  @override
  void progress(double value) => progresses.add(value);

  @override
  bool get isCancelled => cancelled;

  @override
  void log(String message, {bool warning = false}) =>
      logs.add('${warning ? 'W' : 'I'} $message');
}

/// Isolate hasher: the size of the file (top-level, sendable).
Future<String> Function(String) sizeHasher(RepositoryStorage storage) =>
    (path) async => '${(await storage.stat(path))!.size}';

/// Isolate hasher that fails on every file.
Future<String> Function(String) failingHasher(RepositoryStorage storage) =>
    (path) async => throw StateError('No hash for $path');

void main() {
  late MemoryStorage storage;
  late List<String> hashed;

  /// Test hasher: the content itself, recording the paths hashed.
  Future<String> hash(String path) async {
    hashed.add(path);
    return storage.text(path);
  }

  Future<BatchResult> run(List<MigrationFix> fixes, Reporter reporter) =>
      runMigrationBatch(
        storage,
        fixes,
        usage: const {},
        hash: hash,
        reporter: reporter,
        now: DateTime(2026, 11, 12),
      );

  List<String> migrations() => [
    for (final d in storage.dirs)
      if (p.posix.dirname(d) == migrationFolderName) d,
  ];

  const moves = [MoveFolder('One', 'New/One'), MoveFolder('Two', 'New/Two')];

  setUp(() {
    storage = MemoryStorage()
      ..put('One/one.rpp', 'one')
      ..put('Two/two.rpp', 'two')
      ..put('Live/Three/three.rpp', 'three');
    hashed = [];
  });

  test('runs the fixes between an inventory and its check', () async {
    final reporter = Reporter();

    final result = await run([
      ...moves,
      const MoveFolder('Live', 'Live'),
    ], reporter);

    expect(result.cancelled, isFalse);
    expect(result.report.hasErrors, isFalse);
    expect(result.report.items[ReportKind.folderMoved], [
      const ReportItem('New/One'),
      const ReportItem('New/Two'),
    ]);
    expect(result.report.items[ReportKind.valueDeclared], [
      const ReportItem('Live'),
    ]);
    expect(result.knownPaths, ['Live', 'New/One', 'New/Two']);
    expect(
      storage.files.keys,
      containsAll(['New/One/one.rpp', 'New/Two/two.rpp']),
    );
    expect(reporter.steps, ['inventory', 'fix 1/2', 'fix 2/2', 'check']);
    expect(reporter.progresses.last, 1);
    expect(reporter.logs, [
      'I folder Live kept in place',
      startsWith('I Move folder One to New/One\n'),
      startsWith('I Move folder Two to New/Two\n'),
      'I inventory checked, no file lost',
    ]);
    // One inventory for the batch: every file hashed once.
    expect(migrations(), ['.migration/2026-11-12_000000_000']);
    expect(
      hashed,
      unorderedEquals(['One/one.rpp', 'Two/two.rpp', 'Live/Three/three.rpp']),
    );
  });

  test('only declares the folders kept in place, without inventory', () async {
    final reporter = Reporter();

    final result = await run([const MoveFolder('Live', 'Live')], reporter);

    expect(result.report.items.keys, [ReportKind.valueDeclared]);
    expect(result.knownPaths, ['Live']);
    expect(reporter.steps, isEmpty);
    expect(storage.log, isEmpty);
  });

  test('a failed fix is reported, the others go on', () async {
    final reporter = Reporter();

    final result = await run([
      const MoveFolder('Gone', 'New/Gone'),
      moves.first,
    ], reporter);

    expect(result.cancelled, isFalse);
    expect(result.report.items[ReportKind.fixFailed]!.single.path, 'Gone');
    expect(result.report.items[ReportKind.folderMoved], [
      const ReportItem('New/One'),
    ]);
    expect(reporter.logs[0], startsWith('W Move folder Gone to New/Gone\n'));
    expect(reporter.logs[1], startsWith('I Move folder One to New/One\n'));
    expect(result.knownPaths, ['New/Gone', 'New/One']);
  });

  test('a file changed during the batch is reported by the check', () async {
    final reporter = Reporter(
      onStep: (step) {
        if (step == 'fix 1/1') storage.put('Two/two.rpp', 'changed');
      },
    );

    final result = await run([moves.first], reporter);

    expect(result.report.items[ReportKind.fileLost], [
      const ReportItem('Two/two.rpp', 'changed'),
    ]);
    expect(reporter.logs.last, startsWith('W inventory checked\n'));
  });

  group('cancelled', () {
    test('during the inventory: nothing moved, resumed next time', () async {
      final reporter = Reporter(cancelAt: 'inventory');

      final result = await run([
        ...moves,
        const MoveFolder('Live', 'Live'),
      ], reporter);

      expect(result.cancelled, isTrue);
      expect(result.report.items.keys, [ReportKind.valueDeclared]);
      expect(result.knownPaths, ['Live']);
      expect(reporter.steps, ['inventory']);
      expect(reporter.logs.last, 'W cancelled after 0 of 2 fixes');
      expect(storage.files.keys, contains('One/one.rpp'));

      // The interrupted inventory is resumed, not started again.
      final next = await runMigrationBatch(
        storage,
        moves,
        usage: const {},
        hash: hash,
        reporter: Reporter(),
        now: DateTime(2026, 11, 13),
      );
      expect(next.cancelled, isFalse);
      expect(migrations(), ['.migration/2026-11-12_000000_000']);
    });

    test('between two fixes: the first one kept', () async {
      final reporter = Reporter(cancelAt: 'fix 1/2');

      final result = await run(moves, reporter);

      expect(result.cancelled, isTrue);
      expect(result.report.items[ReportKind.folderMoved], [
        const ReportItem('New/One'),
      ]);
      expect(result.knownPaths, ['New/One']);
      expect(storage.files.keys, contains('Two/two.rpp'));
      expect(reporter.steps, ['inventory', 'fix 1/2']);
      expect(reporter.logs.last, 'W cancelled after 1 of 2 fixes');
    });

    test('during the check: every fix kept', () async {
      final reporter = Reporter(cancelAt: 'check');

      final result = await run(moves, reporter);

      expect(result.cancelled, isTrue);
      expect(result.report.items[ReportKind.folderMoved], hasLength(2));
      expect(result.report.items[ReportKind.fileLost], isNull);
      expect(result.knownPaths, ['New/One', 'New/Two']);
      expect(reporter.logs.last, 'W cancelled after 2 of 2 fixes');
    });
  });

  group('in an isolate', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('reaharvest_batch_');
      for (final name in ['One', 'Two']) {
        File(p.join(dir.path, name, '$name.rpp'))
          ..createSync(recursive: true)
          ..writeAsStringSync(name);
      }
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('forwards the steps and log lines, returns the result', () async {
      final reporter = Reporter();

      final result = await runMigrationBatchOn(
        dir.path,
        moves,
        usage: const {},
        hasherOf: sizeHasher,
        reporter: reporter,
      );

      expect(result.cancelled, isFalse);
      expect(result.report.hasErrors, isFalse);
      expect(result.knownPaths, ['New/One', 'New/Two']);
      expect(
        File(p.join(dir.path, 'New', 'Two', 'Two.rpp')).existsSync(),
        isTrue,
      );
      expect(reporter.steps, ['inventory', 'fix 1/2', 'fix 2/2', 'check']);
      expect(reporter.progresses, isNotEmpty);
      expect(reporter.logs.last, 'I inventory checked, no file lost');
    });

    test('sends the cancellation to the isolate', () async {
      final reporter = Reporter()..cancelled = true;

      final result = await runMigrationBatchOn(
        dir.path,
        moves,
        usage: const {},
        hasherOf: sizeHasher,
        reporter: reporter,
      );

      expect(result.cancelled, isTrue);
      expect(result.report.items[ReportKind.folderMoved], isNull);
      expect(Directory(p.join(dir.path, 'One')).existsSync(), isTrue);
    });

    test('rethrows an error of the batch', () async {
      await expectLater(
        runMigrationBatchOn(
          dir.path,
          moves,
          usage: const {},
          hasherOf: failingHasher,
          reporter: Reporter(),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
