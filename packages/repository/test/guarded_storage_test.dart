import 'dart:convert';

import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const folder = '.migration/s';

void main() {
  late MemoryStorage storage;
  late Inventory inventory;
  late MigrationJournal journal;
  late GuardedStorage guarded;
  final date = DateTime(2020, 1, 2, 3, 4, 5);

  Future<String> hash(String path) async => storage.text(path);

  Stream<List<int>> text(String s) => Stream.value(utf8.encode(s));

  List<Map<String, dynamic>> lines() => [
    for (final l in const LineSplitter().convert(
      storage.text('$folder/${MigrationJournal.fileName}'),
    ))
      jsonDecode(l) as Map<String, dynamic>,
  ];

  setUp(() async {
    storage = MemoryStorage()
      ..put('a.rpp', 'original', modified: date)
      ..put('notes.txt', 'n', modified: date);
    inventory = Inventory(storage, folder);
    await inventory.take(hash);
    journal = MigrationJournal(storage, folder);
    guarded = GuardedStorage(storage, inventory, journal);
  });

  test('requires a complete inventory', () {
    expect(
      () =>
          GuardedStorage(storage, Inventory(storage, '.migration/t'), journal),
      throwsStateError,
    );
  });

  test('journals, keeps originals and restores project dates', () async {
    await guarded.move('a.rpp', 'song/a.rpp');
    await guarded.write('song/a.rpp', text('rewritten'));
    await guarded.write('song/a.rpp', text('rewritten twice'));
    await guarded.write('new.txt', text('new'));
    await guarded.write('new.txt', text('new, rewritten'));
    await guarded.write('notes.txt', text('notes'));
    await guarded.createDirectory('empty');
    await guarded.setModified('notes.txt', date);

    expect(
      [for (final l in lines()) l['op']],
      ['move', 'rewrite', 'rewrite', 'create', 'rewrite', 'rewrite'],
    );
    expect(lines()[0], {'op': 'move', 'from': 'a.rpp', 'to': 'song/a.rpp'});
    expect(lines()[1], {
      'op': 'rewrite',
      'path': 'song/a.rpp',
      'modified': date.microsecondsSinceEpoch,
      'copy': '$folder/originals/a.rpp',
    });
    // Later rewrites, and those of a file the migration created, get a
    // copy of their own (outside a fix: fix 0).
    expect(lines()[2]['copy'], '$folder/fixes/0/song/a.rpp');
    expect(storage.text('$folder/fixes/0/song/a.rpp'), 'rewritten');
    expect(lines()[3], {'op': 'create', 'path': 'new.txt'});
    expect(storage.text(lines()[4]['copy'] as String), 'new');
    expect(lines()[5]['path'], 'notes.txt');
    // The first original only, under its inventory path.
    expect(storage.text('$folder/originals/a.rpp'), 'original');
    expect(storage.files.containsKey('$folder/originals/new.txt'), isFalse);
    // A rewritten project keeps its date (version date).
    expect(storage.files['song/a.rpp']!.modified, date);
    expect(await guarded.stat('empty'), isNotNull);
    expect(await guarded.list(''), isNotEmpty);
    expect(await utf8.decodeStream(guarded.read('new.txt')), 'new, rewritten');
    expect(journal.rewrittenAfter(0), {'song/a.rpp', 'new.txt', 'notes.txt'});
    expect(
      (await inventory.check(hash, locate: journal.locate)).isEmpty,
      isTrue,
    );
  });

  test('refuses deletion, and appends outside .migration', () async {
    await expectLater(guarded.delete('notes.txt'), throwsUnsupportedError);
    await expectLater(guarded.append('notes.txt', [1]), throwsUnsupportedError);
    await guarded.append('$folder/log.txt', [65]);
    expect(storage.text('$folder/log.txt'), 'A');
    expect(storage.text('notes.txt'), 'n');
  });

  test('journals an operation before making it', () async {
    storage.failAt = storage.changes + 2;
    await expectLater(
      guarded.move('a.rpp', 'b.rpp'),
      throwsA(isA<InjectedFailure>()),
    );
    expect(lines().single['op'], 'move');
    expect(storage.files.containsKey('a.rpp'), isTrue);
  });

  test('a failure before the write leaves the file as it was', () async {
    // 1: copy of the original; 2: journal line.
    for (final k in [1, 2]) {
      storage.failAt = storage.changes + k;
      await expectLater(
        guarded.write('a.rpp', text('x')),
        throwsA(isA<InjectedFailure>()),
      );
      storage.failAt = null;
      expect(storage.text('a.rpp'), 'original');
    }
  });
}
