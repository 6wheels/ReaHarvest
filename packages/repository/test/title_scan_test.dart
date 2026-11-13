import 'dart:io';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

/// Project with a record path, a render target, [media] references and,
/// when given, a version [id].
String project(
  List<String> media, {
  String record = 'Media',
  String render = r'Renders\mix.wav',
  VersionId? id,
}) {
  final text = [
    '<REAPER_PROJECT 0.1 "7.84/win64" 0',
    '  RECORD_PATH "$record" ""',
    '  RENDER_FILE "$render"',
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
  ].join('\n');
  return id == null
      ? text
      : setExtState(
          text,
          VersionMetadata.section,
          VersionMetadata(id: id).toExtState(),
        );
}

bool _below(String path, String dir) => dir.isEmpty || path.startsWith('$dir/');

/// Comparable form of [title].
Object? describe(Title? title) => title == null
    ? null
    : {
        'id': title.id,
        'path': title.path,
        'tags': title.tags,
        'status': title.status,
        'versionStatuses': title.versionStatuses,
        'versions': [
          for (final v in title.versions)
            [
              v.fileName,
              v.size,
              v.modified,
              v.metadata?.id,
              v.metadata?.label,
              v.metadata?.owner,
              v.tempo,
              v.length,
              v.trackCount,
              v.itemCount,
              v.plugins,
              v.media,
              v.recordPath,
              v.renderFile,
            ],
        ],
      };

/// Checks that [scan] holds what [full] found in the folder [dir], its
/// duplicated version identifiers and level issues aside.
void expectAsFullScan(TitleScan scan, ScanResult full, String dir) {
  expect(
    describe(scan.title),
    describe(full.titles.where((t) => t.path == dir).firstOrNull),
  );
  expect(scan.node?.id, full.nodes[dir]?.id);
  expect(scan.stamps, {
    for (final MapEntry(:key, :value) in full.stamps.entries)
      if (_below(key, dir)) key: value,
  });
  expect(scan.subprojects, {
    for (final MapEntry(:key, :value) in full.subprojects.entries)
      if (_below(key, dir)) key: value,
  });
  expect(scan.issues.items, {
    for (final (kind, items) in full.issues.sections)
      if (kind != ReportKind.duplicateVersionId &&
          items.any((i) => _below(i.path, dir)))
        kind: [
          for (final i in items)
            if (_below(i.path, dir)) i,
        ],
  });
  expect(scan.corrupted, full.corrupted.where((p) => _below(p, dir)));
  expect(scan.orphanNodes, full.orphanNodes.where((p) => _below(p, dir)));
}

