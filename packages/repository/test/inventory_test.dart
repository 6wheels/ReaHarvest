import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const folder = '.migration/s';
const file = '$folder/${Inventory.fileName}';

void main() {
  late MemoryStorage storage;
  late List<String> hashed;

  /// Test hasher: the content itself, recording the paths hashed.
  Future<String> hash(String path) async {
    hashed.add(path);
    return storage.text(path);
  }

  List<Map<String, dynamic>> lines() => [
    for (final l in const LineSplitter().convert(storage.text(file)))
      jsonDecode(l) as Map<String, dynamic>,
  ];

  setUp(() {
    storage = MemoryStorage();
    hashed = [];
  });

  test('covers every file outside .migration, one line each', () async {
    storage
      ..put('.library.json', '{}')
      ..put('a/v.rpp', 'project')
      ..put('a/Media/x.wav', 'audio')
      ..put('.collab/m/member.json', '{}')
      ..put('.migration/old/inventory.json', '{}')
      ..put('a/w.rpp${MountedFolderStorage.tempSuffix}', 'tmp');
    final progress = <double>[];

    final inventory = Inventory(storage, folder);
    expect(inventory.isComplete, isFalse);
    expect(await Inventory.read(storage, folder), isNull);
    await inventory.take(hash, onProgress: progress.add);

    expect(inventory.isComplete, isTrue);
    expect(
      inventory.files.keys,
      unorderedEquals(['a/v.rpp', 'a/Media/x.wav', '.collab/m/member.json']),
    );
    expect(inventory.files['a/v.rpp']!.hash, 'project');
    expect(inventory.files['a/v.rpp']!.size, 7);
    expect(progress.last, 1);
    final saved = lines();
    expect(saved, hasLength(4));
    expect(saved.first.keys, ['path', 'size', 'modified', 'hash']);
    expect(saved.last, {'complete': true, 'files': 3});
    expect(storage.text(file), endsWith('\n'));
    await expectLater(inventory.take(hash), throwsStateError);

    final read = (await Inventory.read(storage, folder))!;
    expect(read.isComplete, isTrue);
    expect(read.files, inventory.files);
  });

  test('an empty library gives a complete, empty inventory', () async {
    final inventory = Inventory(storage, folder);
    await inventory.take(hash);
    expect(lines(), [
      {'complete': true, 'files': 0},
    ]);
  });

  test('a cancelled inventory resumes from the lines written', () async {
    for (var i = 0; i < 6; i++) {
      storage.put('t/f$i.wav', 'f$i');
    }
    var calls = 0;
    void stopAt4() {
      if (++calls > 4) throw const FormatException('cancelled');
    }

    await expectLater(
      Inventory(storage, folder).take(hash, checkCancelled: stopAt4),
      throwsFormatException,
    );
    expect(hashed, hasLength(4));

    storage
      ..put('t/new.wav', 'new')
      ..files.remove('t/f0.wav');
    final resumed = (await Inventory.read(storage, folder))!;
    expect(resumed.isComplete, isFalse);
    expect(resumed.files, hasLength(4));
    hashed.clear();
    await resumed.take(hash);

    expect(hashed, hasLength(3));
    expect(hashed, contains('t/new.wav'));
    expect(resumed.files, hasLength(6));
    expect(resumed.files.containsKey('t/f0.wav'), isFalse);
    // A file gone before the inventory was complete is marked removed.
    expect(lines(), anyElement(equals({'path': 't/f0.wav', 'removed': true})));
    final read = (await Inventory.read(storage, folder))!;
    expect(read.files, resumed.files);
    expect(read.isComplete, isTrue);
  });

  test(
    'a file changed before the end is hashed again, last line wins',
    () async {
      storage
        ..put('a.wav', 'aaaa')
        ..put('b.wav', 'b');
      var calls = 0;
      await expectLater(
        Inventory(storage, folder).take(
          hash,
          checkCancelled: () {
            if (++calls > 1) throw const FormatException('cancelled');
          },
        ),
        throwsFormatException,
      );
      expect(hashed, ['a.wav']);
      storage.put('a.wav', 'AA');
      await (await Inventory.read(storage, folder))!.take(hash);

      final read = (await Inventory.read(storage, folder))!;
      expect(read.files['a.wav']!.hash, 'AA');
      expect(lines().where((l) => l['path'] == 'a.wav'), hasLength(2));
    },
  );

  test('resumes after an interruption at every line', () async {
    for (var i = 0; i < 5; i++) {
      storage.put('d/f$i.wav', 'content $i');
    }
    await Inventory(storage, folder).take(hash);
    final full = storage.text(file);
    final expected = (await Inventory.read(storage, folder))!.files;
    final cuts = [
      for (var i = 0; i < full.length; i++)
        if (full[i] == '\n') i + 1,
    ];

    for (final end in [0, ...cuts]) {
      // Cut after a line, and in the middle of the next one.
      for (final extra in [0, 7]) {
        final at = (end + extra).clamp(0, full.length);
        storage.put(file, full.substring(0, at));
        final resumed = (await Inventory.read(storage, folder))!;
        if (!resumed.isComplete) await resumed.take(hash);
        final read = (await Inventory.read(storage, folder))!;
        expect(read.isComplete, isTrue, reason: 'cut at $at');
        expect(read.files, expected, reason: 'cut at $at');
      }
    }
  });

  test('a line cut by a crash never becomes valid', () async {
    storage
      ..put('a.wav', 'a')
      ..put('b.wav', 'b');
    // A crash right before the end of line of a complete JSON object.
    storage.put(
      file,
      '{"path":"a.wav","size":1,"modified":0,"hash":"x"}\n'
      '{"path":"b.wav","size":1,"modified":0,"hash":"y"}',
    );
    final resumed = (await Inventory.read(storage, folder))!;
    expect(resumed.files.keys, ['a.wav']);
    await resumed.take(hash);

    final read = (await Inventory.read(storage, folder))!;
    expect(read.files['b.wav']!.hash, 'b');
    expect(read.isComplete, isTrue);
  });

  test('a write failure leaves a resumable inventory', () async {
    for (var i = 0; i < 3; i++) {
      storage.put('f$i.wav', '$i');
    }
    // 1: the reused lines (none), 2 and 3: two files; the third fails.
    storage.failAt = 4;
    await expectLater(
      Inventory(storage, folder).take(hash),
      throwsA(isA<InjectedFailure>()),
    );
    storage.failAt = null;
    final resumed = (await Inventory.read(storage, folder))!;
    expect(resumed.files, hasLength(2));
    await resumed.take(hash);
    expect(resumed.files, hasLength(3));
  });

  test('reuses the given hashes for unchanged files', () async {
    storage
      ..put('a.wav', 'aaaa', modified: DateTime(2020))
      ..put('b.wav', 'BB', modified: DateTime(2021));
    final inventory = Inventory(
      storage,
      folder,
      reuse: {
        'a.wav': (size: 4, modified: DateTime(2020), hash: 'old a'),
        'b.wav': (size: 4, modified: DateTime(2020), hash: 'old b'),
      },
    );
    await inventory.take(hash);

    expect(hashed, ['b.wav']);
    expect(inventory.files['a.wav']!.hash, 'old a');
    // Written as a line: read without the previous inventory.
    expect(
      (await Inventory.read(storage, folder))!.files['a.wav']!.hash,
      'old a',
    );
  });

  group('check', () {
    test('requires a complete inventory', () async {
      await expectLater(
        Inventory(storage, folder).check(hash, locate: (p) => p),
        throwsStateError,
      );
    });

    test('follows moves and kept originals', () async {
      storage
        ..put('song/v.rpp', 'project')
        ..put('song/take.wav', 'audio');
      final inventory = Inventory(storage, folder);
      await inventory.take(hash);
      await storage.move('song/take.wav', 'song/Media/take.wav');
      storage
        ..put(inventory.originalPath('song/v.rpp'), 'project')
        ..put('song/v.rpp', 'rewritten, longer');
      hashed.clear();
      final progress = <double>[];

      final report = await inventory.check(
        hash,
        locate: (p) => p == 'song/take.wav' ? 'song/Media/take.wav' : p,
        onProgress: progress.add,
      );

      expect(report.isEmpty, isTrue);
      expect(progress.last, 1);
      // Only the copy, whose date differs, is hashed again.
      expect(hashed, ['$folder/originals/song/v.rpp']);
    });

    test('reports missing and changed files', () async {
      for (final name in ['a', 'b', 'c', 'd', 'e']) {
        storage.put('$name.wav', name * 4, modified: DateTime(2019));
      }
      final inventory = Inventory(storage, folder);
      await inventory.take(hash);

      storage
        ..files.remove('a.wav')
        ..put('b.wav', 'BBBB', modified: DateTime(2021))
        ..put('c.wav', 'cc')
        // Same content, new date: hashed again, not reported.
        ..put('d.wav', 'dddd', modified: DateTime(2020))
        ..files.remove('e.wav')
        ..dirs.add('e.wav');

      final report = await inventory.check(hash, locate: (p) => p);
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
        inventory.check(
          hash,
          locate: (p) => p,
          checkCancelled: () => throw const FormatException(),
        ),
        throwsFormatException,
      );
    });
  });
}
