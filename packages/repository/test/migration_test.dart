import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late MountedFolderStorage storage;
  late List<String> hashed;

  File file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  void put(String path, [String content = '']) {
    final f = file(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  /// Test hasher: the content itself, recording the paths hashed.
  Future<String> hash(String path) {
    hashed.add(path);
    return utf8.decodeStream(storage.read(path));
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('reaharvest_migration_');
    storage = MountedFolderStorage(root.path);
    hashed = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('inventory covers every file outside .migration', () async {
    put('a/v.rpp', 'project');
    put('a/Media/x.wav', 'audio');
    put('.collab/m/member.json', '{}');
    put('.migration/old/inventory.json', '{}');
    put('a/w.rpp${MountedFolderStorage.tempSuffix}', 'tmp');
    final progress = <double>[];

    final migration = Migration.start(
      storage,
      now: DateTime(2026, 11, 9, 8, 5, 3),
    );
    expect(migration.folder, '.migration/2026-11-09_080503');
    expect(migration.inventoryComplete, isFalse);
    await migration.takeInventory(hash, onProgress: progress.add);

    expect(migration.inventoryComplete, isTrue);
    expect(
      migration.files.keys,
      unorderedEquals(['a/v.rpp', 'a/Media/x.wav', '.collab/m/member.json']),
    );
    expect(migration.files['a/v.rpp']!.hash, 'project');
    expect(migration.files['a/v.rpp']!.size, 7);
    expect(progress.last, 1);
    final saved = jsonDecode(
      file('${migration.folder}/inventory.json').readAsStringSync(),
    );
    expect(saved['complete'], isTrue);
    expect(saved['files'], hasLength(3));
    await expectLater(migration.takeInventory(hash), throwsStateError);
  });

  test('an interrupted inventory resumes from the files hashed', () async {
    for (var i = 0; i < 60; i++) {
      put('t/f$i.wav');
    }
    final first = Migration.start(storage);
    var calls = 0;
    void stopAt55() {
      if (++calls > 55) throw const FormatException('cancelled');
    }

    await expectLater(
      first.takeInventory(hash, checkCancelled: stopAt55),
      throwsFormatException,
    );
    expect(hashed, hasLength(55));

    put('t/new.wav');
    file('t/f0.wav').deleteSync();
    final resumed = (await Migration.latest(storage))!;
    expect(resumed.folder, first.folder);
    expect(resumed.inventoryComplete, isFalse);
    expect(resumed.files, hasLength(55));
    hashed.clear();
    final progress = <double>[];
    await resumed.takeInventory(hash, onProgress: progress.add);

    expect(hashed, hasLength(6));
    expect(hashed, contains('t/new.wav'));
    expect(resumed.files, hasLength(60));
    expect(resumed.files.containsKey('t/f0.wav'), isFalse);
    expect(progress.last, 1);
    expect((await Migration.latest(storage))!.inventoryComplete, isTrue);
  });

  test('latest skips folders without an inventory', () async {
    expect(await Migration.latest(storage), isNull);
    put('.migration/note.txt');
    put('.migration/9999-01-01_000000/moves.json', '{}');
    expect(await Migration.latest(storage), isNull);
  });

  test('changes require a complete inventory', () async {
    put('a.rpp');
    final migration = Migration.start(storage);
    await expectLater(migration.move('a.rpp', 'b.rpp'), throwsStateError);
    await expectLater(migration.keepOriginal('a.rpp'), throwsStateError);
    await expectLater(migration.check(hash), throwsStateError);
  });

  test('check follows moves and kept originals', () async {
    put('song/v.rpp', 'project');
    put('song/take.wav', 'audio');
    put('song/member/m.rpp', 'member');
    put('song/member/sub/x.wav', 'x');
    put('other.txt', 'other');
    final migration = Migration.start(storage);
    await migration.takeInventory(hash);

    await migration.move('song/take.wav', 'song/Media/take.wav');
    await migration.move('song/member', 'song/from-member');
    await migration.move('song/from-member/m.rpp', 'song/m.rpp');
    expect(
      migration.locate('song/member/sub/x.wav'),
      'song/from-member/sub/x.wav',
    );
    expect(migration.locate('song/member/m.rpp'), 'song/m.rpp');
    await migration.keepOriginal('song/m.rpp');
    await migration.keepOriginal('song/m.rpp');
    await migration.keepOriginal('not/inventoried.rpp');
    put('song/m.rpp', 'rewritten, longer');
    put('song/added.json', '{}');

    final resumed = (await Migration.latest(storage))!;
    expect(resumed.locate('song/member/m.rpp'), 'song/m.rpp');
    hashed.clear();
    final progress = <double>[];
    expect(
      (await resumed.check(hash, onProgress: progress.add)).isEmpty,
      isTrue,
    );
    expect(progress.last, 1);
    expect(
      file('${migration.folder}/originals/song/member/m.rpp')
          .readAsStringSync(),
      'member',
    );
    // Only the copy, whose date differs, is hashed again.
    expect(hashed, ['${migration.folder}/originals/song/member/m.rpp']);
  });

  test('check reports missing and changed files', () async {
    put('a.wav', 'aaaa');
    put('b.wav', 'bbbb');
    put('c.wav', 'cccc');
    put('d.wav', 'dddd');
    put('e.wav', 'eeee');
    final migration = Migration.start(storage);
    await migration.takeInventory(hash);

    file('a.wav').deleteSync();
    put('b.wav', 'BBBB');
    file('b.wav').setLastModifiedSync(DateTime(2021));
    put('c.wav', 'cc');
    // Same content, new date: hashed again, not reported.
    file('d.wav').setLastModifiedSync(DateTime(2020));
    file('e.wav').deleteSync();
    Directory(file('e.wav').path).createSync();

    final report = await migration.check(hash);
    expect(report.hasErrors, isTrue);
    expect(
      report.items[ReportKind.fileLost],
      unorderedEquals([
        const ReportItem('a.wav', 'missing'),
        const ReportItem('b.wav', 'changed'),
        const ReportItem('c.wav', 'changed'),
        const ReportItem('e.wav', 'missing'),
      ]),
    );
    await expectLater(
      migration.check(
        hash,
        checkCancelled: () => throw const FormatException(),
      ),
      throwsFormatException,
    );
  });

  test('the scan ignores .migration', () async {
    put('.migration/s/originals/song/v.rpp', 'x');
    final result = await scan(
      storage,
      Library(
        id: LibraryId.generate(),
        mode: LibraryMode.local,
        layout: Layout([const LayoutLevel('title')]),
      ),
    );
    expect(result.titles, isEmpty);
    expect(result.toSort, isEmpty);
  });
}