void main() {
  late MemoryStorage storage;

  Library library(Layout? layout) => Library(
    id: LibraryId.generate(),
    mode: LibraryMode.local,
    layout: layout,
  );

  Title titleAt(ScanResult result, String path) =>
      result.titles.singleWhere((t) => t.path == path);

  setUp(() => storage = MemoryStorage());

  group('scanTitle', () {
    const song = 'band/album/song';
    const other = 'band/album/other';
    final shared = VersionId.generate();

    /// A layout library: [song] with versions, pool, subproject, issues and
    /// a corrupted project; [other] sharing a version id and a media file.
    void fill() {
      storage
        ..put('$song/v1.rpp', project([r'Media\a.wav'], id: shared))
        ..put(
          '$song/v2.rpp',
          project([
            r'Media\a.wav',
            r'..\other\Media\b.wav',
            r'..\other\Media\none.wav',
            r'Media\gone.wav',
            r'C:\Users\someone\c.wav',
            r'..\..\..\..\d.wav',
          ], record: 'audio'),
        )
        ..put('$song/bad.rpp', '<REAPER_PROJECT  <TRACK')
        ..put('$song/Media/a.wav', 'a')
        ..put('$song/Media/sub.rpp', project([r'a.wav', r'..\..\x\y.wav']))
        ..put('$song/Media/deep/x.rpp', project([]))
        ..put('$song/mix/deep.rpp', project([]))
        ..put('$song/mix/.node.json', '{"nodeId":"N","level":"title"}')
        ..put('$song/.trash/old.rpp', project([]))
        ..put('$song/notes.txt', 'n')
        ..put('$other/v1.rpp', project([r'Media\b.wav'], id: shared))
        ..put('$other/Media/b.wav', 'b');
    }

    test('finds in one title what the full scan finds there', () async {
      final lib = library(Layout.classic());
      fill();
      final first = await scan(storage, lib);
      storage.log.clear();
      // Changes made by version actions: a project, the node file.
      storage.put(
        '$song/v2.rpp',
        project([r'Media\a.wav'], id: VersionId.generate()),
        modified: DateTime(2027),
      );
      await setVersionStatus(storage, song, shared, 'mixing');
      storage
        ..listed.clear()
        ..stats.clear()
        ..reads.clear();

      final result = await scanTitle(
        storage,
        lib,
        titleAt(first, song),
        stored: first,
      );

      // Only its folder listed; one stat per reference leaving it; only
      // the changed files and the corrupted project read again.
      expect(storage.listed, ['$song/**']);
      expect(storage.stats, ['band/album/x/y.wav']);
      expect(
        storage.reads,
        unorderedEquals(['$song/v2.rpp', '$song/.node.json', '$song/bad.rpp']),
      );
      expect(storage.log, ['write $song/.node.json']);
      expectAsFullScan(result, await scan(storage, lib, previous: first), song);
      expect(result.title!.statusOf(result.title!.versions.first), 'mixing');
      expect(result.corrupted, ['$song/bad.rpp']);
      expect(result.orphanNodes, ['$song/mix/.node.json']);
      expect(
        result.issues.items[ReportKind.projectTooDeep]!.map((i) => i.path),
        ['$song/mix/deep.rpp'],
      );
    });

    test('checks references leaving the title with one stat each', () async {
      final lib = library(Layout.classic());
      fill();
      final first = await scan(storage, lib);
      storage.stats.clear();

      final result = await scanTitle(
        storage,
        lib,
        titleAt(first, song),
        stored: first,
      );

      expect(
        storage.stats,
        unorderedEquals([
          'band/album/other/Media/b.wav',
          'band/album/other/Media/none.wav',
          'band/album/x/y.wav',
        ]),
      );
      expect(result.issues.items[ReportKind.mediaOutsidePool], [
        const ReportItem('$song/v2.rpp', r'..\other\Media\b.wav'),
      ]);
      expect(result.issues.items[ReportKind.missingMedia], [
        const ReportItem('$song/Media/sub.rpp', r'..\..\x\y.wav'),
        const ReportItem(
          '$song/v2.rpp',
          '..\\other\\Media\\none.wav\nMedia\\gone.wav',
        ),
      ]);
      expectAsFullScan(result, first, song);
    });

    test('reads every file without a stored scan', () async {
      final lib = library(Layout.classic());
      fill();
      final first = await scan(storage, lib);
      storage.reads.clear();

      final result = await scanTitle(storage, lib, titleAt(first, song));

      expect(storage.reads, contains('$song/v1.rpp'));
      expectAsFullScan(result, first, song);
    });

    test('keeps the tags of a title placed too high', () async {
      final lib = library(Layout.classic())
          .withKnownValues(const [KnownValue('band')]);
      storage
        ..put('band/loose/v.rpp', project([r'Media\a.wav']))
        ..put('band/loose/Media/a.wav', 'a')
        ..put('band/loose/sub/deep.rpp', project([]));
      final first = await scan(storage, lib);
      final loose = titleAt(first, 'band/loose');
      expect(loose.tags['album'], Layout.unassigned);

      final result = await scanTitle(storage, lib, loose, stored: first);

      expect(result.title!.tags, loose.tags);
      expect(result.issues.items, isEmpty);
      expectAsFullScan(result, first, 'band/loose');
    });

    test('lists the nested versions of a free tree title', () async {
      final lib = library(null);
      storage
        ..put('a/v.rpp', project([r'C:\x.wav']))
        ..put('a/sub/w.rpp', project([]))
        ..put('a/sub/.node.json', '{"nodeId":"N","level":"x"}')
        ..put('b/v.rpp', project([]));
      final first = await scan(storage, lib);
      storage.reads.clear();

      final result = await scanTitle(
        storage,
        lib,
        titleAt(first, 'a'),
        stored: first,
      );

      expect(result.title!.versions.map((v) => v.fileName), [
        'sub/w.rpp',
        'v.rpp',
      ]);
      expect(result.issues.items, isEmpty);
      expect(storage.reads, isEmpty);
      expectAsFullScan(result, first, 'a');
    });

    test('scans a free tree title at the root', () async {
      final lib = library(null);
      storage
        ..put('v.rpp', project([]))
        ..put('a/w.rpp', project([]));
      final first = await scan(storage, lib);
      storage.listed.clear();

      final result = await scanTitle(storage, lib, titleAt(first, ''));

      expect(storage.listed, ['/**']);
      expectAsFullScan(result, first, '');
    });

    group('failures', () {
      test('reports a corrupted node file, no longer a title', () async {
        final lib = library(Layout.classic());
        fill();
        final first = await scan(storage, lib);
        storage.put('$song/.node.json', 'not json');

        final result = await scanTitle(
          storage,
          lib,
          titleAt(first, song),
          stored: first,
        );

        expect(result.title, isNull);
        expect(result.node, isNull);
        expect(result.corrupted, ['$song/.node.json']);
        expectAsFullScan(
          result,
          await scan(storage, lib, previous: first),
          song,
        );
      });

      test('writes no node file when it is missing', () async {
        final lib = library(Layout.classic());
        fill();
        final first = await scan(storage, lib);
        storage.files.remove('$song/.node.json');
        storage.log.clear();

        final result = await scanTitle(
          storage,
          lib,
          titleAt(first, song),
          stored: first,
        );

        expect(result.title, isNull);
        expect(storage.log, isEmpty);
      });

      test('gives no title once its last project is purged', () async {
        final lib = library(Layout.classic());
        storage.put('$song/v1.rpp', project([]));
        final first = await scan(storage, lib);
        storage.files.remove('$song/v1.rpp');

        final result = await scanTitle(
          storage,
          lib,
          titleAt(first, song),
          stored: first,
        );

        expect(result.title, isNull);
        expect(result.orphanNodes, ['$song/.node.json']);
        expectAsFullScan(
          result,
          await scan(storage, lib, previous: first),
          song,
        );
      });

      test('gives no free tree title without a project in it', () async {
        final lib = library(null);
        storage
          ..put('a/v.rpp', project([]))
          ..put('a/sub/w.rpp', project([]));
        final first = await scan(storage, lib);
        storage.files.remove('a/v.rpp');

        final result = await scanTitle(
          storage,
          lib,
          titleAt(first, 'a'),
          stored: first,
        );

        expect(result.title, isNull);
        expect(result.orphanNodes, ['a/.node.json']);
      });

      test('lets a failed listing through', () async {
        final lib = library(Layout.classic());
        storage.put('$song/v1.rpp', project([]));
        final first = await scan(storage, lib);

        await expectLater(
          scanTitle(_FailingStorage(storage), lib, titleAt(first, song)),
          throwsA(isA<InjectedFailure>()),
        );
      });
    });

    test('runs in an isolate', () async {
      final root = Directory.systemTemp.createTempSync('reaharvest_title_');
      addTearDown(() => root.deleteSync(recursive: true));
      final mounted = MountedFolderStorage(root.path);
      final lib = library(Layout.classic());
      await scaffoldTitle(mounted, song, 'title');
      await createVersion(
        mounted,
        song,
        'v1.rpp',
        VersionMetadata(id: VersionId.generate()),
      );
      final first = await scan(mounted, lib);

      final result = await scanTitleFolder(
        root.path,
        lib,
        titleAt(first, song),
        stored: first,
      );

      expectAsFullScan(result, first, song);
    });
  });
}

/// Storage whose listing fails.
final class _FailingStorage implements RepositoryStorage {
  _FailingStorage(this.inner);

  final MemoryStorage inner;

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) =>
      throw const InjectedFailure('list');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
