import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'helpers.dart';

void main() {
  late Directory root;
  late ProviderContainer container;
  late LocalIndex index;

  LibraryService service() => container.read(libraryServiceProvider);

  String folder(String name) {
    final dir = Directory(p.join(root.path, name))..createSync();
    return dir.path;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('reaharvest_app_');
    index = LocalIndex.inMemory();
    container = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings(identity: const LocalIdentity(MemberId('M'), 'Alice')),
        ),
        settingsProvider.overrideWith(MemorySettings.new),
        localIndexProvider.overrideWithValue(index),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    index.close();
    root.deleteSync(recursive: true);
  });

  test('creates a local library, then scans it into the index', () async {
    final band = folder('Band');
    final song = Directory(p.join(band, 'Artist', 'Album', 'Song'))
      ..createSync(recursive: true);
    File('../../test/fixtures/project-1.rpp')
        .copySync(p.join(song.path, 'v1.rpp'));
    final revision = container.read(indexRevisionProvider);

    await service().addLocal(
      folder: band,
      displayName: ' ',
      layout: Layout.classic(),
    );

    final entry = container.read(settingsProvider).libraries.single;
    expect(entry.displayName, 'Band');
    expect(entry.workspaceRoot, band);
    final library = (await readLibrary(MountedFolderStorage(band)))!;
    expect(library.id, entry.id);
    expect(library.mode, LibraryMode.local);
    expect(library.layout!.levels.map((l) => l.key), [
      'artist',
      'album',
      'title',
    ]);
    expect(index.titles().single.tags['title'], 'Song');
    // Frozen as soon as a title exists (SPEC §3.1).
    expect(await service().isLayoutLocked(band), isTrue);
    expect(container.read(indexRevisionProvider), greaterThan(revision));
  });

  test('a free tree feeds the filters and labels', () async {
    final songs = folder('Songs');
    final demo = Directory(p.join(songs, 'Demo'))..createSync();
    File('../../test/fixtures/project-1.rpp')
      ..copySync(p.join(songs, 'root.rpp'))
      ..copySync(p.join(demo.path, 'v1.rpp'));

    await service().addLocal(
      folder: songs,
      displayName: 'My songs',
      layout: null,
    );

    final options = container.read(filterOptionsProvider);
    expect(options.tags, isEmpty);
    final title = container.read(titlesProvider).single;
    // The root holds a project: one title, named after the library.
    expect(title.tags, {'title': 'My songs'});
    expect(titleName(title), 'My songs');
    expect(parentTags(title), isEmpty);
    expect(parentTags(index.titles().single), isEmpty);
  });

  test('attaches the library already described in the folder', () async {
    final solo = folder('Solo');
    final library = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: null,
    );
    await writeLibrary(MountedFolderStorage(solo), library);
    expect((await service().existing(solo))!.id, library.id);

    await service().addLocal(
      folder: solo,
      displayName: 'Solo work',
      layout: null,
    );

    final entry = container.read(settingsProvider).libraries.single;
    expect((entry.id, entry.displayName), (library.id, 'Solo work'));
    expect((await readLibrary(MountedFolderStorage(solo)))!.isFreeTree, isTrue);
  });

  test('re-adding a removed library can change its layout', () async {
    final band = folder('Band');
    await service().addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    final id = container.read(settingsProvider).libraries.single.id;
    await service().remove(id);

    await service().addLocal(
      folder: band,
      displayName: '',
      layout: Layout.film(),
    );

    final read = (await readLibrary(MountedFolderStorage(band)))!;
    expect(read.id, id);
    expect(read.layout!.leaf.key, 'scene');
    expect(container.read(settingsProvider).libraries.single.id, id);
  });

  test('a library holding titles keeps its layout', () async {
    final band = folder('Band');
    final song = Directory(p.join(band, 'Artist', 'Album', 'Song'))
      ..createSync(recursive: true);
    File('../../test/fixtures/project-1.rpp')
        .copySync(p.join(song.path, 'v1.rpp'));
    await service().addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    final id = container.read(settingsProvider).libraries.single.id;
    await service().remove(id);
    expect(await service().existing(band), isNotNull);
    expect(await service().isLayoutLocked(band), isTrue);

    await expectLater(
      service().addLocal(folder: band, displayName: '', layout: Layout.film()),
      throwsA(
        isA<LibraryException>().having(
          (e) => e.problem,
          'problem',
          LibraryProblem.layoutLocked,
        ),
      ),
    );
    expect(container.read(settingsProvider).libraries, isEmpty);

    await service().addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    expect(container.read(settingsProvider).libraries.single.id, id);
  });

  test('a free tree holding projects is locked too', () async {
    final solo = folder('Solo');
    final library = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: null,
    );
    await writeLibrary(MountedFolderStorage(solo), library);
    Directory(p.join(solo, 'Backups')).createSync();
    File(p.join(solo, 'Backups', 'old.rpp')).writeAsStringSync('');
    expect(await service().isLayoutLocked(solo), isFalse);

    File(p.join(solo, 'Demo.RPP')).writeAsStringSync('');
    expect(await service().isLayoutLocked(solo), isTrue);
  });

  test('rejects cloud libraries, overlaps and invalid files', () async {
    final shared = folder('Shared');
    await writeLibrary(
      MountedFolderStorage(shared),
      Library(
        id: LibraryId.generate(),
        mode: LibraryMode.cloud,
        layout: Layout.classic(),
      ),
    );
    final broken = folder('Broken');
    File(p.join(broken, libraryFileName)).writeAsStringSync('{"mode": 1}');
    final band = folder('Band');
    await service().addLocal(folder: band, displayName: '', layout: null);

    Future<LibraryProblem?> problem(String folder) async {
      try {
        await service().addLocal(folder: folder, displayName: '', layout: null);
        return null;
      } on LibraryException catch (e) {
        return e.problem;
      }
    }

    expect(await problem(shared), LibraryProblem.unsupportedMode);
    expect(await problem(broken), LibraryProblem.invalidFile);
    expect(await problem(folder('Band/Sub')), LibraryProblem.overlap);
    expect(File(p.join(band, 'Sub', libraryFileName)).existsSync(), isFalse);
    expect(container.read(settingsProvider).libraries, hasLength(1));
  });

  test('removal forgets the library and keeps its files', () async {
    final band = folder('Band');
    await service().addLocal(folder: band, displayName: '', layout: null);
    final id = container.read(settingsProvider).libraries.single.id;

    await service().remove(id);

    expect(container.read(settingsProvider).libraries, isEmpty);
    expect(index.libraries(), isEmpty);
    expect(File(p.join(band, libraryFileName)).existsSync(), isTrue);
  });

  test('scan skips unavailable libraries', () async {
    final settings = container.read(settingsProvider.notifier);
    await settings.change(
      (s) => s.addLibrary(
        LibraryEntry(
          id: LibraryId.generate(),
          displayName: 'Gone',
          workspaceRoot: p.join(root.path, 'missing'),
        ),
      ),
    );
    await service().scanAll();
    expect(index.libraries(), isEmpty);
  });
}
