import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:test/test.dart';

/// In-memory [RepositoryStorage] holding files only.
final class MemoryStorage implements RepositoryStorage {
  final files = <String, List<int>>{};

  @override
  Future<StorageEntry?> stat(String path) async {
    final data = files[path];
    if (data == null) return null;
    return StorageEntry(
      path: path,
      isDirectory: false,
      size: data.length,
      modified: DateTime(2026),
    );
  }

  @override
  Stream<List<int>> read(String path) => Stream.value(files[path]!);

  @override
  Future<void> write(String path, Stream<List<int>> content) async {
    files[path] = [await for (final chunk in content) ...chunk];
  }

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) =>
      throw UnimplementedError();

  @override
  Future<void> move(String from, String to) => throw UnimplementedError();

  @override
  Future<void> createDirectory(String path) => throw UnimplementedError();
}

void main() {
  group('_library.json', () {
    test('is absent from an empty root', () async {
      expect(await readLibrary(MemoryStorage()), isNull);
    });

    test('round-trips a collab library through storage', () async {
      final storage = MemoryStorage();
      final library = Library(
        id: LibraryId.generate(),
        mode: LibraryMode.collab,
        layout: LayoutTemplate.classic.create().freeze(),
        collab: CollabSettings(
          groupId: GroupId.generate(),
          store: CollabStoreKind.pocketbase,
          backendUrl: 'https://example.com',
        ),
      );
      await writeLibrary(storage, library);

      final json = jsonDecode(utf8.decode(storage.files[libraryFileName]!));
      expect(json['schemaVersion'], 1);
      expect(json['collab']['store'], 'pocketbase');

      final read = (await readLibrary(storage))!;
      expect(read.id, library.id);
      expect(read.mode, LibraryMode.collab);
      expect(read.layout!.frozen, isTrue);
      expect(read.layout!.levels.map((l) => l.key), [
        'artist',
        'album',
        'title',
      ]);
      expect(read.collab!.groupId, library.collab!.groupId);
      expect(read.collab!.backendUrl, 'https://example.com');
    });

    test('round-trips a custom layout and a free tree', () async {
      final storage = MemoryStorage();
      final custom = Layout(
        const [
          LayoutLevel('client'),
          LayoutLevel('spot', labels: {'en': 'Spot', 'fr': 'Annonce'}),
        ],
        renderMetadata: {'client': 'artist', 'spot': 'title'},
      );
      await writeLibrary(
        storage,
        Library(
          id: LibraryId.generate(),
          mode: LibraryMode.cloud,
          layout: custom,
        ),
      );
      final read = (await readLibrary(storage))!;
      expect(read.layout!.leaf.label('fr'), 'Annonce');
      expect(read.layout!.leaf.label('de'), 'Spot');
      expect(read.layout!.levels.first.label('fr'), 'client');
      expect(read.layout!.renderMetadata, {
        'client': 'artist',
        'spot': 'title',
      });

      await writeLibrary(
        storage,
        Library(
          id: LibraryId.generate(),
          mode: LibraryMode.local,
          layout: null,
        ),
      );
      expect((await readLibrary(storage))!.isFreeTree, isTrue);
    });

    test('provides the templates, classic recommended', () {
      expect(LayoutTemplate.recommended, LayoutTemplate.classic);
      expect(LayoutTemplate.projectOriented.create().levels.length, 2);
      expect(LayoutTemplate.film.create().leaf.key, 'scene');
    });
  });

  group('settings', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reaharvest_settings');
      path = p.join(dir.path, 'nested', 'settings.json');
    });

    tearDown(() => dir.delete(recursive: true));

    test('creates a local identity on first launch, then keeps it', () async {
      final first = await SettingsFile(path).load();
      expect(isUlid(first.identity.memberId), isTrue);
      expect(first.identity.displayName, isNotEmpty);
      expect(first.libraries, isEmpty);
      expect(File(path).existsSync(), isTrue);

      final again = await SettingsFile(path).load();
      expect(again.identity.memberId, first.identity.memberId);
    });

    test('round-trips libraries and paths', () async {
      final file = SettingsFile(path);
      final settings = (await file.load())
          .copyWith(
            identity: const LocalIdentity(MemberId('M'), 'Alice'),
            reaperExecutable: '/opt/reaper/reaper',
            reaperResources: '/home/alice/.config/REAPER',
            templatesFolder: '/templates',
            theme: ThemePreference.dark,
            textScale: 1.2,
            language: 'fr',
          )
          .addLibrary(
            const LibraryEntry(
              id: LibraryId('L1'),
              displayName: 'Band',
              workspaceRoot: '/work/band',
              repositoryRoot: '/drive/band',
              templatesFolder: '/work/band-templates',
            ),
          )
          .addLibrary(
            const LibraryEntry(
              id: LibraryId('L2'),
              displayName: 'Solo',
              workspaceRoot: '/work/solo',
            ),
          );
      await file.save(settings);

      final read = await file.load();
      expect(read.identity.displayName, 'Alice');
      expect(read.reaperExecutable, '/opt/reaper/reaper');
      expect(read.reaperResources, '/home/alice/.config/REAPER');
      expect(read.templatesFolder, '/templates');
      expect(
        (read.theme, read.textScale, read.language),
        (ThemePreference.dark, 1.2, 'fr'),
      );
      expect(read.libraries.map((l) => l.id), ['L1', 'L2']);
      expect(read.libraries[0].libraryRoot, '/drive/band');
      expect(read.libraries[0].templatesFolder, '/work/band-templates');
      expect(read.libraries[1].libraryRoot, '/work/solo');
      expect(read.libraries[1].repositoryRoot, isNull);

      expect(
        read.removeLibrary(const LibraryId('L1')).libraries.single.id,
        'L2',
      );

      final kept = read.copyWith(theme: ThemePreference.light);
      expect(kept.reaperExecutable, '/opt/reaper/reaper');
      final reset = read.copyWith(reaperExecutable: null, templatesFolder: null);
      expect(reset.reaperExecutable, isNull);
      expect(reset.templatesFolder, isNull);
      expect(reset.reaperResources, '/home/alice/.config/REAPER');
    });

    test('rejects an unsupported schema', () {
      expect(
        () => AppSettings.fromJson({'schemaVersion': 2}),
        throwsFormatException,
      );
    });

    test('a folder belongs to one library only', () {
      final settings =
          AppSettings(identity: const LocalIdentity(MemberId('M'), 'Alice'))
              .addLibrary(
                LibraryEntry(
                  id: const LibraryId('L1'),
                  displayName: 'Band',
                  workspaceRoot: p.join('work', 'band'),
                  repositoryRoot: p.join('drive', 'band'),
                ),
              );
      LibraryEntry entry(String workspace, [String? repository]) =>
          LibraryEntry(
            id: const LibraryId('L2'),
            displayName: 'Other',
            workspaceRoot: workspace,
            repositoryRoot: repository,
          );

      for (final bad in [
        entry(p.join('work', 'band')),
        entry(p.join('work', 'band', 'sub')),
        entry('work'),
        entry(p.join('work', 'other'), p.join('drive', 'band', 'x')),
      ]) {
        expect(() => settings.addLibrary(bad), throwsArgumentError);
      }
      expect(
        () => settings.addLibrary(
          LibraryEntry(
            id: const LibraryId('L1'),
            displayName: 'Dup',
            workspaceRoot: p.join('elsewhere'),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        settings
            .addLibrary(entry(p.join('work', 'band2'), p.join('drive', 'b2')))
            .libraries
            .length,
        2,
      );
    });
  });
}
