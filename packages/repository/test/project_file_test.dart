import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

const _fixture = '../../test/fixtures/windows-1252.rpp';
const _title = 'band/album/song';

bool _isUtf8(List<int> bytes) {
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

void main() {
  late Directory root;
  late MountedFolderStorage storage;

  File file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  void putBytes(String path, List<int> bytes) {
    final f = file(path);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  /// The Windows-1252 fixture with an item referencing [ref].
  List<int> fixtureWithItem(String ref) {
    final text = latin1.decode(File(_fixture).readAsBytesSync());
    final item = '<ITEM\n  <SOURCE WAVE\n    FILE "$ref"\n  >\n>\n';
    return latin1.encode(
      text.replaceFirst('  <EXTENSIONS', '$item  <EXTENSIONS'),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('reaharvest_encoding_');
    storage = MountedFolderStorage(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('round trip of every byte value from 80 to FF', () async {
    final bytes = [for (var b = 0x80; b <= 0xFF; b++) b];
    putBytes('a.rpp', bytes);

    final read = await readProject(storage, 'a.rpp');
    await writeProject(storage, 'b.rpp', read.text, read.encoding);

    expect(read.encoding, ProjectEncoding.windows1252);
    expect(read.text.codeUnitAt(0x81 - 0x80), 0x81);
    expect(file('b.rpp').readAsBytesSync(), bytes);
  });

  test('reads valid UTF-8 as UTF-8 and writes it back unchanged', () async {
    final bytes = utf8.encode('Café 日\n');
    putBytes('a.rpp', bytes);

    final read = await readProject(storage, 'a.rpp');
    await writeProject(storage, 'b.rpp', read.text, read.encoding);

    expect(read.encoding, ProjectEncoding.utf8);
    expect(read.text, 'Café 日\n');
    expect(file('b.rpp').readAsBytesSync(), bytes);
  });

  test('refuses a character Windows-1252 cannot write, writing nothing', () {
    expect(
      writeProject(storage, 'a.rpp', '日', ProjectEncoding.windows1252),
      throwsA(isA<ProjectEncodingException>()),
    );
    expect(file('a.rpp').existsSync(), isFalse);
  });

  test('reads the Windows-1252 fixture, adopts it byte for byte', () async {
    final original = File(_fixture).readAsBytesSync();
    putBytes('$_title/a.rpp', original);

    final read = await readProject(storage, '$_title/a.rpp');
    await writeVersionId(storage, '$_title/a.rpp', VersionId.generate());

    expect(read.encoding, ProjectEncoding.windows1252);
    expect(read.text, contains('NAME "Café tête"'));
    final after = file('$_title/a.rpp').readAsBytesSync();
    expect(_isUtf8(after), isFalse);
    // Every original line is still there, unchanged and in order.
    final before = latin1.decode(original).split('\n');
    final added = latin1.decode(after).split('\n');
    var i = 0;
    final extra = <String>[];
    for (final line in added) {
      if (i < before.length && line == before[i]) {
        i++;
      } else {
        extra.add(line);
      }
    }
    expect(i, before.length);
    expect(extra.join('\n'), contains('EXTSTATE'));
  });

  test('the scan indexes a Windows-1252 project and finds its media', () async {
    putBytes('$_title/a.rpp', fixtureWithItem(r'audio-files\Café.wav'));
    file('$_title/audio-files/Café.wav')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('wav');

    final result = await scan(
      storage,
      Library(
        id: LibraryId.generate(),
        mode: LibraryMode.local,
        layout: Layout.classic(),
      ),
    );

    final version = result.titles.single.versions.single;
    expect(version.media, [r'audio-files\Café.wav']);
    expect(result.issues.items[ReportKind.missingMedia], isNull);
    expect(result.issues.items[ReportKind.mediaOutsidePool], isNotNull);
  });

  group('with a Windows-1252 project', () {
    Future<Migration> migration() async {
      final m = Migration.start(storage);
      await m.inventory.take(
        (path) async => base64.encode(
          Uint8List.fromList(
            await storage.read(path).expand((c) => c).toList(),
          ),
        ),
      );
      return m;
    }

    setUp(() {
      putBytes('$_title/a.rpp', fixtureWithItem(r'audio-files\Café.wav'));
      file('$_title/audio-files/Café.wav')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('wav');
    });

    test('the normalization rewrites the reference in Windows-1252', () async {
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(_title)]);

      expect(report.hasErrors, isFalse);
      expect(file('$_title/Media/Café.wav').existsSync(), isTrue);
      final after = file('$_title/a.rpp').readAsBytesSync();
      expect(_isUtf8(after), isFalse);
      final text = latin1.decode(after);
      expect(text, contains(r'FILE "Media\Café.wav"'));
      expect(text, contains('NAME "Café tête"'));
    });

    test(
      'a name Windows-1252 cannot hold leaves the project as it is',
      () async {
        final original = File(_fixture).readAsBytesSync();
        putBytes('$_title/日/a.rpp', original);
        await scaffoldTitle(storage, _title, 'title');

        await expectLater(
          liftProject(
            storage,
            '$_title/日/a.rpp',
            _title,
            owner: const MemberId('alice'),
          ),
          throwsA(isA<ProjectEncodingException>()),
        );

        // The title already holds an a.rpp: the lifted one takes a free name.
        expect(file('$_title/a (2).rpp').readAsBytesSync(), original);
      },
    );

    test('backup and restore keep the encoding', () async {
      final when = DateTime(2026, 11, 7, 15, 30, 12);

      final backup = await backupVersion(storage, _title, 'a.rpp', now: when);
      expect(_isUtf8(file(backup).readAsBytesSync()), isFalse);
      expect(
        latin1.decode(file(backup).readAsBytesSync()),
        contains('NAME "Café tête"'),
      );

      await restoreBackup(storage, _title, 'a.rpp', backup, now: when);
      final restored = file('$_title/a.rpp').readAsBytesSync();
      expect(_isUtf8(restored), isFalse);
      expect(latin1.decode(restored), contains('NAME "Café tête"'));
    });
  });
}
