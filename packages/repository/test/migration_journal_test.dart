import 'dart:convert';

import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const folder = '.migration/s';
const file = '$folder/${MigrationJournal.fileName}';

void main() {
  late MemoryStorage storage;

  List<Map<String, dynamic>> lines() => [
    for (final l in const LineSplitter().convert(storage.text(file)))
      jsonDecode(l) as Map<String, dynamic>,
  ];

  Future<MigrationJournal> reread() => MigrationJournal.read(storage, folder);

  setUp(() => storage = MemoryStorage());

  test('appends one line per operation, in the documented format', () async {
    final journal = MigrationJournal(storage, folder);
    final fix = await journal.startFix('normalizeMedia', 'Band/Song');
    await journal.recordMove('Band/Song/audio/a.wav', 'Band/Song/Media/a.wav');
    await journal.recordRewrite(
      'Band/Song/Song.rpp',
      DateTime.fromMicrosecondsSinceEpoch(1731300000000000),
    );
    await journal.recordCreate('Band/Song/Media/b.wav');
    await journal.endFix(fix, ok: true);

    expect(fix, 1);
    expect(journal.length, 5);
    expect(lines(), [
      {
        'op': 'fixStart',
        'fix': 1,
        'kind': 'normalizeMedia',
        'path': 'Band/Song',
      },
      {
        'op': 'move',
        'from': 'Band/Song/audio/a.wav',
        'to': 'Band/Song/Media/a.wav',
      },
      {
        'op': 'rewrite',
        'path': 'Band/Song/Song.rpp',
        'modified': 1731300000000000,
      },
      {'op': 'create', 'path': 'Band/Song/Media/b.wav'},
      {'op': 'fixEnd', 'fix': 1, 'ok': true},
    ]);
    expect(storage.log, everyElement(startsWith('append ')));
    expect((await reread()).length, 5);
    expect(await journal.startFix('moveFolder', 'x'), 2);
  });

  test('a journal of 10 000 moves is written in linear time', () async {
    final journal = MigrationJournal(storage, folder);
    const moves = 10000;
    for (var i = 0; i < moves; i++) {
      await journal.recordMove('a/$i.wav', 'b/$i.wav');
    }
    // A rewrite of the whole journal at each move would pass about
    // 10 000 * 10 000 / 2 lines.
    expect(storage.bytesWritten, lessThan(moves * 64));
    expect((await reread()).locate('a/9999.wav'), 'b/9999.wav');
  });

  test('locates a file through moves of files and folders', () async {
    final journal = MigrationJournal(storage, folder);
    await journal.recordMove('song/take.wav', 'song/Media/take.wav');
    await journal.recordMove('song/member', 'song/from-member');
    await journal.recordMove('song/from-member/m.rpp', 'song/m.rpp');

    for (final j in [journal, await reread()]) {
      expect(j.locate('song/take.wav'), 'song/Media/take.wav');
      expect(j.locate('song/member/sub/x.wav'), 'song/from-member/sub/x.wav');
      expect(j.locate('song/member/m.rpp'), 'song/m.rpp');
      expect(j.locate('other.txt'), 'other.txt');
      expect(j.origin('song/m.rpp'), 'song/member/m.rpp');
      expect(j.origin('song/from-member/sub/x.wav'), 'song/member/sub/x.wav');
      expect(j.origin('other.txt'), 'other.txt');
    }
  });

  test('a file created by the migration has no origin', () async {
    final journal = MigrationJournal(storage, folder);
    await journal.recordMove('a.rpp', 'old/a.rpp');
    await journal.recordCreate('a.rpp');
    await journal.recordMove('a.rpp', 'new/a.rpp');

    expect(journal.origin('new/a.rpp'), isNull);
    expect(journal.origin('old/a.rpp'), 'a.rpp');
    expect((await reread()).origin('new/a.rpp'), isNull);
  });

  test('finds the fix left unfinished', () async {
    final journal = MigrationJournal(storage, folder);
    expect(journal.unfinishedFix, isNull);
    await journal.endFix(await journal.startFix('moveFolder', 'a'), ok: true);
    expect(journal.unfinishedFix, isNull);
    final failed = await journal.startFix('moveFolder', 'b');
    await journal.endFix(failed, ok: false);
    expect(journal.unfinishedFix, failed);
    final interrupted = await journal.startFix('liftProject', 'c/d.rpp');
    expect(journal.unfinishedFix, interrupted);
    expect((await reread()).unfinishedFix, interrupted);

    // An undone fix (#94) is no longer to undo.
    storage
      ..put(file, '${storage.text(file)}{"op":"undoStart","fix":3}\n')
      ..put(file, '${storage.text(file)}{"op":"undoEnd","fix":3}\n');
    expect((await reread()).unfinishedFix, failed);
  });

  test('ignores the operations of an undone fix', () async {
    final journal = MigrationJournal(storage, folder);
    final fix = await journal.startFix('moveProject', 'x/a.rpp');
    await journal.recordMove('x/a.rpp', 'song/a.rpp');
    await journal.recordRewrite('song/a.rpp', DateTime(2020));
    await journal.endFix(fix, ok: false);
    final before = journal.length;
    storage
      ..put(file, '${storage.text(file)}{"op":"undoStart","fix":1}\n')
      ..put(file, '${storage.text(file)}{"op":"undoEnd","fix":1}\n');

    final undone = await reread();
    expect(undone.locate('x/a.rpp'), 'x/a.rpp');
    expect(undone.rewrittenAfter(0), {'x/a.rpp'});
    // The restored file is rewritten after any position before the undo.
    expect(undone.rewrittenAfter(before), {'x/a.rpp'});
    expect(undone.rewrittenAfter(undone.length), isEmpty);
  });

  test('gives the current paths of the files rewritten after a line', () async {
    final journal = MigrationJournal(storage, folder);
    await journal.recordRewrite('a.rpp', DateTime(2020));
    final position = journal.length;
    await journal.recordRewrite('b.rpp', DateTime(2020));
    await journal.recordMove('b.rpp', 'song/b.rpp');
    await journal.recordMove('a.rpp', 'song/a.rpp');
    await journal.recordRewrite('c.rpp', DateTime(2020));

    expect(journal.rewrittenAfter(0), {'song/a.rpp', 'song/b.rpp', 'c.rpp'});
    expect(journal.rewrittenAfter(position), {'song/b.rpp', 'c.rpp'});
    expect(journal.rewrittenAfter(journal.length), isEmpty);
  });

  test('ignores a last line cut by a crash, and keeps it invalid', () async {
    storage.put(
      file,
      '{"op":"move","from":"a","to":"b"}\n'
      'not json\n'
      '{"op":"move","from":"b","to":"c"}',
    );
    final journal = await reread();
    expect(journal.length, 2);
    expect(journal.locate('a'), 'b');

    await journal.recordMove('x', 'y');
    final again = await reread();
    expect(again.locate('a'), 'b', reason: 'the cut move never happened');
    expect(again.locate('x'), 'y');
    expect(again.length, 4);
  });

  test('a failed append is not recorded', () async {
    final journal = MigrationJournal(storage, folder);
    await journal.recordMove('a', 'b');
    storage.failAt = 2;
    await expectLater(
      journal.recordMove('b', 'c'),
      throwsA(isA<InjectedFailure>()),
    );
    expect(journal.locate('a'), 'b');
    storage.failAt = null;
    await journal.recordMove('x', 'y');
    expect((await reread()).locate('a'), 'b');
    expect((await reread()).locate('x'), 'y');
  });
}
