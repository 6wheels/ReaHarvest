import 'dart:convert';
import 'dart:io';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';
import 'migration_batch_test.dart' show Reporter, sizeHasher;

const song = 'Band/Album/Song';

/// Project referencing [media], with the record path [record].
String rpp(List<String> media, {String record = 'audio-files'}) => [
  '<REAPER_PROJECT 0.1 "7.0" 0',
  '  RECORD_PATH "$record" ""',
  '  <TRACK',
  for (final m in media) ...[
    '    <ITEM',
    '      <SOURCE WAVE',
    '        FILE "$m"',
    '      >',
    '    >',
  ],
  '  >',
  '>',
  '',
].join('\n');

String node(String id) =>
    '${jsonEncode(NodeFile(NodeId(id), 'title').toJson())}\n';

/// A fix of each kind (SPEC §5.8 step 4) on the library of [library].
const fixes = <String, MigrationFix>{
  'normalization': NormalizeMedia(song),
  'lift': LiftProject('$song/Alice/take.rpp', song, owner: MemberId('alice')),
  'merge': MoveFolder('Band/Song', song),
  'guided move': MoveProject('Band/loose.rpp', song),
};

void main() {
  late MemoryStorage storage;

  Future<String> hash(String path) async =>
      base64.encode(await storage.read(path).expand((c) => c).toList());

  /// A title with media to normalize and a member subfolder, a copy of it
  /// at the root to merge, and a loose project to move into it.
  void library() => storage
    ..put('$song/.node.json', node('01JC0000000000000000000001'))
    ..put('$song/a.rpp', rpp([r'audio\x.wav', r'.\sub.rpp']))
    ..put('$song/b.rpp', rpp([r'audio\x.wav', r'old\bass.wav']))
    ..put('$song/sub.rpp', rpp([r'audio\y.wav'], record: 'Media'))
    ..put('$song/sub.rpp-PROX', 'proxy')
    ..put('$song/Media/bass.wav', 'bass')
    ..put('$song/old/bass.wav', 'bass')
    ..put('$song/audio/x.wav', 'x')
    ..put('$song/audio/y.wav', 'y')
    ..put('$song/Alice/take.rpp', rpp([r'Media\t.wav']))
    ..put('$song/Alice/Media/t.wav', 't')
    ..put('Band/Song/.node.json', node('01JC0000000000000000000002'))
    ..put('Band/Song/a.rpp', rpp([r'audio\x.wav']))
    ..put('Band/Song/audio/x.wav', 'x2')
    ..put('Band/loose.rpp', rpp([r'loose\l.wav']))
    ..put('Band/loose/l.wav', 'l');

  /// Every file outside `.migration/`, with its content and date.
  Map<String, (String, DateTime)> tree() => {
    for (final MapEntry(:key, :value) in storage.files.entries)
      if (!key.startsWith('$migrationFolderName/'))
        key: (utf8.decode(value.bytes), value.modified),
  };

  Future<BatchResult> batch(List<MigrationFix> fixes, Reporter reporter) =>
      runMigrationBatch(
        storage,
        fixes,
        usage: const {},
        hash: hash,
        reporter: reporter,
        now: DateTime(2026, 11, 13),
      );

  /// A migration of the library, its inventory taken.
  Future<Migration> migration() async {
    final m = Migration.start(storage, now: DateTime(2026, 11, 13));
    await m.inventory.take(hash);
    return m;
  }

  /// Whether the failure set at [failAt] was reached.
  bool reached(int failAt) => storage.changes >= failAt;

  setUp(() {
    storage = MemoryStorage();
    library();
  });

  test('each fix of the tests completes without failure', () async {
    final result = await batch([...fixes.values], Reporter());

    expect(result.report.hasErrors, isFalse, reason: '${result.report}');
    expect(storage.files.keys, contains('$song/take.rpp'));
    expect(storage.files.keys, contains('$song/loose.rpp'));
    expect(storage.files.keys, contains('$song/Media/t.wav'));
  });

  for (final partial in [null, 0.5, 1.0]) {
    final cut = switch (partial) {
      null => '',
      1.0 => ', its journal line written',
      _ => ', its journal line cut',
    };
    for (final MapEntry(key: name, value: fix) in fixes.entries) {
      test('a $name failing at any change is undone at once$cut', () async {
        for (var k = 1; ; k++) {
          storage = MemoryStorage()..appendedOnFailure = partial;
          library();
          final before = tree();
          var failAt = 0;
          final reporter = Reporter(
            onStep: (step) {
              if (step == 'fix 1/1') {
                storage.failAt = failAt = storage.changes + k;
              }
            },
          );

          final result = await batch([fix], reporter);

          final reason = '$name, change $k: ${storage.failed}';
          if (!reached(failAt)) {
            // Past the last change of the fix: it completed.
            expect(result.report.hasErrors, isFalse, reason: reason);
            expect(k, greaterThan(3), reason: reason);
            break;
          }
          final report = result.report;
          expect(report.items[ReportKind.fixFailed]!.single.path, fix.path);
          expect(report.items[ReportKind.fileLost], isNull, reason: reason);
          expect(report.items[ReportKind.undoFailed], isNull, reason: reason);
          expect(tree(), before, reason: reason);
          expect(await unfinishedFixIn(storage), isNull, reason: reason);
        }
      });

      test('a $name stopped at any change is undone later$cut', () async {
        for (var k = 1; ; k++) {
          storage = MemoryStorage()..appendedOnFailure = partial;
          library();
          final m = await migration();
          final before = tree();
          final failAt = storage.failAt = storage.changes + k;
          storage.failAfter = true;

          try {
            await applyFixes(m, [fix], hash: hash);
          } on InjectedFailure {
            // The application stopped: nothing more is written.
          }

          final reason = '$name, change $k: ${storage.failed}';
          storage
            ..failAt = null
            ..failAfter = false
            ..failed = null;
          if (!reached(failAt)) {
            expect(await unfinishedFixIn(storage), isNull, reason: reason);
            expect(k, greaterThan(3), reason: reason);
            break;
          }
          // Read again from the disk, as after a restart.
          final unfinished = await unfinishedFixIn(storage);
          if (unfinished == null) {
            final read = (await Migration.latest(storage))!;
            if (read.journal.lastFix == null) {
              // Its start line not written whole: the fix never started.
              expect(tree(), before, reason: reason);
            } else {
              // Its end line written whole: the fix completed.
              final check = await read.inventory.check(
                hash,
                locate: read.journal.locate,
              );
              expect(check.isEmpty, isTrue, reason: reason);
            }
            continue;
          }
          expect(unfinished.path, fix.path, reason: reason);

          final report = await undoUnfinishedFix(storage, hash: hash);

          expect(report.items[ReportKind.fixUndone], [ReportItem(fix.path)]);
          expect(report.items[ReportKind.fileLost], isNull, reason: reason);
          expect(tree(), before, reason: reason);
          expect(await unfinishedFixIn(storage), isNull, reason: reason);
        }
      });
    }
  }

  for (final MapEntry(key: name, value: fix) in fixes.entries) {
    test('the undo of a $name stopped at any change is resumed', () async {
      // Changes of the fix, its start and end lines included.
      final m = await migration();
      final from = storage.changes;
      await applyFixes(m, [fix], hash: hash);
      final fixChanges = storage.changes - from;

      for (var j = 1; ; j++) {
        storage = MemoryStorage();
        library();
        final m = await migration();
        final before = tree();
        // Stopped at its end line: every operation is to undo.
        storage
          ..failAt = storage.changes + fixChanges
          ..failAfter = true;
        await expectLater(
          applyFixes(m, [fix], hash: hash),
          throwsA(isA<InjectedFailure>()),
        );
        expect(storage.failed, startsWith('append'));
        storage
          ..failAt = null
          ..failAfter = false
          ..failed = null;

        // The undo stops at its change j, then runs again.
        final failAt = storage.failAt = storage.changes + j;
        storage.failAfter = true;
        try {
          await undoUnfinishedFix(storage, hash: hash);
        } on InjectedFailure {
          // Stopped.
        }
        final reason = '$name, undo change $j: ${storage.failed}';
        storage
          ..failAt = null
          ..failAfter = false
          ..failed = null;
        final done = !reached(failAt);

        final report = await undoUnfinishedFix(storage, hash: hash);

        expect(report.items[ReportKind.fileLost], isNull, reason: reason);
        expect(tree(), before, reason: reason);
        expect(await unfinishedFixIn(storage), isNull, reason: reason);
        if (done) {
          // Nothing left to undo the second time.
          expect(report.isEmpty, isTrue, reason: reason);
          expect(j, greaterThan(3), reason: reason);
          break;
        }
        expect(report.items[ReportKind.fixUndone], [ReportItem(fix.path)]);
      }
    });
  }

  test('a lift whose write fails after its move is undone (#91)', () async {
    const lift = LiftProject('$song/Alice/take.rpp', song);
    for (var k = 1; ; k++) {
      storage = MemoryStorage();
      library();
      final before = tree();
      final result = await batch(
        [lift],
        Reporter(
          onStep: (step) {
            if (step == 'fix 1/1') storage.failAt = storage.changes + k;
          },
        ),
      );
      if (storage.failed != 'write $song/take.rpp') continue;

      expect(storage.log, contains('move $song/Alice/take.rpp $song/take.rpp'));
      expect(result.report.items[ReportKind.fixUndone], [
        const ReportItem('$song/Alice/take.rpp'),
      ]);
      expect(tree(), before);
      break;
    }
  });

  group('a move', () {
    test('missing its source or onto a target fails before its line', () async {
      final m = await migration();
      final before = tree();
      final fix = await m.journal.startFix('moveFolder', 'Band/Song');
      final lines = m.journal.length;

      await expectLater(
        m.storage.move('Band/Gone', 'Band/New'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        m.storage.move('Band/Song', song),
        throwsA(isA<StateError>()),
      );
      expect(m.journal.length, lines);

      final report = await undoFix(storage, m, fix);
      expect(report.items[ReportKind.fixUndone], [
        const ReportItem('Band/Song'),
      ]);
      expect(tree(), before);
    });

    test('journaled but never made is not moved back', () async {
      final m = await migration();
      final before = tree();
      final journal = '${m.folder}/${MigrationJournal.fileName}';
      String line(Map<String, Object?> json) => '${jsonEncode(json)}\n';
      storage.put(
        journal,
        [
          line({'op': 'fixStart', 'fix': 1, 'kind': 'moveFolder', 'path': 'x'}),
          // Source and target both present: the move threw.
          line({'op': 'move', 'from': 'Band/Song', 'to': song}),
          // Neither present.
          line({'op': 'move', 'from': 'Band/Gone', 'to': 'Band/New'}),
        ].join(),
      );

      final report = await undoUnfinishedFix(storage, hash: hash);

      expect(report.items[ReportKind.fixUndone], [const ReportItem('x')]);
      expect(report.items[ReportKind.fileLost], isNull);
      expect(tree(), before);
    });
  });

  test('two fixes rewriting one project: the second undone alone', () async {
    const fixes = [
      LiftProject('$song/Alice/take.rpp', song),
      NormalizeMedia(song),
    ];
    for (var k = 1; ; k++) {
      storage = MemoryStorage();
      library();
      Map<String, (String, DateTime)>? afterFirst;
      var failAt = 0;
      final result = await batch(
        fixes,
        Reporter(
          onStep: (step) {
            if (step == 'fix 2/2') {
              afterFirst = tree();
              storage.failAt = failAt = storage.changes + k;
            }
          },
        ),
      );
      final reason = 'change $k: ${storage.failed}';
      if (!reached(failAt)) {
        expect(result.report.hasErrors, isFalse, reason: reason);
        break;
      }
      // The first fix's rewrite of the lifted project is kept.
      expect(afterFirst!['$song/take.rpp']!.$1, contains(r'Alice\Media'));
      expect(tree(), afterFirst, reason: reason);
      expect(result.report.items[ReportKind.projectMoved], [
        const ReportItem('$song/take.rpp'),
      ]);
    }
  });

  test('a file created then rewritten is undone fix by fix', () async {
    final m = await migration();
    Stream<List<int>> text(String s) => Stream.value(utf8.encode(s));

    // Fix 1, completed: creates new.txt, then rewrites it and a.rpp.
    final first = await m.journal.startFix('normalizeMedia', song);
    await m.storage.write('$song/new.txt', text('created'));
    await m.storage.write('$song/new.txt', text('first'));
    await m.storage.write('$song/a.rpp', text('first'));
    await m.journal.endFix(first, ok: true);
    final afterFirst = tree();

    // Fix 2, failed: rewrites both again, creates and rewrites another.
    final second = await m.journal.startFix('normalizeMedia', song);
    await m.storage.write('$song/new.txt', text('second'));
    await m.storage.write('$song/a.rpp', text('second'));
    await m.storage.write('$song/other.txt', text('created'));
    await m.storage.write('$song/other.txt', text('second'));
    await m.journal.endFix(second, ok: false);

    final report = await undoFix(storage, m, second);

    expect(report.items[ReportKind.fixUndone], [const ReportItem(song)]);
    // Back to the end of fix 1, not to the inventory.
    expect(tree(), afterFirst);
    // Its rewrite undone first, then the created file set aside.
    expect(storage.text('${m.folder}/undone/$song/other.txt'), 'created');
    expect(storage.text('${m.folder}/originals/$song/a.rpp'), isNot('first'));
    expect(await unfinishedFixIn(storage), isNull);
  });

  test('a rewrite without copy cannot be undone', () async {
    final m = await migration();
    final journal = '${m.folder}/${MigrationJournal.fileName}';
    String line(Map<String, Object?> json) => '${jsonEncode(json)}\n';
    storage.put(
      journal,
      [
        line({'op': 'fixStart', 'fix': 1, 'kind': 'liftProject', 'path': 'x'}),
        line({'op': 'rewrite', 'path': '$song/a.rpp', 'modified': 0}),
      ].join(),
    );

    await expectLater(
      undoUnfinishedFix(storage, hash: hash),
      throwsA(isA<StateError>()),
    );
    expect((await unfinishedFixIn(storage))?.fix, 1);
  });

  test('a missing copy stops the undo, the fix left to undo', () async {
    final m = await migration();
    final fix = await m.journal.startFix('normalizeMedia', song);
    await m.storage.write('$song/a.rpp', Stream.value(utf8.encode('new')));
    final copy =
        (await MigrationJournal.read(
              storage,
              m.folder,
            )).operationsOf(fix).single['copy']
            as String;
    storage.files.remove(copy);

    await expectLater(
      undoUnfinishedFix(storage, hash: hash),
      throwsA(isA<StateError>()),
    );
    expect((await unfinishedFixIn(storage))?.fix, fix);
    expect(storage.text('$song/a.rpp'), 'new');
  });

  test('a missing copy among several rewrites: nothing is undone', () async {
    final m = await migration();
    Stream<List<int>> text(String s) => Stream.value(utf8.encode(s));
    final fix = await m.journal.startFix('normalizeMedia', song);
    await m.storage.move('$song/audio/x.wav', '$song/Media/x.wav');
    await m.storage.write('$song/a.rpp', text('new a'));
    await m.storage.write('$song/b.rpp', text('new b'));
    final copy =
        (await MigrationJournal.read(
              storage,
              m.folder,
            )).operationsOf(fix)[1]['copy']
            as String;
    final kept = storage.files.remove(copy)!;
    final after = tree();

    await expectLater(
      undoUnfinishedFix(storage, hash: hash),
      throwsA(isA<StateError>()),
    );
    // Not half undone: the later rewrite and the move are untouched.
    expect(tree(), after);
    expect(
      storage.text('${m.folder}/${MigrationJournal.fileName}'),
      isNot(contains('undoStart')),
    );

    // The copy is back (synced at last): the undo goes through.
    storage.files[copy] = kept;
    await undoUnfinishedFix(storage, hash: hash);
    expect(await unfinishedFixIn(storage), isNull);
    expect(tree().keys, contains('$song/audio/x.wav'));
  });

  test('the content replaced by an undo is kept', () async {
    final m = await migration();
    Stream<List<int>> text(String s) => Stream.value(utf8.encode(s));
    final before = storage.text('$song/a.rpp');
    await m.journal.startFix('normalizeMedia', song);
    await m.storage.write('$song/a.rpp', text('fixed'));
    // Saved in REAPER after the interruption, before the undo.
    storage.put('$song/a.rpp', 'saved since');

    await undoUnfinishedFix(storage, hash: hash);

    expect(storage.text('$song/a.rpp'), before);
    expect(storage.text('${m.folder}/replaced/$song/a.rpp'), 'saved since');
  });

  test('in an isolate, on a library folder', () async {
    final root = Directory.systemTemp.createTempSync('reaharvest_undo_');
    addTearDown(() => root.deleteSync(recursive: true));
    final disk = MountedFolderStorage(root.path);
    File('${root.path}/Song/a.rpp')
      ..createSync(recursive: true)
      ..writeAsStringSync('a');
    final m = Migration.start(disk);
    await m.inventory.take(sizeHasher(disk));
    await m.journal.startFix('moveFolder', 'Song');
    await m.storage.move('Song', 'New');

    final unfinished = await unfinishedFixOn(root.path);
    expect(unfinished?.path, 'Song');
    expect('${FixToUndo(unfinished!.path)}', contains('Song'));
    final report = await undoUnfinishedFixOn(root.path, hasherOf: sizeHasher);

    expect(report.items[ReportKind.fixUndone], [const ReportItem('Song')]);
    expect(report.items[ReportKind.fileLost], isNull);
    expect(File('${root.path}/Song/a.rpp').existsSync(), isTrue);
    expect(await unfinishedFixOn(root.path), isNull);
  });

  group('in a batch', () {
    test('a failing fix among others: the others applied', () async {
      final before = tree();
      final result = await batch(const [
        MoveFolder('Band/Gone', 'Band/New'),
        LiftProject('$song/Alice/take.rpp', song),
      ], Reporter());

      final report = result.report;
      expect(report.items[ReportKind.fixFailed]!.single.path, 'Band/Gone');
      expect(report.items[ReportKind.fixUndone], [
        const ReportItem('Band/Gone'),
      ]);
      expect(report.items[ReportKind.projectMoved], [
        const ReportItem('$song/take.rpp'),
      ]);
      expect(report.items[ReportKind.fileLost], isNull);
      expect(tree().keys, contains('$song/take.rpp'));
      expect(tree().keys, isNot(contains('$song/Alice/take.rpp')));
      expect(before.keys, contains('$song/Alice/take.rpp'));
      // Its journal: fix 1 undone, fix 2 completed.
      final m = (await Migration.latest(storage))!;
      expect(m.journal.unfinishedFix, isNull);
    });

    test(
      'a failing fix leaves the fixes of a later-stamped migration',
      () async {
        // A batch stamped after this one (clock set back since).
        final earlier = await runMigrationBatch(
          storage,
          const [MoveFolder('Band/Song', 'Band/Other')],
          usage: const {},
          hash: hash,
          reporter: Reporter(),
          now: DateTime(2026, 11, 14),
        );
        expect(earlier.report.hasErrors, isFalse);

        final result = await batch(const [
          MoveFolder('Band/Gone', 'Band/New'),
        ], Reporter());

        final report = result.report;
        expect(report.items[ReportKind.fixUndone], [
          const ReportItem('Band/Gone'),
        ]);
        expect(report.items[ReportKind.fileLost], isNull);
        expect(tree().keys, contains('Band/Other/a.rpp'));
        expect(tree().keys, isNot(contains('Band/Song/a.rpp')));
      },
    );

    test('an undo failing too stops the batch, refused until undone', () async {
      final before = tree();
      final reporter = Reporter(
        onStep: (step) {
          if (step == 'fix 1/2') {
            // The drive is gone from the third change of the fix on.
            storage
              ..failAt = storage.changes + 3
              ..failAfter = true;
          }
        },
      );

      final result = await batch(const [
        NormalizeMedia(song),
        MoveFolder('Band/Song', 'Band/Other'),
      ], reporter);

      final report = result.report;
      expect(report.items[ReportKind.fixFailed]!.single.path, song);
      expect(report.items[ReportKind.undoFailed]!.single.path, song);
      expect(report.items[ReportKind.undoFailed]!.single.detail, isNotEmpty);
      expect(report.items[ReportKind.fixUndone], isNull);
      // Stopped there: no other fix, no check.
      expect(reporter.steps, ['inventory', 'fix 1/2']);
      expect(result.cancelled, isFalse);
      expect(tree().keys, contains('Band/Song/a.rpp'));

      // The drive is back: the fix is offered, no batch runs meanwhile.
      storage
        ..failAt = null
        ..failAfter = false;
      expect((await unfinishedFixIn(storage))?.path, song);
      await expectLater(
        batch(const [MoveFolder('Band/Song', 'Band/Other')], Reporter()),
        throwsA(isA<FixToUndo>().having((e) => e.path, 'path', song)),
      );

      final undone = await undoUnfinishedFix(storage, hash: hash);
      expect(undone.items[ReportKind.fixUndone], [const ReportItem(song)]);
      expect(undone.items[ReportKind.fileLost], isNull);
      expect(tree(), before);
      final next = await batch(const [
        MoveFolder('Band/Song', 'Band/Other'),
      ], Reporter());
      expect(next.report.items[ReportKind.folderMoved], [
        const ReportItem('Band/Other'),
      ]);
    });

    test('a cancelled batch started again runs only what remains', () async {
      const first = MoveFolder('Band/Song', 'Band/Other');
      const second = MoveProject('Band/loose.rpp', song);
      final cancelled = await batch([
        first,
        second,
      ], Reporter(cancelAt: 'fix 1/2'));
      expect(cancelled.cancelled, isTrue);
      expect(await unfinishedFixIn(storage), isNull);

      final reporter = Reporter();
      final result = await batch([second], reporter);

      expect(reporter.steps, ['inventory', 'fix 1/1', 'check']);
      expect(result.report.hasErrors, isFalse);
      expect(tree().keys, containsAll(['Band/Other/a.rpp', '$song/loose.rpp']));
    });

    test('nothing to undo: an empty report', () async {
      expect(await unfinishedFixIn(storage), isNull);
      expect((await undoUnfinishedFix(storage, hash: hash)).isEmpty, isTrue);
    });
  });
}
