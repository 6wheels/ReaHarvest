import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/logs.dart';
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'helpers.dart';

void main() {
  late Directory root;
  late ProviderContainer container;
  late LocalIndex index;
  late List<String> launched;

  LibraryService service() => container.read(libraryServiceProvider);

  String folder(String name) {
    final dir = Directory(p.join(root.path, name))..createSync();
    return dir.path;
  }

  setUp(() {
    launched = [];
    root = Directory.systemTemp.createTempSync('reaharvest_app_');
    index = LocalIndex.inMemory();
    container = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings(identity: const LocalIdentity(MemberId('M'), 'Alice')),
        ),
        settingsProvider.overrideWith(MemorySettings.new),
        localIndexProvider.overrideWithValue(index),
        defaultReaperResourcesProvider.overrideWithValue(
          p.join(root.path, 'resources'),
        ),
        detectedReaperProvider.overrideWith((ref) async => null),
        reaperLauncherProvider.overrideWithValue(
          (executable, file) async => launched.add(file),
        ),
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

    final navigation = container.read(navigationProvider.notifier);
    navigation.setFilter(TitleFilter(libraries: {id}));
    navigation.saveView('Band only');

    await service().remove(id);

    expect(container.read(settingsProvider).libraries, isEmpty);
    final filtered = container.read(navigationProvider);
    expect(filtered.filter.libraries, isEmpty);
    expect(filtered.savedViews.single.filter.libraries, isEmpty);
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

  test('manages the versions of a title', () async {
    final band = folder('Band');
    final song = Directory(p.join(band, 'Artist', 'Album', 'Song'))
      ..createSync(recursive: true);
    File('../../test/fixtures/project-1.rpp')
        .copySync(p.join(song.path, 'v1.rpp'));
    File(p.join(song.path, 'Media', 'unused.wav'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    await service().addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    Title title() => index.titles().single;
    Version version(String name) =>
        title().versions.firstWhere((v) => v.fileName == name);

    expect(
      await service().addVersion(title(), 'Song - a.RPP', ' a '),
      'Song - a.RPP',
    );
    final blank = version('Song - a.RPP').metadata!;
    expect((blank.owner, blank.label), (const MemberId('M'), 'a'));
    await service().addVersion(
      title(),
      'copy.RPP',
      'b',
      source: version('Song - a.RPP'),
    );
    final copy = version('copy.RPP').metadata!;
    expect(copy.id, isNot(blank.id));
    expect(copy.label, 'b');

    expect(
      await service().editVersion(
        title(),
        version('copy.RPP'),
        fileName: 'Song - c.RPP',
        label: 'c',
      ),
      'Song - c.RPP',
    );
    final edited = version('Song - c.RPP').metadata!;
    expect((edited.id, edited.label), (copy.id, 'c'));

    await service().setStatusOf(title(), version('Song - c.RPP'), 'mixing');
    expect(title().statusOf(version('Song - c.RPP')), 'mixing');

    await service().trashVersion(title(), version('Song - c.RPP'));
    expect(
      title().versions.map((v) => v.fileName),
      isNot(contains('Song - c.RPP')),
    );
    final trash = await container.read(trashProvider(title().id).future);
    expect(trash.map((e) => e.path), ['Artist/Album/Song/.trash/Song - c.RPP']);

    final unused = await service().purge(title(), [trash.single.path]);
    expect(
      File(p.join(song.path, '.trash', 'Song - c.RPP')).existsSync(),
      isFalse,
    );
    expect(unused.map((e) => e.path), ['Artist/Album/Song/Media/unused.wav']);
    await service().purgeUnusedMedia(title(), [unused.single.path]);
    expect(
      File(p.join(song.path, 'Media', 'unused.wav')).existsSync(),
      isFalse,
    );
  });

  test('deletes only node files of folders without project', () async {
    final band = folder('Band');
    final song = p.join(band, 'Artist', 'Album', 'Song');
    Directory(song).createSync(recursive: true);
    File('../../test/fixtures/project-1.rpp').copySync(p.join(song, 'v1.rpp'));
    final orphan = File(p.join(band, 'Artist', 'render', '.node.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"nodeId": "01X", "level": "album"}');
    await service().addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    final id = container.read(settingsProvider).libraries.single.id;
    expect(index.issues(kind: ReportKind.orphanNode), [
      (
        library: id,
        kind: ReportKind.orphanNode,
        item: const ReportItem('Artist/render/.node.json'),
      ),
    ]);

    await expectLater(
      service().deleteOrphanNode(id, 'Artist/Album/Song/.node.json'),
      throwsArgumentError,
    );
    await expectLater(
      service().deleteOrphanNode(id, 'Artist/Album/Song/v1.rpp'),
      throwsArgumentError,
    );
    await service().deleteOrphanNode(id, 'Artist/render/.node.json');

    expect(orphan.existsSync(), isFalse);
    expect(index.issues(kind: ReportKind.orphanNode), isEmpty);
    expect(File(p.join(song, '.node.json')).existsSync(), isTrue);
  });

  test('lists the project templates of a library', () async {
    final templates = Directory(
      p.join(root.path, 'resources', 'ProjectTemplates'),
    )..createSync(recursive: true);
    File(p.join(templates.path, 'band.RPP')).createSync();
    expect(
      await container.read(
        projectTemplatesProvider(LibraryId.generate()).future,
      ),
      [p.join(templates.path, 'band.RPP')],
    );
  });

  /// Library `Band` holding `Artist/Album/Song/v1.rpp` (not adopted).
  Future<String> bandWithSong() async {
    final band = folder('Band');
    final song = p.join(band, 'Artist', 'Album', 'Song');
    Directory(song).createSync(recursive: true);
    File('../../test/fixtures/project-1.rpp').copySync(p.join(song, 'v1.rpp'));
    await service().addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    return song;
  }

  Title title() => index.titles().single;
  Version version(String name) =>
      title().versions.firstWhere((v) => v.fileName == name);

  test('adopts versions and separates manual duplicates', () async {
    final song = await bandWithSong();
    expect(version('v1.rpp').isAdopted, isFalse);

    await service().adopt(title(), version('v1.rpp'), ' main ');
    final adopted = version('v1.rpp').metadata!;
    expect((adopted.owner, adopted.label), (const MemberId('M'), 'main'));

    File(p.join(song, 'v1.rpp')).copySync(p.join(song, 'dup.rpp'));
    await service().scanAll();
    expect(duplicateVersions(index.titles()).keys, [adopted.id]);

    await service().separateDuplicate(title(), version('dup.rpp'));
    final separated = version('dup.rpp').metadata!;
    expect(separated.id, isNot(adopted.id));
    expect(separated.label, 'main');
    expect(duplicateVersions(index.titles()), isEmpty);
  });

  test('declares members and adopts for one of them', () async {
    await bandWithSong();
    final entry = container.read(settingsProvider).libraries.single;
    expect(await service().membersOf(entry), isEmpty);
    const bob = Member(MemberId('B'), 'Bob');
    await service().setMembers(entry, const [bob]);
    expect(await service().membersOf(entry), const [bob]);
    expect(container.read(indexedLibrariesProvider).values.single.members, [
      bob,
    ]);

    await service().adopt(title(), version('v1.rpp'), '', owner: bob.id);
    expect(version('v1.rpp').metadata!.owner, bob.id);
  });

  test('backs up, restores and opens versions in REAPER', () async {
    final song = await bandWithSong();
    await service().adopt(title(), version('v1.rpp'), 'main');
    final id = version('v1.rpp').metadata!.id;
    Future<List<Backup>> backups() async =>
        (await container.read(historyProvider(title().id).future))[id] ?? [];

    await service().backup(title(), version('v1.rpp'));
    final saved = (await backups()).single;
    final project = File(p.join(song, 'v1.rpp'));
    await service().editVersion(
      title(),
      version('v1.rpp'),
      fileName: 'v1.rpp',
      label: 'changed',
    );

    await service().restore(title(), version('v1.rpp'), saved);
    expect(version('v1.rpp').metadata!.label, 'main');
    // The state before the restore is backed up first.
    expect(await backups(), hasLength(2));

    // REAPER not found.
    expect(await service().openVersion(title(), version('v1.rpp')), isFalse);
    expect(await service().openBackup(title(), saved), isFalse);
    expect(launched, isEmpty);

    await container
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(reaperExecutable: 'reaper.exe'));
    expect(await service().openVersion(title(), version('v1.rpp')), isTrue);
    expect(await service().openBackup(title(), saved), isTrue);
    expect(launched, [
      project.path,
      p.joinAll([
        p.dirname(p.dirname(p.dirname(song))),
        ...saved.path.split('/'),
      ]),
    ]);
  });

  test('moves a misplaced project into a title', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    File('../../test/fixtures/project-2.rpp')
        .copySync(p.join(band, 'Artist', 'loose.rpp'));
    await service().scanAll();
    final id = container.read(settingsProvider).libraries.single.id;

    final report = await service().moveToTitle(id, 'Artist/loose.rpp', [
      'Artist',
      'Album',
      'Loose',
    ]);

    final root = container.read(settingsProvider).libraries.single.libraryRoot;
    expect(container.read(tasksProvider).last.error, isNull);
    expect(report!.items[ReportKind.projectMoved], [
      ReportItem(p.join(root, 'Artist', 'Album', 'Loose', 'loose.rpp')),
    ]);
    expect(
      index.titles().map((t) => t.tags['title']),
      containsAll(['Song', 'Loose']),
    );
    final task = container.read(tasksProvider).last;
    expect(task.openReport, isTrue);
    expect(task.report, same(report));
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(task.label(l10n), 'Move of “loose.rpp”');

    // A failed move is reported; the inventory check still passes.
    final failed = await service().moveToTitle(id, 'Artist/gone.rpp', [
      'A',
      'B',
      'C',
    ]);
    expect(
      failed!.items[ReportKind.fixFailed]!.single.path,
      endsWith('gone.rpp'),
    );
    expect(failed.items[ReportKind.fileLost], isNull);
    expect(container.read(tasksProvider).last.state, TaskState.failed);
    // The inventory was taken once, before the first move.
    expect(Directory(p.join(root, '.migration')).listSync(), hasLength(1));
  });

  test('fixes misplaced folders and projects without losing a file', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    final member = Directory(p.join(song, 'Bob', 'mix'))
      ..createSync(recursive: true);
    File('../../test/fixtures/project-2.rpp')
        .copySync(p.join(member.path, 'take.rpp'));
    final old = Directory(p.join(band, 'Old'))..createSync();
    File('../../test/fixtures/project-1.rpp')
        .copySync(p.join(old.path, 'old.rpp'));
    // With known values, Old is recognized as a title placed too high.
    final entry = container.read(settingsProvider).libraries.single;
    await service().setKnownValues(entry, const [
      KnownValue('Artist', [
        KnownValue('Album'),
        KnownValue(Layout.unassigned),
      ]),
    ]);
    final id = entry.id;

    final report = await service().fix(id, const [
      LiftProject(
        'Artist/Album/Song/Bob/mix/take.rpp',
        'Artist/Album/Song',
        owner: MemberId('bob'),
        status: 'mixing',
      ),
      MoveFolder('Old', 'Artist/_Unassigned/Old'),
    ]);

    expect(report!.hasErrors, isFalse);
    expect(report.items[ReportKind.projectMoved], [
      ReportItem(p.join(song, 'take.rpp')),
    ]);
    expect(report.items[ReportKind.folderMoved], [
      ReportItem(p.join(band, 'Artist', '_Unassigned', 'Old')),
    ]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(container.read(tasksProvider).last.label(l10n), 'Fix 2 items');
    final lifted = index
        .titles()
        .firstWhere((t) => t.tags['title'] == 'Song')
        .versions
        .firstWhere((v) => v.fileName == 'take.rpp');
    expect(lifted.metadata!.owner, 'bob');
    expect(
      index.titles().map((t) => t.path),
      contains('Artist/_Unassigned/Old'),
    );
  });

  test('reports unreadable library files and survives failed scans', () async {
    final broken = folder('Broken');
    File(p.join(broken, libraryFileName)).writeAsStringSync('[]');
    await expectLater(
      service().existing(broken),
      throwsA(
        isA<LibraryException>()
            .having((e) => e.problem, 'problem', LibraryProblem.invalidFile)
            .having((e) => e.toString(), 'toString', contains('invalidFile')),
      ),
    );

    await container
        .read(settingsProvider.notifier)
        .change(
          (s) => s.addLibrary(
            LibraryEntry(
              id: LibraryId.generate(),
              displayName: 'Broken',
              workspaceRoot: broken,
            ),
          ),
        );
    await service().scanAll();
    expect(index.libraries(), isEmpty);
    final task = container.read(tasksProvider).single;
    expect(task.state, TaskState.failed);
    expect(task.openReport, isFalse);
    final failed = task.report!.items[ReportKind.scanFailed]!.single;
    expect(failed.path, broken);
    expect(failed.detail, isNotEmpty);

    // A rescan after a small action fails silently, without task.
    await service().scan(container.read(settingsProvider).libraries.single);
    expect(container.read(tasksProvider), [task]);
  });

  test('reports misplaced levels through the known values', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    final storage = MountedFolderStorage(band);
    final library = await readLibrary(storage);
    await writeLibrary(
      storage,
      library!.withKnownValues(const [
        KnownValue('Artist', [KnownValue('Album')]),
      ]),
    );
    Directory(p.join(band, 'Album')).createSync();
    File('../../test/fixtures/project-2.rpp')
        .copySync(p.join(band, 'Album', 'loose.rpp'));
    container.read(tasksProvider.notifier).clearFinished();

    await service().scanAll();
    final report = container.read(tasksProvider).single.report!;
    expect(report.items[ReportKind.misplacedLevel], [
      ReportItem.misplaced(
        p.join(band, 'Album'),
        level: const LayoutLevel('album'),
        target: 'Artist/Album',
      ),
    ]);
    expect(report.items.keys, isNot(contains(ReportKind.unknownValue)));
  });

  test('declares, edits and extends the known values', () async {
    final band = folder('Declared');
    final song = p.join(band, 'Artist', 'Album', 'Song');
    Directory(song).createSync(recursive: true);
    File('../../test/fixtures/project-1.rpp').copySync(p.join(song, 'v1.rpp'));
    expect(await service().hasProjects(band), isTrue);
    final prefilled = await service().prefillKnownValues(
      band,
      Layout.classic(),
    );
    expect(prefilled, const [
      KnownValue('Artist', [KnownValue('Album')]),
    ]);

    await service().addLocal(
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
    await service().setKnownValues(entry, values);
    expect((await readLibrary(storage))!.knownValues, values);
    expect(container.read(tasksProvider).last.openReport, isTrue);
    final known = await service().knownValuesOf(entry);
    expect(known.values, values);
    expect(known.used, {'Artist', 'Artist/Album'});

    // A title moved under a new artist adds it to the known values.
    File('../../test/fixtures/project-2.rpp')
        .copySync(p.join(band, 'loose.rpp'));
    await service().scanAll();
    await service().moveToTitle(entry.id, 'loose.rpp', ['Solo', 'Demo', 'X']);
    expect((await readLibrary(storage))!.knownValues, [
      ...values,
      const KnownValue('Solo', [KnownValue('Demo')]),
    ]);
    // Already known: unchanged.
    File('../../test/fixtures/project-2.rpp')
        .copySync(p.join(band, 'other.rpp'));
    await service().scanAll();
    await service().moveToTitle(entry.id, 'other.rpp', ['Solo', 'Demo', 'Y']);
    expect((await readLibrary(storage))!.knownValues, hasLength(2));

    // A library without known values keeps none, and one without
    // .library.json is left alone.
    await service().setKnownValues(
      LibraryEntry(
        id: LibraryId.generate(),
        displayName: 'None',
        workspaceRoot: folder('None'),
      ),
      values,
    );
    expect(await readLibrary(MountedFolderStorage(folder('None'))), isNull);
  });

  test('scans as background tasks', () async {
    await service().scanAll();
    expect(container.read(tasksProvider), isEmpty, reason: 'no library');

    await service().addLocal(
      folder: folder('Band'),
      displayName: 'Band',
      layout: null,
    );
    // A library whose .library.json is gone (unmounted drive) is skipped.
    final gone = folder('Gone');
    await container
        .read(settingsProvider.notifier)
        .change(
          (s) => s.addLibrary(
            LibraryEntry(
              id: LibraryId.generate(),
              displayName: 'Gone',
              workspaceRoot: gone,
            ),
          ),
        );
    await service().scanAll();
    final tasks = container.read(tasksProvider);
    expect([for (final t in tasks) t.state], [TaskState.done, TaskState.done]);
    expect([for (final t in tasks) t.openReport], [true, false]);
    expect(tasks.last.progress, 1);
    expect(tasks.first.report!.items[ReportKind.libraryScanned], [
      ReportItem(folder('Band')),
    ]);
    expect(tasks.last.report!.items[ReportKind.libraryUnavailable], [
      ReportItem(gone),
    ]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(tasks.first.label(l10n), 'Scan of “Band”');
    expect(tasks.last.label(l10n), 'Scan of the libraries');
  });

  group('REAPER providers', () {
    test('read the peaks preference of the resource folder', () async {
      final resources = Directory(p.join(root.path, 'resources'))..createSync();
      final ini = File(p.join(resources.path, 'REAPER.ini'))
        ..writeAsStringSync('[REAPER]\naltpeaks=1\naltpeakspath=P\n');
      expect(
        (await container.read(peaksPreferenceProvider.future))!.isRecommended,
        isTrue,
      );

      ini.writeAsBytesSync([0xff, 0xfe, 0xfd]);
      container.invalidate(peaksPreferenceProvider);
      expect(await container.read(peaksPreferenceProvider.future), isNull);

      final none = ProviderContainer(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            AppSettings(identity: const LocalIdentity(MemberId('M'), 'A')),
          ),
          defaultReaperResourcesProvider.overrideWithValue(null),
        ],
      );
      addTearDown(none.dispose);
      expect(await none.read(peaksPreferenceProvider.future), isNull);
    });

    test('default to this machine', () async {
      final machine = ProviderContainer();
      addTearDown(machine.dispose);
      final detected = await machine.read(detectedReaperProvider.future);
      if (detected != null) expect(File(detected).existsSync(), isTrue);
      expect(machine.read(defaultReaperResourcesProvider), isNotNull);
      expect(machine.read(reaperRunningProvider), isReaperRunning);
      expect(machine.read(reaperLauncherProvider), openInReaper);
    });
  });

  test('ports must be provided by main()', () {
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    expect(() => bare.read(settingsFileProvider), throwsA(anything));
    expect(() => bare.read(initialSettingsProvider), throwsA(anything));
    expect(() => bare.read(localIndexProvider), throwsA(anything));
    expect(() => bare.read(logFolderProvider), throwsA(anything));
    expect(bare.read(openFolderProvider), openFolder);
  });
}
