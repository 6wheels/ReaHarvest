import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
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
  final owner = MemberId.generate();
  final t0 = DateTime(2026, 1, 2, 3, 4, 5, 6, 7);
  final t1 = DateTime(2026, 2, 1);

  Library library() => Library(
    id: LibraryId.generate(),
    mode: LibraryMode.local,
    layout: Layout.classic(),
  );

  Title title(
    LibraryId lib,
    String artist,
    String album,
    String name, {
    List<Version> versions = const [],
  }) => Title(
    id: NodeId.generate(),
    libraryId: lib,
    path: '$artist/$album/$name',
    tags: {'artist': artist, 'album': album, 'title': name},
    versions: versions,
  );

  Version version(String fileName, {String? label, MemberId? by}) => Version(
    fileName: fileName,
    modified: t0,
    size: 10,
    tempo: label == null ? null : 98.5,
    length: label == null ? null : 184.5,
    trackCount: label == null ? null : 12,
    itemCount: label == null ? null : 40,
    plugins: [
      if (label != null)
        const PluginRef(
          kind: 'VST3',
          name: 'Comp (Vendor)',
          identifier: 'comp.vst3',
        ),
    ],
    media: [if (label != null) r'Media\kick.wav'],
    recordPath: label == null ? null : 'Media',
    renderFile: label == null ? null : 'Renders',
    metadata: label == null
        ? null
        : VersionMetadata(
            id: VersionId.generate(),
            owner: by ?? owner,
            label: label,
          ),
  );

  late LocalIndex index;

  setUp(() => index = LocalIndex.inMemory());
  tearDown(() => index.close());

  group('LocalIndex', () {
    test('stores and restores libraries, titles, versions and issues', () {
      final lib = library();
      final song = title(
        lib.id,
        'Band',
        'First Album',
        'Song',
        versions: [
          version('a.RPP', label: 'chorus B'),
          version('b.rpp'),
        ],
      );
      final nodeId = NodeId.generate();
      index.update(
        lib,
        ScanResult(
          titles: [song],
          nodes: {'Band': NodeFile(nodeId, 'artist')},
          issues: Report({
            ReportKind.projectTooDeep: [
              const ReportItem.misplaced(
                'Band/First Album/Song/mix/x.rpp',
                level: LayoutLevel('title'),
                target: 'Band/First Album/Song',
              ),
            ],
            ReportKind.projectTooShallow: [
              const ReportItem.misplaced(
                'loose.rpp',
                level: LayoutLevel('gone'),
              ),
            ],
            ReportKind.duplicateVersionId: [
              const ReportItem('Band/First Album/Song/b.rpp', 'id1'),
              const ReportItem('Band/First Album/Song/a.RPP', 'id1'),
            ],
          }),
          corrupted: ['Band/bad.rpp'],
          orphanNodes: ['Band/render/.node.json'],
          stamps: {'Band/First Album/Song/a.RPP': (size: 10, modified: t0)},
          subprojects: const {
            'Band/First Album/Song/Media/sub.rpp': [r'C:\x.wav'],
          },
        ),
      );

      expect(index.libraries().single.id, lib.id);
      final restored = index.scanResult(lib.id)!;
      final t = restored.titles.single;
      expect(t.id, song.id);
      expect(t.tags, song.tags);
      expect(t.tags.keys, ['artist', 'album', 'title']);
      expect(t.versions.map((v) => v.fileName), ['a.RPP', 'b.rpp']);
      final a = t.versions.first;
      expect(a.metadata!.id, song.versions.first.metadata!.id);
      expect(a.metadata!.owner, owner);
      expect(a.metadata!.label, 'chorus B');
      expect(a.modified, t0);
      expect(a.tempo, 98.5);
      expect((a.length, a.trackCount, a.itemCount), (184.5, 12, 40));
      expect(a.plugins, song.versions.first.plugins);
      expect(a.media, [r'Media\kick.wav']);
      expect((a.recordPath, a.renderFile), ('Media', 'Renders'));
      expect(t.versions.last.isAdopted, isFalse);
      expect(t.versions.last.tempo, isNull);
      expect(t.versions.last.trackCount, isNull);
      expect(t.versions.last.plugins, isEmpty);
      expect(t.versions.last.media, isEmpty);
      expect(t.versions.last.recordPath, isNull);
      expect(restored.nodes['Band']!.id, nodeId);
      expect(restored.subprojects, {
        'Band/First Album/Song/Media/sub.rpp': [r'C:\x.wav'],
      });
      expect(restored.issues.items, {
        ReportKind.projectTooDeep: [
          const ReportItem.misplaced(
            'Band/First Album/Song/mix/x.rpp',
            level: LayoutLevel('title'),
            target: 'Band/First Album/Song',
          ),
        ],
        ReportKind.projectTooShallow: [
          const ReportItem.misplaced('loose.rpp', level: LayoutLevel('gone')),
        ],
        ReportKind.duplicateVersionId: [
          const ReportItem('Band/First Album/Song/a.RPP', 'id1'),
          const ReportItem('Band/First Album/Song/b.rpp', 'id1'),
        ],
      });
      expect(restored.corrupted, ['Band/bad.rpp']);
      expect(restored.orphanNodes, ['Band/render/.node.json']);
      expect(index.issues(kind: ReportKind.orphanNode), [
        (
          library: lib.id,
          kind: ReportKind.orphanNode,
          item: const ReportItem('Band/render/.node.json'),
        ),
      ]);
      // Sorted by kind (display order), then path.
      final all = index.issues();
      expect(all.map((i) => i.kind), [
        ReportKind.corrupted,
        ReportKind.projectTooDeep,
        ReportKind.projectTooShallow,
        ReportKind.duplicateVersionId,
        ReportKind.duplicateVersionId,
        ReportKind.orphanNode,
      ]);
      expect(
        [for (final i in all) i.item.level?.key],
        [null, 'title', 'gone', null, null, null],
      );
      final other = library();
      index.update(
        other,
        ScanResult(corrupted: ['a.rpp'], orphanNodes: ['b/.node.json']),
      );
      final libraries = [for (final i in index.issues()) i.library];
      expect(libraries, [...libraries]..sort());
      expect(libraries.toSet(), {lib.id, other.id});
      expect(index.issues(library: other.id), hasLength(2));
      index.removeLibrary(other.id);
      expect(restored.stamps, {
        'Band/First Album/Song/a.RPP': (size: 10, modified: t0),
      });
      expect(restored.toAdopt.single.$2.fileName, 'b.rpp');
      expect(restored.freeTree, isFalse);

      expect(index.scanResult(LibraryId.generate()), isNull);
      index.removeLibrary(lib.id);
      expect(index.libraries(), isEmpty);
      expect(index.titles(), isEmpty);
      expect(index.files(lib.id), isEmpty);
    });

    test('keeps hashes of unchanged files only', () async {
      final lib = library();
      ScanResult scanOf(Map<String, FileStamp> stamps) =>
          ScanResult(stamps: stamps);

      index.update(
        lib,
        scanOf({
          'a.wav': (size: 1, modified: t0),
          'b.wav': (size: 2, modified: t0),
          'c.wav': (size: 3, modified: t0),
        }),
      );
      final hashed = <String>[];
      final count = await index.hashPending(lib.id, (path) async {
        hashed.add(path);
        return 'h-$path';
      });
      expect(count, 3);
      expect(hashed, ['a.wav', 'b.wav', 'c.wav']);
      expect(index.hashOf(lib.id, 'a.wav'), 'h-a.wav');

      index.update(
        lib,
        scanOf({
          'a.wav': (size: 1, modified: t0),
          'b.wav': (size: 2, modified: t1),
          'd.wav': (size: 4, modified: t0),
        }),
      );
      expect(index.hashOf(lib.id, 'a.wav'), 'h-a.wav');
      expect(index.hashOf(lib.id, 'b.wav'), isNull);
      expect(index.files(lib.id).map((f) => f.path), [
        'a.wav',
        'b.wav',
        'd.wav',
      ]);
      expect(index.files(lib.id, unhashedOnly: true).map((f) => f.path), [
        'b.wav',
        'd.wav',
      ]);

      // A hash computed for an outdated stamp is not stored.
      expect(
        index.setHash(lib.id, 'b.wav', (size: 2, modified: t0), 'stale'),
        isFalse,
      );
      expect(index.hashOf(lib.id, 'b.wav'), isNull);
    });

    test('lists titles of all libraries', () {
      final one = library();
      final two = library();
      index.update(one, ScanResult(titles: [title(one.id, 'A', 'B', 'C')]));
      index.update(
        two,
        ScanResult(
          titles: [title(two.id, 'X', 'Y', 'Z'), title(two.id, 'D', 'E', 'F')],
        ),
      );
      expect(index.titles().length, 3);
      expect(index.titles(library: two.id).map((t) => t.path), [
        'D/E/F',
        'X/Y/Z',
      ]);

      index.update(two, const ScanResult());
      expect(index.titles().single.path, 'A/B/C');
    });

    test('persists to disk and survives a reopen', () {
      final dir = Directory.systemTemp.createTempSync('reaharvest_index_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'index.db');
      final lib = library();
      final disk = LocalIndex.open(path);
      disk.update(lib, ScanResult(titles: [title(lib.id, 'A', 'B', 'C')]));
      disk.close();
      final reopened = LocalIndex.open(path);
      addTearDown(reopened.close);
      expect(reopened.titles().single.path, 'A/B/C');
    });

    test('serves 1,000 titles in under a second', () {
      final lib = library();
      index.update(
        lib,
        ScanResult(
          titles: [
            for (var i = 0; i < 1000; i++)
              title(
                lib.id,
                'Artist ${i % 20}',
                'Album ${i % 100}',
                'Title $i',
                versions: [
                  for (var v = 0; v < 5; v++)
                    version('v$v.rpp', label: 'take $v'),
                ],
              ),
          ],
        ),
      );
      final watch = Stopwatch()..start();
      final titles = index.titles();
      final search = TitleSearch(titles);
      search.search('titl 99');
      watch.stop();
      expect(titles.length, 1000);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('restored scan makes a rescan incremental', () async {
      final root = Directory.systemTemp.createTempSync('reaharvest_scan_');
      addTearDown(() => root.deleteSync(recursive: true));
      final song = Directory(p.join(root.path, 'Band', 'Album', 'Song'))
        ..createSync(recursive: true);
      File('$fixtures/tracks.rpp').copySync(p.join(song.path, 'v1.rpp'));
      File(p.join(song.path, 'Media', 'kick.wav'))
        ..createSync(recursive: true)
        ..writeAsStringSync('audio');

      final lib = library();
      final storage = CountingStorage(MountedFolderStorage(root.path));
      index.update(lib, await scan(storage, lib));
      expect(
        index.files(lib.id).map((f) => f.path),
        containsAll([
          'Band/Album/Song/v1.rpp',
          'Band/Album/Song/Media/kick.wav',
          'Band/Album/Song/.node.json',
        ]),
      );

      // After a restart: the stored scan is the baseline.
      storage.reads.clear();
      final again = await scan(
        storage,
        lib,
        previous: index.scanResult(lib.id),
      );
      expect(storage.reads, isEmpty);
      expect(again.titles.single.versions.single.fileName, 'v1.rpp');
    });

    test('stores statuses and keeps them across a restart', () async {
      final root = Directory.systemTemp.createTempSync('reaharvest_scan_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(p.join(root.path, 'Band', 'Album', 'Song'))
          .createSync(recursive: true);
      File('$fixtures/tracks.rpp')
          .copySync(p.join(root.path, 'Band', 'Album', 'Song', 'v1.rpp'));
      final lib = library();
      final storage = MountedFolderStorage(root.path);
      await scan(storage, lib);
      final versionId = VersionId.generate();
      await setTitleStatus(storage, 'Band/Album/Song', 'recording');
      await setVersionStatus(storage, 'Band/Album/Song', versionId, 'done');
      index.update(lib, await scan(storage, lib));

      final stored = index.titles().single;
      expect(stored.status, 'recording');
      expect(stored.versionStatuses, {versionId: 'done'});

      // After a restart, unchanged node files are not read again: statuses
      // must come from the stored scan.
      final again = await scan(
        storage,
        lib,
        previous: index.scanResult(lib.id),
      );
      expect(again.titles.single.status, 'recording');
      expect(again.nodes['Band/Album/Song']!.versionStatuses, {
        versionId: 'done',
      });
    });
  });

  group('TitleSearch', () {
    final lib = LibraryId.generate();
    final alice = MemberId.generate();
    final titles = [
      title(
        lib,
        'Northern Lights',
        'Éclipse',
        'Dancing on a line',
        versions: [version('Drums take.rpp', label: 'chorus B', by: alice)],
      ),
      title(lib, 'Southern Band', 'Second', 'Morning coffee'),
      title(lib, 'Northern Lights', 'Second', 'Late night'),
    ];
    final search = TitleSearch(titles, memberNames: {alice: 'Alice'});

    List<String> find(String query) =>
        search.search(query).map((t) => t.tags['title']!).toList();

    test('blank query returns every title in order', () {
      expect(find('  '), ['Dancing on a line', 'Morning coffee', 'Late night']);
    });

    test('matches tags, version names, labels and owners', () {
      expect(find('morning'), ['Morning coffee']);
      expect(find('drums'), ['Dancing on a line']);
      expect(find('chorus'), ['Dancing on a line']);
      expect(find('alice'), ['Dancing on a line']);
      expect(find('northern'), ['Dancing on a line', 'Late night']);
    });

    test('combines words, prefixes and diacritics', () {
      expect(find('north late'), ['Late night']);
      expect(find('danc'), ['Dancing on a line']);
      expect(find('eclipse'), ['Dancing on a line']);
      expect(find('ÉCLIPSÉ'), ['Dancing on a line']);
    });

    test('tolerates typos', () {
      expect(find('mornign'), ['Morning coffee']);
      expect(find('cofee'), ['Morning coffee']);
      expect(find('nortern lihgts'), ['Dancing on a line', 'Late night']);
      expect(find('xyz'), isEmpty);
    });

    test('ranks exact matches first', () {
      expect(find('second').length, 2);
      expect(find('late').first, 'Late night');
    });
  });
}
