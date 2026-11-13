import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/state/library_catalog.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_env.dart';

void main() {
  setUpLibraryEnv();

  test('creates a local library, then scans it into the index', () async {
    final band = folder('Band');
    final song = Directory(p.join(band, 'Artist', 'Album', 'Song'))
      ..createSync(recursive: true);
    File('../../test/fixtures/tracks.rpp')
        .copySync(p.join(song.path, 'v1.rpp'));
    final revision = container.read(indexRevisionProvider);

    await catalog.addLocal(
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
    expect(await catalog.hasProjects(band), isTrue);
    expect(container.read(indexRevisionProvider), greaterThan(revision));
  });

  test('a free tree feeds the filters and labels', () async {
    final songs = folder('Songs');
    final demo = Directory(p.join(songs, 'Demo'))..createSync();
    File('../../test/fixtures/tracks.rpp')
      ..copySync(p.join(songs, 'root.rpp'))
      ..copySync(p.join(demo.path, 'v1.rpp'));

    await catalog.addLocal(
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
    expect((await catalog.existing(solo))!.id, library.id);

    await catalog.addLocal(
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
    await catalog.addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    final id = container.read(settingsProvider).libraries.single.id;
    await catalog.remove(id);

    await catalog.addLocal(
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
    File('../../test/fixtures/tracks.rpp')
        .copySync(p.join(song.path, 'v1.rpp'));
    await catalog.addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    final id = container.read(settingsProvider).libraries.single.id;
    await catalog.remove(id);
    expect(await catalog.existing(band), isNotNull);
    expect(await catalog.hasProjects(band), isTrue);

    await expectLater(
      catalog.addLocal(folder: band, displayName: '', layout: Layout.film()),
      throwsA(
        isA<LibraryException>().having(
          (e) => e.problem,
          'problem',
          LibraryProblem.layoutLocked,
        ),
      ),
    );
    expect(container.read(settingsProvider).libraries, isEmpty);

    await catalog.addLocal(
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
    expect(await catalog.hasProjects(solo), isFalse);

    File(p.join(solo, 'Demo.RPP')).writeAsStringSync('');
    expect(await catalog.hasProjects(solo), isTrue);
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
    await catalog.addLocal(folder: band, displayName: '', layout: null);

    Future<LibraryProblem?> problem(String folder) async {
      try {
        await catalog.addLocal(folder: folder, displayName: '', layout: null);
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
    await catalog.addLocal(folder: band, displayName: '', layout: null);
    final id = container.read(settingsProvider).libraries.single.id;

    final navigation = container.read(navigationProvider.notifier);
    navigation.setFilter(TitleFilter(libraries: {id}));
    navigation.saveView('Band only');

    await catalog.remove(id);

    expect(container.read(settingsProvider).libraries, isEmpty);
    final filtered = container.read(navigationProvider);
    expect(filtered.filter.libraries, isEmpty);
    expect(filtered.savedViews.single.filter.libraries, isEmpty);
    expect(index.libraries(), isEmpty);
    expect(File(p.join(band, libraryFileName)).existsSync(), isTrue);
  });

  test('declares members and adopts for one of them', () async {
    await bandWithSong();
    final entry = container.read(settingsProvider).libraries.single;
    expect(await catalog.membersOf(entry), isEmpty);
    const bob = Member(MemberId('B'), 'Bob');
    await catalog.setMembers(entry, const [bob]);
    expect(await catalog.membersOf(entry), const [bob]);
    expect(container.read(indexedLibrariesProvider).values.single.members, [
      bob,
    ]);

    await versions.adopt(title(), version('v1.rpp'), '', owner: bob.id);
    expect(version('v1.rpp').metadata!.owner, bob.id);
  });

  test('declares, edits and extends the known values', () async {
    final band = folder('Declared');
    final song = p.join(band, 'Artist', 'Album', 'Song');
    Directory(song).createSync(recursive: true);
    File('../../test/fixtures/tracks.rpp').copySync(p.join(song, 'v1.rpp'));
    expect(await catalog.hasProjects(band), isTrue);
    final prefilled = await catalog.prefillKnownValues(band, Layout.classic());
    expect(prefilled, const [
      KnownValue('Artist', [KnownValue('Album')]),
    ]);

    await catalog.addLocal(
      folder: band,
      displayName: 'Declared',
      layout: Layout.classic(),
      knownValues: prefilled,
    );
    final storage = MountedFolderStorage(band);
    expect((await readLibrary(storage))!.knownValues, prefilled);
    final entry = container.read(settingsProvider).libraries.single;

    final values = const [
      KnownValue('Artist', [KnownValue('Album'), KnownValue('Live')]),
    ];
    await catalog.setKnownValues(entry, values);
    expect((await readLibrary(storage))!.knownValues, values);
    expect(container.read(tasksProvider).last.openReport, isTrue);
    final known = await catalog.knownValuesOf(entry);
    expect(known.values, values);
    expect(known.used, {'Artist', 'Artist/Album'});

    // A title moved under a new artist adds it to the known values.
    File('../../test/fixtures/render-file.rpp')
        .copySync(p.join(band, 'loose.rpp'));
    await scans.scanAll();
    await migration.moveToTitle(entry.id, 'loose.rpp', ['Solo', 'Demo', 'X']);
    expect((await readLibrary(storage))!.knownValues, [
      ...values,
      const KnownValue('Solo', [KnownValue('Demo')]),
    ]);
    // Already known: unchanged.
    File('../../test/fixtures/render-file.rpp')
        .copySync(p.join(band, 'other.rpp'));
    await scans.scanAll();
    await migration.moveToTitle(entry.id, 'other.rpp', ['Solo', 'Demo', 'Y']);
    expect((await readLibrary(storage))!.knownValues, hasLength(2));

    // A library without known values keeps none, and one without
    // .library.json is left alone.
    await catalog.setKnownValues(
      LibraryEntry(
        id: LibraryId.generate(),
        displayName: 'None',
        workspaceRoot: folder('None'),
      ),
      values,
    );
    expect(await readLibrary(MountedFolderStorage(folder('None'))), isNull);
  });
}
