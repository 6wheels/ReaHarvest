import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:test/test.dart';

import '../make_library.dart';

/// Files below [dir] with their relative path and content; the modification
/// dates are not part of the library.
Map<String, String> tree(String dir) => {
  for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
    p.relative(f.path, from: dir): base64.encode(f.readAsBytesSync()),
};

void main() {
  late Directory temp;
  final fixtures = findFixtures();

  setUp(() => temp = Directory.systemTemp.createTempSync('perf_library_'));
  tearDown(() => temp.deleteSync(recursive: true));

  String path(String name) => p.join(temp.path, name);

  test('builds 1,000 projects with their media, the same each time', () async {
    await makeLibrary(path('a'), path('a-data'), fixtures: fixtures);
    final files = Directory(path('a'))
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    final projects = files.where((f) => f.path.endsWith('.RPP')).toList();
    expect(projects, hasLength(1000));
    expect(
      p.relative(projects.first.path, from: path('a')).split(p.separator),
      hasLength(5),
    );
    final media = files.where((f) => p.basename(p.dirname(f.path)) == 'Media');
    expect(media, isNotEmpty);
    expect(media.every((f) => f.lengthSync() == 1024), isTrue);

    await makeLibrary(path('b'), path('b-data'), fixtures: fixtures);
    expect(tree(path('b')), tree(path('a')));
  });

  test(
    'titles are patched, the index is up to date, tray is an option',
    () async {
      await makeLibrary(
        path('a'),
        path('a-data'),
        fixtures: fixtures,
        tray: true,
      );
      final project = File(
        p.join(path('a'), 'Artist 1', 'Album 1', 'Title 0001', 'v1', 'v1.RPP'),
      );
      expect(project.readAsStringSync(), contains('TITLE "Title 0001"'));

      final settings = await SettingsFile(
        p.join(path('a-data'), 'settings.json'),
      ).load();
      expect(settings.showInTray, isTrue);
      expect(settings.libraries.single.workspaceRoot, path('a'));
      final index = LocalIndex.open(
        p.join(path('a-data'), 'index.sqlite'),
        readOnly: true,
      );
      addTearDown(index.close);
      expect(index.titles(), hasLength(1000));

      await makeLibrary(
        path('b'),
        path('b-data'),
        fixtures: fixtures,
        indexed: false,
      );
      expect(
        File(p.join(path('b-data'), 'index.sqlite')).existsSync(),
        isFalse,
      );
      final plain = await SettingsFile(p.join(path('b-data'), 'settings.json'))
          .load();
      expect(plain.showInTray, isFalse);
    },
  );

  test('rebuilds its own folder only', () async {
    for (var i = 0; i < 2; i++) {
      await makeLibrary(
        path('a'),
        path('a-data'),
        fixtures: fixtures,
        indexed: false,
      );
    }
    Directory(path('other')).createSync();
    File(p.join(path('other'), 'mine.txt')).writeAsStringSync('keep');
    await expectLater(
      makeLibrary(path('other'), path('other-data'), fixtures: fixtures),
      throwsStateError,
    );
    expect(File(p.join(path('other'), 'mine.txt')).existsSync(), isTrue);
  });
}
