import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/state/providers.dart';
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
    File(
      '../../test/fixtures/project-1.rpp',
    ).copySync(p.join(song.path, 'v1.rpp'));
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
    expect(container.read(indexRevisionProvider), greaterThan(revision));
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
      layout: Layout.film(),
    );

    final entry = container.read(settingsProvider).libraries.single;
    expect((entry.id, entry.displayName), (library.id, 'Solo work'));
    expect((await readLibrary(MountedFolderStorage(solo)))!.isFreeTree, isTrue);
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
