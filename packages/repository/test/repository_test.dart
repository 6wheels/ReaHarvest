import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_repository/src/windows_hidden.dart' as windows;
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

const fixtures = '../../test/fixtures';

/// Storage recording the paths read.
final class CountingStorage implements RepositoryStorage {
  CountingStorage(this.inner);

  final RepositoryStorage inner;
  final reads = <String>[];

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) =>
      inner.list(dir, recursive: recursive);

  @override
  Future<StorageEntry?> stat(String path) => inner.stat(path);

  @override
  Stream<List<int>> read(String path) {
    reads.add(path);
    return inner.read(path);
  }

  @override
  Future<void> write(String path, Stream<List<int>> content) =>
      inner.write(path, content);

  @override
  Future<void> move(String from, String to) => inner.move(from, to);

  @override
  Future<void> createDirectory(String path) => inner.createDirectory(path);

  @override
  Future<void> delete(String path) => inner.delete(path);
}

void main() {
  late Directory root;
  late MountedFolderStorage storage;

  final unknown = File('$fixtures/project-1.rpp').readAsStringSync();
  final adopted = setExtState(
    unknown,
    VersionMetadata.section,
    VersionMetadata(
      id: VersionId.generate(),
      owner: MemberId.generate(),
      label: 'chorus B',
    ).toExtState(),
  );

  void put(String path, [String content = '']) {
    final f = File(p.joinAll([root.path, ...path.split('/')]));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  bool exists(String path) =>
      File(p.joinAll([root.path, ...path.split('/')])).existsSync();

  Library library(Layout? layout) => Library(
    id: LibraryId.generate(),
    mode: LibraryMode.local,
    layout: layout,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('reaharvest_repo_');
    storage = MountedFolderStorage(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('MountedFolderStorage', () {
    test('writes atomically, lists with / paths and moves', () async {
      await storage.write('a/b/c.txt', Stream.value(utf8.encode('hi')));
      final entries = await storage.list('', recursive: true);
      expect(
        entries.map((e) => e.path),
        containsAll(['a', 'a/b', 'a/b/c.txt']),
      );
      expect((await storage.stat('a/b/c.txt'))!.size, 2);
      expect(await storage.stat('missing'), isNull);
      await storage.move('a/b/c.txt', 'a/.trash/c.txt');
      expect(exists('a/.trash/c.txt'), isTrue);
      expect(exists('a/b/c.txt'), isFalse);
      await storage.write('a/b/c.txt', Stream.value(utf8.encode('x')));
      expect(
        () => storage.move('a/b/c.txt', 'a/.trash/c.txt'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test(
      'hides dot-prefixed files and folders on Windows (SPEC §3.2)',
      () async {
        bool hidden(String path) => windows.isHidden(p.join(root.path, path));

        await storage.write('.library.json', Stream.value(utf8.encode('{}')));
        await storage.write('a/.node.json', Stream.value(utf8.encode('{}')));
        // Rewriting replaces the file: it must stay hidden.
        await storage.write('a/.node.json', Stream.value(utf8.encode('{ }')));
        await storage.createDirectory('.collab/m1');
        await storage.write('a/b.rpp', Stream.value(utf8.encode('')));
        await storage.move('a/b.rpp', 'a/.trash/b.rpp');

        expect(hidden('.library.json'), isTrue);
        expect(hidden('a/.node.json'), isTrue);
        expect(hidden('.collab'), isTrue);
        expect(hidden('a/.trash'), isTrue);
        expect(hidden('a'), isFalse);
        expect(hidden('.collab/m1'), isFalse);
        expect(hidden('a/.trash/b.rpp'), isFalse);
      },
      testOn: 'windows',
    );
  });

  group('conventions', () {
    test('exclusions are case-insensitive', () {
      for (final name in [
        'song.RPP-BAK',
        'song-2024-01-02_1030.rpp-bak',
        'a.wav.reapeaks',
        'x.rpp-undo',
        'x.RPP-PROX',
        'x.reapindex',
        '.DS_Store',
        '._song.rpp',
        'Desktop.ini',
        'Thumbs.db',
        'doc.gdoc',
      ]) {
        expect(isExcludedFile(name), isTrue, reason: name);
      }
      expect(isExcludedFile('song.RPP'), isFalse);
      expect(isProjectFile('song.RPP'), isTrue);
      expect(isProjectFile('song.rpp-bak'), isFalse);
      expect(isExcludedFolder('Backups'), isTrue);
    });
  });

  group('layout scan', () {
    test('finds titles, versions, to sort and to adopt', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1.rpp', adopted);
      put('band/album/song/v2.RPP', unknown);
      put('band/album/song/v2.rpp-bak', unknown);
      put('band/album/song/Backups/v2-2024-01-02_1030.rpp', unknown);
      put('band/album/song/.history/old.rpp', unknown);
      put('band/album/song/Media/a.wav');
      put('band/album/song/old-takes/notes.txt');
      put('band/album/song/old-takes/take.rpp', unknown);
      put('band/_Unassigned/other/v1.rpp', unknown);
      put('band/loose.rpp', unknown);
      put('root.rpp', unknown);
      put('.collab/x.rpp', unknown);

      final result = await scan(storage, lib);

      expect(result.titles.map((t) => t.path), [
        'band/_Unassigned/other',
        'band/album/song',
      ]);
      final song = result.titles[1];
      expect(song.tags, {'artist': 'band', 'album': 'album', 'title': 'song'});
      expect(song.libraryId, lib.id);
      expect(song.versions.map((v) => v.fileName), ['v1.rpp', 'v2.RPP']);
      expect(song.versions[0].isAdopted, isTrue);
      expect(song.versions[1].isAdopted, isFalse);
      expect(result.toSort, [
        'band/album/song/old-takes/take.rpp',
        'band/loose.rpp',
        'root.rpp',
      ]);
      expect(result.toAdopt.map((e) => '${e.$1.path}/${e.$2.fileName}'), [
        'band/_Unassigned/other/v1.rpp',
        'band/album/song/v2.RPP',
      ]);
    });

    test('writes missing node files and keeps ids on rescan', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1.rpp', adopted);

      final first = await scan(storage, lib);
      expect(
        first.nodes.keys,
        unorderedEquals(['band', 'band/album', 'band/album/song']),
      );
      expect(exists('band/album/song/.node.json'), isTrue);
      expect(exists('.node.json'), isFalse);
      final saved = jsonDecode(
        File(p.join(root.path, 'band', 'album', 'song', '.node.json'))
            .readAsStringSync(),
      );
      expect(saved['level'], 'title');
      expect(saved['nodeId'], first.titles.single.id);

      final second = await scan(storage, lib);
      expect(second.titles.single.id, first.titles.single.id);
      expect(second.nodes['band']!.id, first.nodes['band']!.id);
    });

    test('sends folders with a wrong node level to sort', () async {
      final lib = library(Layout.classic());
      put('band/album/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');
      put('band/album/song/v1.rpp', unknown);

      final result = await scan(storage, lib);

      expect(result.titles, isEmpty);
      expect(result.toSort, ['band/album']);
      expect(result.corrupted, isEmpty);
    });

    test('reports corrupted node and project files', () async {
      final lib = library(Layout.classic());
      put('other/broken/.node.json', 'not json');
      put('other/broken/song/v1.rpp', unknown);
      put('other/shape/.node.json', '["array"]');
      put('band/album/song/v1.rpp', unknown);
      put('band/album/song/bad.rpp', r'<REAPER_PROJECT  <TRACK');

      final result = await scan(storage, lib);

      expect(result.titles.single.versions.map((v) => v.fileName), ['v1.rpp']);
      expect(result.toSort, isEmpty);
      expect(result.corrupted, [
        'band/album/song/bad.rpp',
        'other/broken/.node.json',
        'other/shape/.node.json',
      ]);
    });

    test('is incremental by size and mtime', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1.rpp', adopted);
      put('band/album/song/v2.rpp', unknown);
      final counting = CountingStorage(storage);

      final first = await scan(counting, lib);
      counting.reads.clear();
      final second = await scan(counting, lib, previous: first);
      expect(counting.reads, isEmpty);
      expect(
        second.titles.single.versions[0].metadata?.id,
        first.titles.single.versions[0].metadata?.id,
      );

      put('band/album/song/v2.rpp', adopted);
      final third = await scan(counting, lib, previous: second);
      expect(counting.reads, ['band/album/song/v2.rpp']);
      expect(third.toAdopt, isEmpty);
    });

    test('runs in an isolate', () async {
      put('band/album/song/v1.rpp', adopted);
      final result = await scanFolder(root.path, library(Layout.classic()));
      expect(result.titles.single.versions.single.isAdopted, isTrue);
    });
  });

  group('statuses', () {
    test('are written to the title node file and read by the scan', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1.rpp', adopted);
      final first = await scan(storage, lib);
      final versionId = first.titles.single.versions.single.metadata!.id;

      await setTitleStatus(storage, 'band/album/song', 'mixing');
      await setVersionStatus(storage, 'band/album/song', versionId, 'done');
      final saved = jsonDecode(
        File(p.join(root.path, 'band', 'album', 'song', '.node.json'))
            .readAsStringSync(),
      );
      expect(saved['status'], 'mixing');
      expect(saved['versionStatuses'], {versionId: 'done'});
      expect(saved['nodeId'], first.titles.single.id);

      final second = await scan(storage, lib, previous: first);
      final title = second.titles.single;
      expect(title.status, 'mixing');
      expect(title.statusOf(title.versions.single), 'done');
      expect(second.nodes['band/album/song']!.status, 'mixing');

      await setTitleStatus(storage, 'band/album/song', null);
      await setVersionStatus(storage, 'band/album/song', versionId, '');
      final cleared = (await scan(storage, lib, previous: second)).titles;
      expect(cleared.single.status, isNull);
      expect(cleared.single.versionStatuses, isEmpty);
      expect(
        File(p.join(root.path, 'band', 'album', 'song', '.node.json'))
            .readAsStringSync(),
        isNot(contains('tatus')),
      );
    });

    test('are kept for versions that no longer exist', () async {
      put('song/v1.rpp', unknown);
      await scan(storage, library(null));
      final gone = VersionId.generate();
      await setVersionStatus(storage, 'song', gone, 'idea');
      await setTitleStatus(storage, 'song', 'writing');

      final title = (await scan(storage, library(null))).titles.single;
      expect(title.status, 'writing');
      expect(title.versionStatuses, {gone: 'idea'});
      expect(title.statusOf(title.versions.single), isNull);
    });

    test('require an existing node file', () {
      expect(
        setTitleStatus(storage, 'missing', 'idea'),
        throwsA(isA<StateError>()),
      );
    });

    test('reject an invalid shape', () {
      expect(
        () => NodeFile.fromJson({
          'nodeId': newUlid(),
          'level': 'title',
          'versionStatuses': {'v': 1},
        }),
        throwsFormatException,
      );
    });
  });

  group('free tree scan', () {
    test('makes a title of every topmost folder holding a project', () async {
      put('band/2024/demo/demo.rpp', unknown);
      put('band/2024/demo/drums/v2/take.rpp', adopted);
      put('band/2024/demo/drums/notes.txt');
      put('band/2024/demo/Backups/demo-2024-01-02_1030.rpp', unknown);
      put('band/2024/demo/.trash/old.rpp', unknown);
      put('band/2024/demo/audio-files/a.wav');
      put('band/other/Song.RPP', unknown);
      final counting = CountingStorage(storage);

      final result = await scan(counting, library(null));

      expect(result.titles.map((t) => t.path), [
        'band/2024/demo',
        'band/other',
      ]);
      final demo = result.titles.first;
      expect(demo.tags, {
        'folder1': 'band',
        'folder2': '2024',
        'title': 'demo',
      });
      expect(demo.versions.map((v) => v.fileName), [
        'demo.rpp',
        'drums/v2/take.rpp',
      ]);
      expect(demo.versions.map((v) => v.key), [
        'demo.rpp',
        'drums/v2/take.rpp',
      ]);
      expect(demo.versions.every((v) => !v.isAdopted), isTrue);
      expect(result.freeTree, isTrue);
      expect(result.toAdopt, isEmpty);
      expect(result.toSort, isEmpty);
      expect(counting.reads.where(isProjectFile), isEmpty);
      expect(exists('band/2024/demo/.node.json'), isTrue);
      expect(exists('band/2024/demo/drums/v2/.node.json'), isFalse);
      expect(exists('band/.node.json'), isFalse);
      expect(result.nodes.keys, {'band/2024/demo', 'band/other'});
      expect(result.nodes['band/2024/demo']!.level, freeTreeLevel);
    });

    test('makes the root a single title when it holds a project', () async {
      put('top.rpp', unknown);
      put('band/demo/demo.rpp', unknown);

      final result = await scan(storage, library(null));

      expect(result.titles.single.path, '');
      expect(result.titles.single.versions.map((v) => v.fileName), [
        'band/demo/demo.rpp',
        'top.rpp',
      ]);
    });

    test('keys version statuses by relative path', () async {
      put('song/song.rpp', unknown);
      put('song/live/take.rpp', unknown);
      final lib = library(null);
      final first = await scan(storage, lib);
      final version = first.titles.single.versions.first;
      expect(version.fileName, 'live/take.rpp');

      await setVersionStatus(storage, 'song', version.key, 'done');
      final saved = jsonDecode(
        File(p.join(root.path, 'song', '.node.json')).readAsStringSync(),
      );
      expect(saved['versionStatuses'], {'live/take.rpp': 'done'});

      final title = (await scan(storage, lib, previous: first)).titles.single;
      expect(title.statusOf(title.versions.first), 'done');
      expect(title.statusOf(title.versions.last), isNull);
    });
  });

  group('project data', () {
    test('scan reads tempo and plugins of layout versions', () async {
      put('band/album/song/v1.rpp', unknown);
      final result = await scan(storage, library(Layout.classic()));
      final v = result.titles.single.versions.single;
      expect(v.tempo, 120);
      expect(
        v.plugins.map((p) => p.identifier),
        containsAll(['TDR Kotelnikov.vst3', 'reaeq.dll']),
      );
    });

    test('duplicates share a version id across titles', () async {
      put('band/album/song/v1.rpp', adopted);
      put('band/album/song/copy.rpp', adopted);
      put('band/album/other/v1.rpp', unknown);
      final result = await scan(storage, library(Layout.classic()));
      final duplicates = duplicateVersions(result.titles);
      expect(duplicates.values.single.map((d) => d.$2.fileName), [
        'copy.rpp',
        'v1.rpp',
      ]);
    });
  });

  group('scaffolding', () {
    bool dir(String path) =>
        Directory(p.joinAll([root.path, ...path.split('/')])).existsSync();

    test('scan scaffolds new layout titles only', () async {
      put('band/album/song/v1.rpp', adopted);
      put(
        'band/album/old/.node.json',
        '{"nodeId":"${newUlid()}","level":"title"}',
      );

      await scan(storage, library(Layout.classic()));

      for (final name in titleFolders) {
        expect(dir('band/album/song/$name'), isTrue, reason: name);
        expect(dir('band/album/old/$name'), isFalse, reason: name);
        expect(dir('band/album/$name'), isFalse, reason: name);
      }
      expect(exists('band/album/song/.node.json'), isTrue);
    });

    test('free tree titles are not scaffolded', () async {
      put('songs/demo/v1.rpp', unknown);
      await scan(storage, library(null));
      expect(exists('songs/demo/.node.json'), isTrue);
      expect(dir('songs/demo/Media'), isFalse);
    });

    test('scaffoldTitle creates the folders and node file', () async {
      final node = await scaffoldTitle(storage, 'band/album/song', 'title');
      expect(titleFolders.every((n) => dir('band/album/song/$n')), isTrue);
      final saved = await readNodeFile(storage, 'band/album/song');
      expect((saved!.id, saved.level), (node.id, 'title'));
    });
  });

  group('history', () {
    const title = 'band/album/song';
    final when = DateTime(2026, 11, 7, 15, 30, 12);

    String read(String path) =>
        File(p.joinAll([root.path, ...path.split('/')])).readAsStringSync();

    test('backs up a version under its name and date', () async {
      put('$title/Song - chorus.RPP', adopted);

      final path = await backupVersion(
        storage,
        title,
        'Song - chorus.RPP',
        now: when,
      );
      final again = await backupVersion(
        storage,
        title,
        'Song - chorus.RPP',
        now: when,
      );

      expect(path, '$title/.history/Song - chorus 2026-11-07 153012.RPP');
      expect(again, '$title/.history/Song - chorus 2026-11-07 153012 (2).RPP');
      expect(read(path), rebaseProjectPaths(adopted, title, '$title/.history'));
      expect(read(path), isNot(adopted));
      expect(read('$title/Song - chorus.RPP'), adopted);
      final result = await scan(storage, library(Layout.classic()));
      expect(result.titles.single.versions, hasLength(1));
    });

    test('lists backups by version, newest first', () async {
      final id = VersionMetadata.fromExtState(
        RppProject.parse(adopted).extState(VersionMetadata.section),
      )!.id;
      put('$title/v1.rpp', adopted);
      put('$title/.history/unknown 2026-01-01 000000.rpp', unknown);
      put('$title/.history/notes.txt', 'x');
      await backupVersion(storage, title, 'v1.rpp', now: when);
      await backupVersion(
        storage,
        title,
        'v1.rpp',
        now: when.add(const Duration(days: 1)),
      );

      final history = await readHistory(storage, title);

      expect(history.keys, [id]);
      expect(history[id]!.map((b) => b.created), [
        when.add(const Duration(days: 1)),
        when,
      ]);
      expect(await readHistory(storage, 'band/album/other'), isEmpty);
    });

    test('restores a backup after backing up the current state', () async {
      put('$title/v1.rpp', adopted);
      final backup = await backupVersion(storage, title, 'v1.rpp', now: when);
      put('$title/v1.rpp', '$adopted\n');

      final saved = await restoreBackup(
        storage,
        title,
        'v1.rpp',
        backup,
        now: when.add(const Duration(hours: 1)),
      );

      final history = '$title/.history';
      expect(read(backup), rebaseProjectPaths(adopted, title, history));
      expect(
        read('$title/v1.rpp'),
        rebaseProjectPaths(read(backup), history, title),
      );
      expect(read(saved), rebaseProjectPaths('$adopted\n', title, history));
    });

    const project = r'''<REAPER_PROJECT 0.1 "7.84/win64" 0
  RECORD_PATH "Media" ""
  RENDER_FILE ".\Renders"
  <TRACK
    <ITEM
      <SOURCE WAVE
        FILE "Media\kick.wav"
      >
    >
    <ITEM
      <SOURCE WAVE
        FILE "C:\Samples\snare.wav"
      >
    >
    <ITEM
      <SOURCE MIDI
        FILE "../../../../other.mid" QN
      >
    >
  >
>
''';

    RppProject parse(String text) => RppProject.parse(text);

    test('rebases relative paths into and out of the history', () {
      final backup = rebaseProjectPaths(project, title, '$title/.history');
      expect(parse(backup).mediaFiles, {
        r'..\Media\kick.wav',
        r'C:\Samples\snare.wav',
        '../../../../../other.mid',
      });
      expect(parse(backup).recordPath, r'..\Media');
      expect(parse(backup).renderFile, r'..\Renders');
      expect(backup, contains('FILE "../../../../../other.mid" QN'));

      final restored = rebaseProjectPaths(backup, '$title/.history', title);
      expect(parse(restored).mediaFiles, {
        r'Media\kick.wav',
        r'C:\Samples\snare.wav',
        '../../../../other.mid',
      });
      expect(parse(restored).recordPath, 'Media');
      expect(parse(restored).renderFile, 'Renders');
    });

    test('rebases an empty record path to the project folder', () {
      final text = project.replaceFirst(
        'RECORD_PATH "Media" ""',
        'RECORD_PATH "" ""',
      );
      final backup = rebaseProjectPaths(text, title, '$title/.history');
      expect(parse(backup).recordPath, '..');
      expect(
        parse(rebaseProjectPaths(backup, '$title/.history', title)).recordPath,
        '',
      );
    });

    test('normalizes paths lengthened by REAPER, keeps clean files', () async {
      final history = '$title/.history';
      final file = '$history/v1 2026-11-07 153012.rpp';
      final clean = rebaseProjectPaths(project, title, history);
      expect(rebaseProjectPaths(clean, history, history), clean);
      put(
        file,
        clean.replaceFirst(r'..\Media\kick.wav', r'..\Media\..\Media\kick.wav'),
      );

      await cleanBackupPaths(storage, file);

      expect(read(file), clean);
    });
  });

  group('versions', () {
    const title = 'band/album/song';
    final owner = MemberId.generate();

    String read(String path) =>
        File(p.joinAll([root.path, ...path.split('/')])).readAsStringSync();

    VersionMetadata? metadataOf(String path) => VersionMetadata.fromExtState(
      RppProject.parse(read(path)).extState(VersionMetadata.section),
    );

    VersionMetadata meta([String label = '']) =>
        VersionMetadata(id: VersionId.generate(), owner: owner, label: label);

    String withoutMetadata(String text) => setExtState(
      text,
      VersionMetadata.section,
      {for (final k in meta().toExtState().keys) k: null},
    );

    /// [adopted] with every media reference replaced by [ref].
    String withMedia(String ref, {String record = 'Media'}) => setRootAttribute(
      rewriteMediaPaths(adopted, (_) => ref),
      'RECORD_PATH',
      [record, ''],
    );

    test('creates a blank version, scanned as adopted', () async {
      final m = meta('intro');
      final path = await createVersion(storage, title, 'Song - intro.RPP', m);

      expect(path, '$title/Song - intro.RPP');
      final root = RppProject.parse(read(path)).document.root;
      expect(root.line('RECORD_PATH')!.params, ['Media', '']);
      expect(root.line('RENDER_FILE')!.params, ['Renders']);
      expect(metadataOf(path)!.id, m.id);
      final result = await scan(storage, library(Layout.classic()));
      expect(result.titles.single.versions.single.metadata!.label, 'intro');
    });

    test('creates a version from a template, keeping its content', () async {
      final path = await createVersion(
        storage,
        title,
        'Song.rpp',
        meta(),
        template: unknown,
      );

      final project = RppProject.parse(read(path));
      expect(project.tracks.length, RppProject.parse(unknown).tracks.length);
      expect(project.document.root.line('RECORD_PATH')!.params.first, 'Media');
    });

    test('refuses invalid or existing names', () async {
      put('$title/Song.RPP', adopted);
      expect(
        () => createVersion(storage, title, 'Song.RPP', meta()),
        throwsStateError,
      );
      for (final name in ['Song.txt', 'a/b.rpp', '.rpp', ' .rpp']) {
        expect(
          () => createVersion(storage, title, name, meta()),
          throwsArgumentError,
          reason: name,
        );
      }
    });

    test('duplicates a version under a new identity', () async {
      put('$title/Song.RPP', adopted);
      final m = meta('copy');

      final path = await duplicateVersion(
        storage,
        title,
        'Song.RPP',
        'Song - copy.RPP',
        m,
      );

      expect(metadataOf(path)!.id, m.id);
      expect(withoutMetadata(read(path)), withoutMetadata(adopted));
    });

    test('renames a version and edits its label', () async {
      put('$title/Song.RPP', adopted);
      final id = metadataOf('$title/Song.RPP')!.id;

      final path = await renameVersion(
        storage,
        title,
        'Song.RPP',
        'Song B.RPP',
      );
      await setVersionLabel(storage, title, 'Song B.RPP', 'bridge');

      expect(path, '$title/Song B.RPP');
      expect(exists('$title/Song.RPP'), isFalse);
      expect(metadataOf(path)!.id, id);
      expect(metadataOf(path)!.label, 'bridge');
      put('$title/Other.RPP', unknown);
      expect(
        () => renameVersion(storage, title, 'Other.RPP', 'Song B.RPP'),
        throwsStateError,
      );
      expect(
        () => setVersionLabel(storage, title, 'Other.RPP', 'x'),
        throwsStateError,
      );
    });

    test('deletes versions to the trash next to them', () async {
      put('$title/Song.RPP', adopted);
      put('$title/.trash/Song.RPP', adopted);
      put('free/member/v2/take.rpp', unknown);

      final trashed = await deleteVersion(storage, title, 'Song.RPP');
      final nested = await deleteVersion(storage, 'free', 'member/v2/take.rpp');

      expect(trashed, '$title/.trash/Song (2).RPP');
      expect(nested, 'free/member/v2/.trash/take.rpp');
      expect(exists('$title/Song.RPP'), isFalse);
      expect((await readTrash(storage, 'free')).map((e) => e.path), [nested]);
    });

    test('purges trash files only', () async {
      put('$title/.trash/Song.RPP', adopted);
      put('$title/Song.RPP', adopted);

      await expectLater(
        purgeTrash(storage, title, ['$title/Song.RPP']),
        throwsArgumentError,
      );
      await purgeTrash(storage, title, [
        for (final e in await readTrash(storage, title)) e.path,
      ]);

      expect(exists('$title/.trash/Song.RPP'), isFalse);
      expect(exists('$title/Song.RPP'), isTrue);
    });

    test('lists media referenced by no version nor backup', () async {
      expect(RppProject.parse(adopted).mediaFiles, isNotEmpty);
      put('$title/Song.RPP', withMedia(r'Media\kick.wav'));
      put('$title/Other.RPP', withMedia('snare.wav'));
      put(
        '$title/.history/Song 2026-01-01 000000.RPP',
        withMedia(r'..\Media\bass.wav', record: r'..\Media'),
      );
      put('$title/.trash/Old.RPP', withMedia(r'Media\old.wav'));
      put('$title/Far.RPP', withMedia(r'D:\elsewhere\Media\far.wav'));
      for (final name in [
        'kick.wav',
        'snare.wav',
        'bass.wav',
        'old.wav',
        'far.wav',
        'orphan.wav',
        'orphan.wav.reapeaks',
      ]) {
        put('$title/Media/$name', 'x');
      }

      final orphans = await unreferencedMedia(storage, title);

      expect(
        orphans.map((e) => e.path),
        unorderedEquals(['$title/Media/old.wav', '$title/Media/orphan.wav']),
      );
      await expectLater(
        purgeMedia(storage, title, ['$title/Song.RPP']),
        throwsArgumentError,
      );
      await purgeMedia(storage, title, [for (final e in orphans) e.path]);
      expect(exists('$title/Media/orphan.wav'), isFalse);
      expect(exists('$title/Media/kick.wav'), isTrue);
      expect(await unreferencedMedia(storage, 'band/album/none'), isEmpty);
    });

    test('lists no media when a project cannot be read', () async {
      put('$title/Media/a.wav', 'x');
      File(p.joinAll([root.path, ...'$title/Bad.RPP'.split('/')]))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xff, 0xfe, 0x00]);

      await expectLater(
        unreferencedMedia(storage, title),
        throwsFormatException,
      );
    });
  });

  group('adoption', () {
    test('writes version metadata into the project', () async {
      put('band/album/song/v1.rpp', unknown);
      final metadata = VersionMetadata(
        id: VersionId.generate(),
        owner: MemberId.generate(),
        label: 'chorus B',
      );
      await writeVersionMetadata(storage, 'band/album/song/v1.rpp', metadata);
      final result = await scan(storage, library(Layout.classic()));
      final read = result.titles.single.versions.single.metadata!;
      expect(
        (read.id, read.owner, read.label),
        (metadata.id, metadata.owner, 'chorus B'),
      );
      expect(result.toAdopt, isEmpty);
    });

    test('accepts portable folder names only', () {
      expect(isValidFolderName('Album 2'), isTrue);
      expect(isValidFolderName(Layout.unassigned), isTrue);
      for (final name in ['', '.hidden', 'a/b', r'a\b', 'a:b', 'end.', 'x ']) {
        expect(isValidFolderName(name), isFalse, reason: name);
      }
    });
  });

  group('guided move', () {
    String project(List<String> media) => [
      '<REAPER_PROJECT 0.1 "7.84/win64" 0',
      '  RECORD_PATH "audio-files" ""',
      '  <TRACK',
      for (final m in media) ...[
        '    <ITEM',
        '      <SOURCE WAVE',
        '        FILE "$m"',
        '      >',
        '    >',
      ],
      '  >',
      '>',
      '',
    ].join('\n');

    RppProject read(String path) => RppProject.parse(
      File(p.joinAll([root.path, ...path.split('/')])).readAsStringSync(),
    );

    test('moves the project and its media into the title pool', () async {
      put(
        'band/loose.rpp',
        project([r'audio-files\kick.wav', r'C:\elsewhere\x.wav', 'gone.wav']),
      );
      put('band/audio-files/kick.wav', 'kick');

      final report = await moveProjectToTitle(
        storage,
        'band/loose.rpp',
        'band/_Unassigned/loose',
      );

      expect(report.project, 'band/_Unassigned/loose/loose.rpp');
      expect(report.moved, ['band/_Unassigned/loose/Media/kick.wav']);
      expect(report.missing, ['gone.wav']);
      expect(report.external, [r'C:\elsewhere\x.wav']);
      expect(exists('band/loose.rpp'), isFalse);
      expect(exists('band/audio-files/kick.wav'), isFalse);
      final moved = read(report.project);
      expect(moved.mediaFiles, [
        r'Media\kick.wav',
        r'C:\elsewhere\x.wav',
        'gone.wav',
      ]);
      expect(moved.recordPath, 'Media');

      final result = await scan(storage, library(Layout.classic()));
      expect(result.toSort, isEmpty);
      expect(result.titles.single.path, 'band/_Unassigned/loose');
    });

    test(
      'copies shared media, reuses identical ones, renames others',
      () async {
        put(
          'band/a.rpp',
          project(['audio/kick.wav', 'audio/snare.wav', 'audio/hat.wav']),
        );
        put('band/b.rpp', project(['audio/kick.wav']));
        put('band/audio/kick.wav', 'kick');
        put('band/audio/snare.wav', 'snare');
        put('band/audio/hat.wav', 'hat');
        put('band/album/song/Media/snare.wav', 'snare');
        put('band/album/song/Media/hat.wav', 'other hat');
        put('band/album/song/a.rpp', unknown);

        final report = await moveProjectToTitle(
          storage,
          'band/a.rpp',
          'band/album/song',
        );

        expect(report.project, 'band/album/song/a (2).rpp');
        expect(report.copied, ['band/album/song/Media/kick.wav']);
        expect(report.moved, ['band/album/song/Media/hat (2).wav']);
        expect(exists('band/audio/kick.wav'), isTrue);
        expect(exists('band/audio/snare.wav'), isTrue);
        expect(read(report.project).mediaFiles, [
          'Media/kick.wav',
          'Media/snare.wav',
          'Media/hat (2).wav',
        ]);
      },
    );
  });
}
