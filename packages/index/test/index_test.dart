import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

const fixtures = '../../test/fixtures';

/// Storage recording the paths read.
final class CountingStorage implements RepositoryStorage {
  CountingStorage(this.inner);

  final RepositoryStorage inner;
  final reads = <String>[];

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) {
    listed.add(recursive ? '$dir/**' : dir);
    return inner.list(dir, recursive: recursive);
  }

  @override
  Future<StorageEntry?> stat(String path) => inner.stat(path);

  /// Folders listed, recursive ones suffixed with `/**`.
  final listed = <String>[];

  @override
  Stream<List<int>> read(String path) {
    reads.add(path);
    return inner.read(path);
  }

  @override
  Future<void> write(String path, Stream<List<int>> content) =>
      inner.write(path, content);

  @override
  Future<void> append(String path, List<int> bytes) =>
      inner.append(path, bytes);

  @override
  Future<void> move(String from, String to) => inner.move(from, to);

  @override
  Future<void> createDirectory(String path) => inner.createDirectory(path);

  @override
  Future<void> delete(String path) => inner.delete(path);

  @override
  Future<void> setModified(String path, DateTime modified) =>
      inner.setModified(path, modified);
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

    test('stores the journal position of the last scan', () {
      final lib = library();
      expect(index.journalPosition(lib.id), isNull);
      const position = (folder: '.migration/2026-11-12_000000_000', line: 7);
      index.update(lib, const ScanResult(journalPosition: position));
      expect(index.journalPosition(lib.id), position);
      index.update(lib, const ScanResult());
      expect(index.journalPosition(lib.id), isNull);
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

    test('keeps version labels and owners across a restart', () async {
      final root = Directory.systemTemp.createTempSync('reaharvest_scan_');
      addTearDown(() => root.deleteSync(recursive: true));
      const title = 'Band/Album/Song';
      final lib = library();
      final storage = MountedFolderStorage(root.path);
      await scaffoldTitle(storage, title, 'title');
      final kept = VersionMetadata(
        id: VersionId.generate(),
        label: 'chorus B',
        owner: owner,
      );
      await createVersion(storage, title, 'v1.rpp', kept);
      final gone = VersionId.generate();
      await setVersionLabel(storage, title, gone, 'old take');
      index.update(lib, await scan(storage, lib));

      final stored = index.titles().single.versions.single.metadata!;
      expect((stored.label, stored.owner), ('chorus B', owner));

      // Unchanged node file: not read again, its entries come from the
      // stored scan, those of versions that no longer exist included.
      final again = await scan(
        storage,
        lib,
        previous: index.scanResult(lib.id),
      );
      final m = again.titles.single.versions.single.metadata!;
      expect((m.id, m.label, m.owner), (kept.id, 'chorus B', owner));
      expect(again.nodes[title]!.versionLabels, {
        kept.id: 'chorus B',
        gone: 'old take',
      });
      expect(again.nodes[title]!.versionOwners, {kept.id: owner});
    });
  });

  group('updateTitle', () {
    /// Comparable form of the scan stored in [index] for [id].
    Object describe(LocalIndex index, LibraryId id) {
      final s = index.scanResult(id)!;
      return {
        'titles': [
          for (final t in s.titles)
            [
              t.id,
              t.path,
              t.tags,
              t.status,
              t.versionStatuses,
              for (final v in t.versions)
                [
                  v.fileName,
                  v.size,
                  v.modified,
                  v.metadata?.id,
                  v.metadata?.label,
                  v.metadata?.owner,
                  v.tempo,
                  v.trackCount,
                  v.media,
                  v.recordPath,
                  v.renderFile,
                ],
            ],
        ],
        'nodes': {
          for (final MapEntry(:key, :value) in s.nodes.entries)
            key: [
              value.id,
              value.level,
              value.status,
              value.versionStatuses,
              value.versionLabels,
              value.versionOwners,
            ],
        },
        'issues': [
          for (final i in index.issues(library: id))
            [i.kind, i.item.path, i.item.detail, i.item.level?.key],
        ],
        'stamps': s.stamps,
        'subprojects': s.subprojects,
      };
    }

    String project({VersionId? id, List<String> media = const []}) => [
      '<REAPER_PROJECT 0.1 "7.84/win64" 0',
      '  RECORD_PATH "Media" ""',
      '  RENDER_FILE "Renders"',
      '  <TRACK',
      for (final m in media) ...[
        '    <ITEM',
        '      <SOURCE WAVE',
        '        FILE "$m"',
        '      >',
        '    >',
      ],
      '  >',
      if (id != null) ...[
        '  <EXTSTATE',
        '    <${VersionMetadata.section}',
        '      ${VersionMetadata.idKey} $id',
        '    >',
        '  >',
      ],
      '>',
    ].join('\n');

    late Directory root;
    late CountingStorage storage;

    void put(String path, String content) =>
        File(p.joinAll([root.path, ...path.split('/')]))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);

    setUp(() {
      root = Directory.systemTemp.createTempSync('reaharvest_title_');
      storage = CountingStorage(MountedFolderStorage(root.path));
    });
    tearDown(() => root.deleteSync(recursive: true));

    /// Indexes [lib] with a full scan, then scans the title [path] only,
    /// stores it, and checks the index against a full scan in another one.
    Future<void> rescanAndCompare(Library lib, String path) async {
      final stored = index.scanResult(lib.id)!;
      // Only the stored rows of the title are loaded for its rescan.
      final slice = index.storedTitle(lib.id, path)!;
      expect(slice.titles.map((t) => t.path), [path]);
      expect(slice.nodes.keys, [path]);
      expect(slice.stamps.keys.every((k) => k.startsWith('$path/')), isTrue);
      final previous = slice.titles.single;
      storage
        ..listed.clear()
        ..reads.clear();
      final result = await scanTitle(storage, lib, previous, stored: slice);
      expect(storage.listed, ['$path/**']);
      expect(storage.reads, isNot(contains('$path/.node.json')));
      index.updateTitle(lib, path, result);

      final full = LocalIndex.inMemory();
      addTearDown(full.close);
      full.update(lib, await scan(storage, lib, previous: stored));
      expect(describe(index, lib.id), describe(full, lib.id));
    }

    test('rescans one title of 1,000 as a full scan would', () async {
      final lib = library();
      final shared = VersionId.generate();
      for (var i = 0; i < 1000; i++) {
        put(
          'Artist ${i % 10}/Album ${i % 50}/Title $i/v.rpp',
          project(id: i < 2 ? shared : VersionId.generate()),
        );
      }
      index.update(lib, await scan(storage, lib));
      expect(
        index
            .issues(kind: ReportKind.duplicateVersionId)
            .map((i) => i.item.path),
        ['Artist 0/Album 0/Title 0/v.rpp', 'Artist 1/Album 1/Title 1/v.rpp'],
      );
      const one = 'Artist 1/Album 1/Title 1';

      // Separated: the duplicate across titles is gone.
      put('$one/v.rpp', project(id: VersionId.generate()));
      put('$one/Media/a.wav', 'a');
      put('$one/mix/deep.rpp', project());
      await rescanAndCompare(lib, one);
      expect(index.issues(kind: ReportKind.duplicateVersionId), isEmpty);
      expect(
        index.issues(kind: ReportKind.projectTooDeep).single.item.path,
        '$one/mix/deep.rpp',
      );

      // A copy keeping the id of another title: found again.
      put(
        '$one/copy.rpp',
        project(
          id: index.titles(library: lib.id).first.versions.single.metadata!.id,
        ),
      );
      await rescanAndCompare(lib, one);
      expect(index.issues(kind: ReportKind.duplicateVersionId), hasLength(2));
    });

    test('keeps hashes of unchanged files and the level issues', () async {
      final lib = library().withKnownValues(const [
        KnownValue('Band', [KnownValue('Album'), KnownValue('Album 2')]),
      ]);
      const song = 'Band/Album/Song';
      put('$song/v.rpp', project(media: [r'Media\a.wav']));
      put('$song/Media/a.wav', 'a');
      put('$song/Media/b.wav', 'b');
      put('Band/Loose/v.rpp', project());
      put('Band/Album 2/Song/v.rpp', project());
      index.update(lib, await scan(storage, lib));
      await index.hashPending(lib.id, (path) async => 'h');
      expect(
        index.issues(kind: ReportKind.titleTooHigh).single.item.path,
        'Band/Loose',
      );

      File(p.join(root.path, 'Band', 'Album', 'Song', 'Media', 'b.wav'))
          .deleteSync();
      put('$song/Media/c.wav', 'c');
      await rescanAndCompare(lib, song);
      expect(index.hashOf(lib.id, '$song/Media/a.wav'), 'h');
      expect(index.hashOf(lib.id, '$song/Media/c.wav'), isNull);
      expect(index.hashOf(lib.id, 'Band/Album 2/Song/v.rpp'), 'h');

      put('Band/Loose/w.rpp', project());
      await rescanAndCompare(lib, 'Band/Loose');
      expect(
        index.issues(kind: ReportKind.titleTooHigh).single.item.path,
        'Band/Loose',
      );
    });

    test('drops a folder that is no longer a title', () async {
      final lib = library();
      const song = 'Band/Album/Song';
      put('$song/v.rpp', project());
      put('$song/mix/deep.rpp', project());
      put('Band/Album/Other/v.rpp', project());
      index.update(lib, await scan(storage, lib));
      final previous = index.titles().firstWhere((t) => t.path == song);

      File(p.join(root.path, 'Band', 'Album', 'Song', 'v.rpp')).deleteSync();
      File(p.join(root.path, 'Band', 'Album', 'Song', 'mix', 'deep.rpp'))
          .deleteSync();
      index.updateTitle(
        lib,
        song,
        await scanTitle(
          storage,
          lib,
          previous,
          stored: index.scanResult(lib.id)!,
        ),
      );

      expect(index.titles().map((t) => t.path), ['Band/Album/Other']);
      expect(index.scanResult(lib.id)!.nodes.keys, isNot(contains(song)));
      expect(index.issues().map((i) => (i.kind, i.item.path)), [
        (ReportKind.orphanNode, '$song/.node.json'),
      ]);
      expect(
        index.files(lib.id).map((f) => f.path),
        isNot(contains('$song/v.rpp')),
      );
    });

    test('stores the library, keeps the journal position', () {
      final lib = library();
      const position = (folder: '.migration/2026-11-12_000000_000', line: 7);
      index.update(lib, const ScanResult(journalPosition: position));
      expect(index.storedTitle(lib.id, 'A/B/C'), isNull);
      expect(index.storedTitle(LibraryId.generate(), 'A/B/C'), isNull);
      final changed = lib.withKnownValues(const [KnownValue('A')]);

      index.updateTitle(changed, 'A/B/C', (
        title: null,
        node: null,
        stamps: const {},
        subprojects: const {},
        issues: const Report(),
        corrupted: const [],
        orphanNodes: const [],
      ));

      expect(index.libraries().single.knownValues, changed.knownValues);
      expect(index.journalPosition(lib.id), position);
    });

    test('changes nothing when it fails', () {
      final lib = library();
      final song = title(lib.id, 'A', 'B', 'C', versions: [version('v.rpp')]);
      index.update(lib, ScanResult(titles: [song]));
      final before = describe(index, lib.id);
      // A version written twice breaks the key of the versions table.
      final twice = Title(
        id: song.id,
        libraryId: lib.id,
        path: song.path,
        tags: song.tags,
        versions: [version('v.rpp'), version('v.rpp')],
      );

      expect(
        () => index.updateTitle(lib, song.path, (
          title: twice,
          node: null,
          stamps: const {},
          subprojects: const {},
          issues: const Report(),
          corrupted: const [],
          orphanNodes: const [],
        )),
        throwsA(isA<SqliteException>()),
      );
      expect(describe(index, lib.id), before);
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
