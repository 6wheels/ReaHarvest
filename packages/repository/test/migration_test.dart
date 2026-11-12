import 'dart:convert';
import 'dart:io';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const fixtures = '../../test/fixtures';

void main() {
  late MemoryStorage storage;
  late List<String> hashed;

  /// Test hasher: the content itself, recording the paths hashed.
  Future<String> hash(String path) async {
    hashed.add(path);
    return storage.text(path);
  }

  Library library() => Library(
    id: LibraryId.generate(),
    mode: LibraryMode.local,
    layout: Layout([const LayoutLevel('title')]),
  );

  setUp(() {
    storage = MemoryStorage();
    hashed = [];
  });

  test('starts a stamped migration, writing nothing', () {
    final migration = Migration.start(
      storage,
      now: DateTime(2026, 11, 9, 8, 5, 3),
    );
    expect(migration.folder, '.migration/2026-11-09_080503_000');
    expect(migration.inventory.folder, migration.folder);
    expect(migration.inventory.isComplete, isFalse);
    expect(migration.journal.length, 0);
    expect(() => migration.storage, throwsStateError);
    expect(storage.log, isEmpty);
  });

  test('a new migration reuses the hashes of the previous one', () async {
    storage
      ..put('a.wav', 'aaaa')
      ..put('b.wav', 'bbbb');
    final first = Migration.start(storage, now: DateTime(2026, 11, 9));
    await first.inventory.take(hash);
    await first.storage.move('a.wav', 'x/a.wav');
    storage.put('b.wav', 'BB');
    hashed.clear();

    final next = Migration.start(
      storage,
      now: DateTime(2026, 11, 10),
      previous: (await Migration.latest(storage))!,
    );
    await next.inventory.take(hash);

    expect(hashed, ['b.wav'], reason: 'moved but unchanged: not hashed');
    expect(next.inventory.files.keys, unorderedEquals(['x/a.wav', 'b.wav']));
    expect(next.inventory.files['b.wav']!.hash, 'BB');
    final latest = (await Migration.latest(storage))!;
    expect(latest.folder, next.folder);
    expect(
      (await latest.inventory.check(
        hash,
        locate: latest.journal.locate,
      )).isEmpty,
      isTrue,
    );
  });

  test('latest reads the inventory and journal, complete or not', () async {
    storage.put('a.wav', 'a');
    final migration = Migration.start(storage);
    var calls = 0;
    await expectLater(
      migration.inventory.take(
        hash,
        checkCancelled: () {
          if (++calls > 0) throw const FormatException('cancelled');
        },
      ),
      throwsFormatException,
    );
    final interrupted = (await Migration.latest(storage))!;
    expect(interrupted.folder, migration.folder);
    expect(interrupted.inventory.isComplete, isFalse);

    await interrupted.inventory.take(hash);
    await interrupted.storage.move('a.wav', 'b.wav');
    final latest = (await Migration.latest(storage))!;
    expect(latest.inventory.isComplete, isTrue);
    expect(latest.journal.locate('a.wav'), 'b.wav');
  });

  test('migrations in the former format are ignored', () async {
    expect(await Migration.latest(storage), isNull);
    storage
      ..put('.migration/note.txt', '')
      ..put('.migration/2026-01-01_000000_000/inventory.json', '{}')
      ..put('.migration/2026-01-01_000000_000/moves.json', '{}');
    expect(await Migration.latest(storage), isNull);
  });

  group('rewrittenSince', () {
    Future<Migration> migrated(DateTime now) async {
      final m = Migration.start(storage, now: now);
      await m.inventory.take(hash);
      return m;
    }

    test('starts before any journal when there is no migration', () async {
      final none = await rewrittenSince(storage, null);
      expect(none.paths, isEmpty);
      expect(none.position, (folder: '', line: 0));
      const position = (folder: '.migration/x', line: 3);
      expect((await rewrittenSince(storage, position)).position, position);
    });

    test('a null position gives the end of the latest journal', () async {
      storage.put('a.rpp', 'a');
      final m = await migrated(DateTime(2026, 1, 1));
      await m.storage.write('a.rpp', Stream.value([65]));

      final since = await rewrittenSince(storage, null);
      expect(since.paths, isEmpty);
      expect(since.position, (folder: m.folder, line: 1));
    });

    test('follows the rewritten files over later migrations', () async {
      storage
        ..put('a.rpp', 'a')
        ..put('b.rpp', 'b');
      final first = await migrated(DateTime(2026, 1, 1));
      await first.storage.write('a.rpp', Stream.value([65]));
      final position = (folder: first.folder, line: first.journal.length);
      await first.storage.write('b.rpp', Stream.value([66]));
      final second = Migration.start(
        storage,
        now: DateTime(2026, 1, 2),
        previous: first,
      );
      await second.inventory.take(hash);
      await second.storage.move('b.rpp', 'song/b.rpp');

      final since = await rewrittenSince(storage, position);
      expect(since.paths, {'song/b.rpp'});
      expect(since.position, (folder: second.folder, line: 1));
      expect((await rewrittenSince(storage, (folder: '', line: 0))).paths, {
        'a.rpp',
        'song/b.rpp',
      });
      expect(
        (await rewrittenSince(storage, (folder: second.folder, line: 1))).paths,
        isEmpty,
      );
    });
  });

  test(
    'a project rewritten before a crash is read again by the scan',
    () async {
      final project = File('$fixtures/tracks.rpp').readAsStringSync();
      storage.put('song/v1.rpp', project);
      final lib = library();
      final first = await scan(storage, lib);
      expect(first.titles.single.versions.single.tempo, 128);

      final migration = Migration.start(storage);
      await migration.inventory.take(hash);
      // Same size, date restored: only the journal tells it changed.
      await migration.storage.write(
        'song/v1.rpp',
        Stream.value(
          utf8.encode(project.replaceFirst('TEMPO 128', 'TEMPO 129')),
        ),
      );
      // The application stops here, before its rescan.

      final rescan = await scan(
        storage,
        lib,
        previous: first,
        journalPosition: first.journalPosition,
      );
      expect(rescan.titles.single.versions.single.tempo, 129);
      expect(rescan.journalPosition, (
        folder: migration.folder,
        line: migration.journal.length,
      ));
    },
  );

  test('the scan ignores .migration', () async {
    storage.put('.migration/s/originals/song/v.rpp', 'x');
    final result = await scan(storage, library());
    expect(result.titles, isEmpty);
    expect(result.issues.isEmpty, isTrue);
  });
}
