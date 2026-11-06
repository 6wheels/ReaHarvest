import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
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
      await storage.move('a/b/c.txt', 'a/_trash/c.txt');
      expect(exists('a/_trash/c.txt'), isTrue);
      expect(exists('a/b/c.txt'), isFalse);
      await storage.write('a/b/c.txt', Stream.value(utf8.encode('x')));
      expect(
        () => storage.move('a/b/c.txt', 'a/_trash/c.txt'),
        throwsA(isA<FileSystemException>()),
      );
    });
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
      put('band/album/song/_versions/old.rpp', unknown);
      put('band/album/song/Media/a.wav');
      put('band/album/song/old-takes/notes.txt');
      put('band/album/song/old-takes/take.rpp', unknown);
      put('band/_Unassigned/other/v1.rpp', unknown);
      put('band/loose.rpp', unknown);
      put('root.rpp', unknown);
      put('_collab/x.rpp', unknown);

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

  group('free tree scan', () {
    test('makes a title of every folder holding a project', () async {
      put('band/2024/demo/demo.rpp', unknown);
      put('band/2024/demo/drums/v2/take.rpp', adopted);
      put('band/2024/demo/Backups/demo-2024-01-02_1030.rpp', unknown);
      put('band/2024/demo/audio-files/a.wav');
      put('top.rpp', unknown);

      final result = await scan(storage, library(null));

      expect(result.titles.map((t) => t.path), [
        '',
        'band/2024/demo',
        'band/2024/demo/drums/v2',
      ]);
      expect(result.titles[1].tags, {
        'folder1': 'band',
        'folder2': '2024',
        'title': 'demo',
      });
      expect(result.titles[2].tags['title'], 'v2');
      expect(result.toSort, isEmpty);
      expect(exists('band/2024/demo/.node.json'), isTrue);
      expect(exists('band/.node.json'), isFalse);
      expect(result.nodes['band/2024/demo']!.level, freeTreeLevel);
    });
  });
}
