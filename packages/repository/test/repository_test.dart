import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_repository/src/windows_hidden.dart' as windows;
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const fixtures = '../../test/fixtures';

/// Issues about the media, record path and render target of the projects
/// (SPEC §4.3): left out of the layout tests, the fixtures not following
/// these conventions.
const mediaKinds = {
  ReportKind.mediaOutsidePool,
  ReportKind.missingMedia,
  ReportKind.externalMedia,
  ReportKind.recordPathNotMedia,
  ReportKind.renderFileForm,
};

/// Issues of [result] other than [mediaKinds].
Map<ReportKind, List<ReportItem>> layoutIssues(ScanResult result) => {
  for (final MapEntry(:key, :value) in result.issues.items.entries)
    if (!mediaKinds.contains(key)) key: value,
};

/// Paths of the issues of [result] other than [mediaKinds], by kind then
/// path.
List<String> issuePaths(ScanResult result) => [
  for (final (kind, items) in result.issues.sections)
    if (!mediaKinds.contains(kind)) ...items.map((i) => i.path),
];

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
  late Directory root;
  late MountedFolderStorage storage;

  final unknown = File('$fixtures/tracks.rpp').readAsStringSync();
  final adoptedId = VersionId.generate();
  final adopted = setExtState(
    unknown,
    VersionMetadata.section,
    VersionMetadata(
      id: adoptedId,
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

  /// The version folder [folder] of a layout title, its project named
  /// [file] (`<folder>.RPP` by default).
  Version version(String folder, [String? file]) => Version(
    fileName: '$folder/${file ?? '$folder.RPP'}',
    folder: folder,
    modified: DateTime(2026),
    size: 0,
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

    test('appends to a file, created with its folders', () async {
      await storage.append('a/b/log.jsonl', utf8.encode('one\n'));
      await storage.append('a/b/log.jsonl', utf8.encode('two\n'));
      expect(
        File(p.join(root.path, 'a', 'b', 'log.jsonl')).readAsStringSync(),
        'one\ntwo\n',
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
        await storage.append('.migration/s/journal.jsonl', [10]);

        expect(hidden('.library.json'), isTrue);
        expect(hidden('a/.node.json'), isTrue);
        expect(hidden('.collab'), isTrue);
        expect(hidden('a/.trash'), isTrue);
        expect(hidden('a'), isFalse);
        expect(hidden('.collab/m1'), isFalse);
        expect(hidden('a/.trash/b.rpp'), isFalse);
        expect(hidden('.migration'), isTrue);
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
      put('band/album/song/v1/v1.rpp', adopted);
      put('band/album/song/v2/v2.RPP', unknown);
      put('band/album/song/v2/v2.rpp-bak', unknown);
      put('band/album/song/v2/Backups/v2-2024-01-02_1030.rpp', unknown);
      put('band/album/song/v2/.history/old.rpp', unknown);
      put('band/album/song/v2/Media/a.wav');
      put('band/album/song/v2/Media/sub.rpp', unknown);
      put('band/album/song/v2/old-takes/notes.txt');
      put('band/album/song/v2/old-takes/take.rpp', unknown);
      put('band/album/song/Alice/mix/a.rpp', unknown);
      put('band/album/song/Assets/notes.rpp', unknown);
      put('band/album/song/.trash/old/old.rpp', unknown);
      // Left to the title-oriented scan (#147): neither a version nor
      // reported yet.
      put('band/album/song/loose.rpp', unknown);
      put('band/_Unassigned/other/v1/v1.rpp', unknown);
      put('band/_Unassigned/other/copy/copy.rpp', adopted);
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
      expect(song.versions.map((v) => v.fileName), ['v1/v1.rpp', 'v2/v2.RPP']);
      expect(song.versions.map((v) => v.folder), ['v1', 'v2']);
      expect(song.versions[0].isAdopted, isTrue);
      expect(song.versions[1].isAdopted, isFalse);
      expect(layoutIssues(result), {
        ReportKind.projectTooDeep: [
          for (final path in ['Alice/mix/a.rpp', 'v2/old-takes/take.rpp'])
            ReportItem.misplaced(
              'band/album/song/$path',
              level: lib.layout!.leaf,
              target: 'band/album/song',
            ),
        ],
        ReportKind.projectTooShallow: [
          for (final path in ['band/loose.rpp', 'root.rpp'])
            ReportItem.misplaced(path, level: lib.layout!.leaf),
        ],
        ReportKind.duplicateVersionId: [
          for (final path in [
            'band/_Unassigned/other/copy/copy.rpp',
            'band/album/song/v1/v1.rpp',
          ])
            ReportItem(path, adoptedId),
        ],
      });
      expect(result.toAdopt.map((e) => '${e.$1.path}/${e.$2.fileName}'), [
        'band/_Unassigned/other/v1/v1.rpp',
        'band/album/song/v2/v2.RPP',
      ]);
    });

    test('sizes a version by every file of its folder, by kind', () async {
      final lib = library(Layout.classic());
      const project = blankProject;
      put('band/album/song/v1/v1.rpp', project);
      put('band/album/song/v1/v1.rpp-bak', 'b' * 7);
      put('band/album/song/v1/Media/a.wav', 'a' * 100);
      put('band/album/song/v1/Media/a.wav.reapeaks', 'x' * 1000);
      put('band/album/song/v1/Renders/mix.wav', 'r' * 30);
      put('band/album/song/v1/.history/v1 old.rpp', 'h' * 2000);
      put('band/album/song/v1/Backups/v1-2026.rpp', 'k' * 40);
      put('band/album/song/v1/notes.txt', 'n' * 3);
      put('band/album/song/v2/v2.rpp', project);
      put('band/album/song/Assets/score.pdf', 'x' * 1000);
      final counting = CountingStorage(storage);

      final first = await scan(counting, lib);
      final v1 = first.titles.single.versions.first;
      expect(v1.sizes, {
        SizeCategory.project: project.length,
        SizeCategory.reaperBackups: 47,
        SizeCategory.media: 1100,
        SizeCategory.renders: 30,
        SizeCategory.history: 2000,
        SizeCategory.other: 3,
      });
      expect(v1.size, project.length + 3180);
      expect(first.titles.single.versions.last.sizes, {
        SizeCategory.project: project.length,
      });

      // A backup point added: the size follows, the project is not read
      // again.
      put('band/album/song/v1/.history/v1 new.rpp', 'h' * 5);
      counting.reads.clear();
      final second = await scan(counting, lib, previous: first);
      expect(counting.reads, isEmpty);
      final again = second.titles.single.versions.first;
      expect(again.sizes[SizeCategory.history], 2005);
      expect(again.size, project.length + 3185);
    });

    test('a reserved folder of a title is never a version', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1/v1.rpp', unknown);
      // Pool of the former layout, renders, REAPER backups at title level.
      put('band/album/song/Media/sub.rpp', unknown);
      put('band/album/song/renders/r.rpp', unknown);
      put('band/album/song/Backups/b.rpp', unknown);

      final result = await scan(storage, lib);

      expect(result.titles.single.versions.map((v) => v.folder), ['v1']);
      expect(issuePaths(result), isEmpty);
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
      put('band/album/song/v1/v1.rpp', unknown);

      final result = await scan(storage, lib);

      expect(result.titles, isEmpty);
      expect(layoutIssues(result), {
        ReportKind.outsideLayout: [
          const ReportItem.misplaced('band/album', level: LayoutLevel('album')),
        ],
      });
      expect(result.corrupted, isEmpty);
    });

    test('reports corrupted node and project files', () async {
      final lib = library(Layout.classic());
      put('other/broken/.node.json', 'not json');
      put('other/broken/song/v1/v1.rpp', unknown);
      put('other/shape/.node.json', '["array"]');
      put('other/shape/song/v1/v1.rpp', unknown);
      put('band/album/song/v1/v1.rpp', unknown);
      put('band/album/song/bad/bad.rpp', r'<REAPER_PROJECT  <TRACK');

      final result = await scan(storage, lib);

      expect(result.titles.single.versions.map((v) => v.fileName), [
        'v1/v1.rpp',
      ]);
      expect(issuePaths(result), isEmpty);
      expect(result.corrupted, [
        'band/album/song/bad/bad.rpp',
        'other/broken/.node.json',
        'other/shape/.node.json',
      ]);
    });

    test('folders without projects are not nodes (#54)', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1/v1.rpp', unknown);
      put('band/album/song/Assets/old/old.rpp', unknown);
      put('band/album/other/Assets/old/old.rpp', unknown);
      put('band/album/other/v1/Media/sub.rpp', unknown);
      put('band/audio-files/kick.wav', 'x');
      put('band/render/sub/mix.wav', 'x');
      put('band/album/empty/notes.txt', 'x');
      // Misplaced project with its own media folder at the album level.
      put('proj/proj.rpp', unknown);
      put('proj/Media/peaks/kick.reapeaks', 'x');
      put('proj/Media/peaks/song/stray.rpp', unknown);

      final result = await scan(storage, lib);

      expect(result.titles.map((t) => t.path), ['band/album/song']);
      expect(result.nodes.keys.toSet(), {
        'band',
        'band/album',
        'band/album/song',
        'proj',
      });
      expect(issuePaths(result), ['proj/proj.rpp']);
      for (final dir in [
        'band/audio-files',
        'band/render',
        'band/render/sub',
        'band/album/empty',
        'proj/Media',
        'proj/Media/peaks',
        'proj/Media/peaks/song',
      ]) {
        expect(exists('$dir/.node.json'), isFalse, reason: dir);
      }
      expect(exists('band/album/empty/Media'), isFalse);
    });

    test('a title whose versions are all in its trash stays a title', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1/v1.rpp', unknown);
      final first = await scan(storage, lib);
      final id = first.titles.single.id;
      await deleteVersion(
        storage,
        'band/album/song',
        first.titles.single.versions.single,
      );

      final second = await scan(storage, lib, previous: first);

      expect(second.titles.single.id, id);
      expect(second.titles.single.versions, isEmpty);
      expect(second.orphanNodes, isEmpty);

      await purgeTrash(storage, 'band/album/song', [
        'band/album/song/.trash/v1',
      ]);
      final third = await scan(storage, lib, previous: second);
      expect(third.titles, isEmpty);
      expect(third.orphanNodes, [
        'band/.node.json',
        'band/album/.node.json',
        'band/album/song/.node.json',
      ]);
      expect(exists('band/album/song/.node.json'), isTrue);
    });

    test('a title whose versions have backups only stays a title', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1/.history/v1 2026-01-01 000000.rpp', unknown);
      put('band/album/deep/v1/sub/.history/v1.rpp', unknown);

      final result = await scan(storage, lib);

      expect(result.titles.map((t) => t.path), ['band/album/song']);
      expect(result.titles.single.versions, isEmpty);
    });

    test('reports node files of folders that are not nodes', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1/v1.rpp', unknown);
      put('band/audio-files/.node.json', '{"nodeId": "01X", "level": "album"}');
      put('band/audio-files/kick.wav', 'x');

      final result = await scan(storage, lib);

      expect(result.orphanNodes, ['band/audio-files/.node.json']);
      expect(result.corrupted, isEmpty);
      expect(result.nodes.containsKey('band/audio-files'), isFalse);
      expect(exists('band/audio-files/.node.json'), isTrue);
    });

    test('is incremental by size and mtime', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1/v1.rpp', adopted);
      put('band/album/song/v2/v2.rpp', unknown);
      final counting = CountingStorage(storage);

      final first = await scan(counting, lib);
      counting.reads.clear();
      final second = await scan(counting, lib, previous: first);
      expect(counting.reads, isEmpty);
      expect(
        second.titles.single.versions[0].metadata?.id,
        first.titles.single.versions[0].metadata?.id,
      );

      put('band/album/song/v2/v2.rpp', adopted);
      final third = await scan(counting, lib, previous: second);
      expect(counting.reads, ['band/album/song/v2/v2.rpp']);
      expect(third.toAdopt, isEmpty);
    });

    test('reports media, record path and render target issues', () async {
      final lib = library(Layout.classic());
      String project(String record, String render, List<String> media) => [
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
      // Paths resolve from the version folder.
      put('band/album/song/good/Media/a.wav', 'a');
      put('band/album/song/bad/Media/a.wav', 'a');
      put('band/album/song/bad/audio-files/b.wav', 'b');
      put(
        'band/album/song/good/good.rpp',
        project('Media', r'Renders\mix.wav', [r'Media\a.wav', r'media\A.WAV']),
      );
      put(
        'band/album/song/bad/bad.rpp',
        project('audio-files', r'.\render', [
          r'Media\a.wav',
          r'.\audio-files\b.wav',
          r'..\good\Media\a.wav',
          r'Media\gone.wav',
          r'C:\Users\someone\c.wav',
          r'..\..\..\..\..\d.wav',
        ]),
      );
      put('band/album/song/blank/blank.rpp', project('', '', []));

      final counting = CountingStorage(storage);
      final first = await scan(counting, lib);

      const bad = 'band/album/song/bad/bad.rpp';
      const blank = 'band/album/song/blank/blank.rpp';
      final expected = {
        ReportKind.mediaOutsidePool: [
          const ReportItem(
            bad,
            '.\\audio-files\\b.wav\n..\\good\\Media\\a.wav',
          ),
        ],
        ReportKind.missingMedia: [const ReportItem(bad, r'Media\gone.wav')],
        ReportKind.externalMedia: [
          const ReportItem(
            bad,
            'C:\\Users\\someone\\c.wav\n..\\..\\..\\..\\..\\d.wav',
          ),
        ],
        ReportKind.recordPathNotMedia: [
          const ReportItem(bad, 'audio-files'),
          const ReportItem(blank, ''),
        ],
        ReportKind.renderFileForm: [
          const ReportItem(bad, r'.\render'),
          const ReportItem(blank, ''),
        ],
      };
      expect(first.issues.items, expected);

      // Unchanged projects are not read again: their references come from
      // the previous scan, checked against the files present now.
      put('band/album/song/bad/Media/gone.wav', 'g');
      counting.reads.clear();
      final second = await scan(counting, lib, previous: first);
      expect(counting.reads, isEmpty);
      expect(second.issues.items[ReportKind.missingMedia], isNull);
      expect(
        second.issues.items[ReportKind.mediaOutsidePool],
        expected[ReportKind.mediaOutsidePool],
      );
    });

    test('runs in an isolate', () async {
      put('band/album/song/v1/v1.rpp', adopted);
      final result = await scanFolder(root.path, library(Layout.classic()));
      expect(result.titles.single.versions.single.isAdopted, isTrue);
    });
  });

  group('statuses', () {
    test('are written to the title node file and read by the scan', () async {
      final lib = library(Layout.classic());
      put('band/album/song/v1/v1.rpp', adopted);
      final first = await scan(storage, lib);
      final versionId = first.titles.single.versions.single.metadata!.id;

      await setVersionStatus(storage, 'band/album/song', versionId, 'done');
      final saved = jsonDecode(
        File(p.join(root.path, 'band', 'album', 'song', '.node.json'))
            .readAsStringSync(),
      );
      expect(saved.keys, isNot(contains('status')));
      expect(saved['versionStatuses'], {versionId: 'done'});
      expect(saved['nodeId'], first.titles.single.id);

      final second = await scan(storage, lib, previous: first);
      final title = second.titles.single;
      // The title status is derived from its versions (SPEC §5.9).
      expect(title.status, 'done');
      expect(title.statusOf(title.versions.single), 'done');

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

      final title = (await scan(storage, library(null))).titles.single;
      expect(title.status, isNull);
      expect(title.versionStatuses, {gone: 'idea'});
      expect(title.statusOf(title.versions.single), isNull);
    });

    test('require an existing node file', () {
      expect(
        setVersionStatus(storage, 'missing', 'v', 'idea'),
        throwsA(isA<StateError>()),
      );
    });

    test('reject an invalid shape', () {
      for (final key in ['versionStatuses', 'versionLabels', 'versionOwners']) {
        expect(
          () => NodeFile.fromJson({
            'nodeId': newUlid(),
            'level': 'title',
            key: {'v': 1},
          }),
          throwsFormatException,
          reason: key,
        );
      }
      for (final tags in [
        'live',
        1,
        ['live', 2],
      ]) {
        expect(
          () => NodeFile.fromJson({
            'nodeId': newUlid(),
            'level': 'title',
            'tags': tags,
          }),
          throwsFormatException,
          reason: '$tags',
        );
      }
    });

    test('keep the tags of a title, none by default', () {
      final id = NodeId.generate();
      final bare = NodeFile(id, 'title');
      expect(bare.tags, isEmpty);
      expect(bare.toJson().keys, isNot(contains('tags')));
      final tagged = NodeFile.fromJson({
        'nodeId': id,
        'level': 'title',
        'tags': ['live', 'rehearsal'],
      });
      expect(tagged.tags, ['live', 'rehearsal']);
      expect(tagged.toJson()['tags'], ['live', 'rehearsal']);
      expect(tagged.withVersionStatus('V', 'idea').tags, ['live', 'rehearsal']);
      expect(
        tagged.mergedWith(NodeFile(id, 'title', tags: ['solo', 'live'])).tags,
        ['live', 'rehearsal', 'solo'],
      );
    });
  });

  group('version labels and owners', () {
    const title = 'band/album/song';
    const file = '$title/v1/v1.rpp';

    File project() => File(p.joinAll([root.path, ...file.split('/')]));

    Map<String, Object?> node() => (jsonDecode(
      File(p.joinAll([root.path, ...title.split('/'), '.node.json']))
          .readAsStringSync(),
    ) as Map).cast();

    test('are edited in the node file, the project left untouched', () async {
      final lib = library(Layout.classic());
      put(file, adopted);
      final date = DateTime(2025, 1, 2);
      project().setLastModifiedSync(date);
      final first = await scan(storage, lib);
      final bytes = project().readAsBytesSync();
      final owner = MemberId.generate();

      await setVersionLabel(storage, title, adoptedId, 'bridge');
      await setVersionOwner(storage, title, adoptedId, owner);

      expect(project().readAsBytesSync(), bytes);
      expect(project().lastModifiedSync(), date);
      expect(node()['versionLabels'], {adoptedId: 'bridge'});
      expect(node()['versionOwners'], {adoptedId: owner});
      // Unchanged project, changed node file: read again from the node.
      final second = await scan(storage, lib, previous: first);
      final m = second.titles.single.versions.single.metadata!;
      expect((m.id, m.label, m.owner), (adoptedId, 'bridge', owner));

      await setVersionOwner(storage, title, adoptedId, null);
      await setVersionLabel(storage, title, adoptedId, '');
      expect(node().keys, isNot(contains('versionOwners')));
      expect(node().keys, isNot(contains('versionLabels')));
      final third = await scan(storage, lib, previous: second);
      final cleared = third.titles.single.versions.single.metadata!;
      expect((cleared.label, cleared.owner), ('v1', null));
    });

    test('fall back to the folder name, without owner', () async {
      put(file, adopted);
      final m = (await scan(
        storage,
        library(Layout.classic()),
      )).titles.single.versions.single.metadata!;
      expect((m.id, m.label, m.owner), (adoptedId, 'v1', null));
      expect(node().keys, isNot(contains('versionLabels')));
    });

    test('ignore and keep OWNER and LABEL keys of a project', () async {
      final legacy = setExtState(unknown, VersionMetadata.section, {
        'VERSIONID': adoptedId,
        'OWNER': 'M',
        'LABEL': 'old label',
      });
      put(file, legacy);
      final lib = library(Layout.classic());
      await scan(storage, lib);

      await setVersionLabel(storage, title, adoptedId, 'new');
      final m = (await scan(
        storage,
        lib,
      )).titles.single.versions.single.metadata!;
      expect((m.id, m.label, m.owner), (adoptedId, 'new', null));
      expect(project().readAsStringSync(), legacy);

      final copy = await separateDuplicateVersion(
        storage,
        title,
        'v1/v1.rpp',
        label: 'new',
      );
      final values = RppProject.parse(project().readAsStringSync())
          .extState(VersionMetadata.section);
      expect(values, {'VERSIONID': copy, 'OWNER': 'M', 'LABEL': 'old label'});
    });

    test('require an existing node file', () {
      expect(
        setVersionLabel(storage, 'missing', adoptedId, 'x'),
        throwsA(isA<StateError>()),
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
      expect(issuePaths(result), isEmpty);
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
    test('scan reads tempo, counts and plugins of layout versions', () async {
      put('band/album/song/v1/v1.rpp', unknown);
      final result = await scan(storage, library(Layout.classic()));
      final v = result.titles.single.versions.single;
      expect(v.tempo, 128);
      expect(v.sampleRate, RppProject.parse(unknown).sampleRate);
      expect(v.sampleRate, isNotNull);
      expect((v.trackCount, v.itemCount), (13, 6));
      expect(v.length, greaterThan(0));
      expect(
        v.plugins.map((p) => p.identifier),
        containsAll(['reasynth.dll', 'reaeq.dll']),
      );
    });

    test('rescan reads again the files without their stamp', () async {
      put('band/album/song/v1/v1.rpp', unknown);
      final lib = library(Layout.classic());
      final first = await scan(storage, lib);
      final path = p.joinAll([
        root.path,
        ...'band/album/song/v1/v1.rpp'.split('/'),
      ]);
      final date = File(path).lastModifiedSync();
      // Same size and date, other content: a migration rewrite.
      File(path)
        ..writeAsStringSync(unknown.replaceFirst('TEMPO 128', 'TEMPO 129'))
        ..setLastModifiedSync(date);

      final stale = await scan(storage, lib, previous: first);
      final fresh = await scan(
        storage,
        lib,
        previous: first.withoutStamps({'band/album/song/v1/v1.rpp'}),
      );

      expect(stale.titles.single.versions.single.tempo, 128);
      expect(fresh.titles.single.versions.single.tempo, 129);
    });

    test('duplicates share a version id across titles', () async {
      put('band/album/song/v1/v1.rpp', adopted);
      put('band/album/song/copy/copy.rpp', adopted);
      put('band/album/other/v1/v1.rpp', unknown);
      final result = await scan(storage, library(Layout.classic()));
      final duplicates = duplicateVersions(result.titles);
      expect(duplicates.values.single.map((d) => d.$2.fileName), [
        'copy/copy.rpp',
        'v1/v1.rpp',
      ]);
    });
  });

  group('scaffolding', () {
    bool dir(String path) =>
        Directory(p.joinAll([root.path, ...path.split('/')])).existsSync();

    /// A folder not organized yet: a title, a member subfolder in it, a
    /// member folder standing at the title depth, loose projects.
    MemoryStorage misorganized() => MemoryStorage()
      ..put('band/album/song/v1/v1.rpp', adopted)
      ..put('band/album/song/Alice/mix/a.rpp', unknown)
      ..put('band/single/Bob/take.rpp', unknown)
      ..put('band/loose.rpp', unknown)
      ..put('demo.rpp', unknown);

    test('scan creates no folder, only node files', () async {
      final memory = misorganized();
      final before = {...memory.dirs};

      final result = await scan(memory, library(Layout.classic()));

      expect(result.titles.map((t) => t.path), [
        'band/album/song',
        'band/single/Bob',
      ]);
      expect(memory.dirs, before);
      expect(memory.log, isNotEmpty);
      expect(memory.log.where((op) => !op.endsWith('/$nodeFileName')), isEmpty);
      expect(memory.log.every((op) => op.startsWith('write ')), isTrue);
    });

    test('scan without writeNodes writes nothing', () async {
      final memory = misorganized()
        ..put(
          'band/album/old/$nodeFileName',
          '{"nodeId":"${newUlid()}","level":"title"}',
        )
        ..put('band/album/old/v1.rpp', unknown);

      final result = await scan(
        memory,
        library(Layout.classic()),
        writeNodes: false,
      );

      expect(memory.log, isEmpty);
      expect(memory.changes, 0);
      // Only a folder whose node file and parents' node files exist.
      expect(result.titles, isEmpty);
      expect(result.corrupted, isEmpty);
    });

    test('free tree scan without writeNodes writes nothing', () async {
      final memory = MemoryStorage()
        ..put('songs/demo/v1.rpp', unknown)
        ..put(
          'songs/kept/$nodeFileName',
          '{"nodeId":"${newUlid()}","level":"$freeTreeLevel"}',
        )
        ..put('songs/kept/v1.rpp', unknown);

      final result = await scan(memory, library(null), writeNodes: false);

      expect(memory.changes, 0);
      expect(result.titles.map((t) => t.path), ['songs/kept']);
    });

    test('scan keeps the folders of titles and versions', () async {
      const folders = ['Assets', '.trash', 'v1/Media', 'v1/Renders'];
      put('band/album/song/v1/v1.rpp', adopted);
      for (final name in folders) {
        Directory(p.joinAll([root.path, 'band', 'album', 'song', name]))
            .createSync(recursive: true);
      }

      await scan(storage, library(Layout.classic()));

      expect(folders.every((n) => dir('band/album/song/$n')), isTrue);
      expect(exists('band/album/song/.node.json'), isTrue);
    });

    test('free tree titles are not scaffolded', () async {
      put('songs/demo/v1.rpp', unknown);
      await scan(storage, library(null));
      expect(exists('songs/demo/.node.json'), isTrue);
      expect(dir('songs/demo/Media'), isFalse);
    });

    test('scaffoldTitle writes the node file only', () async {
      final node = await scaffoldTitle(storage, 'band/album/song', 'title');
      for (final name in ['Assets', '.trash', 'Media', 'Renders']) {
        expect(dir('band/album/song/$name'), isFalse, reason: name);
      }
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
      const dir = '$title/Song - chorus';
      const file = 'Song - chorus/Song - chorus.RPP';
      put('$title/$file', adopted);

      final path = await backupVersion(storage, title, file, now: when);
      final again = await backupVersion(storage, title, file, now: when);

      expect(path, '$dir/.history/Song - chorus 2026-11-07 153012.RPP');
      expect(again, '$dir/.history/Song - chorus 2026-11-07 153012 (2).RPP');
      expect(read(path), rebaseProjectPaths(adopted, dir, '$dir/.history'));
      expect(read(path), isNot(adopted));
      expect(read('$title/$file'), adopted);
      final result = await scan(storage, library(Layout.classic()));
      expect(result.titles.single.versions, hasLength(1));
    });

    test('lists backups by version, newest first', () async {
      final id = VersionMetadata.fromExtState(
        RppProject.parse(adopted).extState(VersionMetadata.section),
      )!.id;
      put('$title/v1/v1.rpp', adopted);
      put('$title/v1/.history/unknown 2026-01-01 000000.rpp', unknown);
      put('$title/v1/.history/notes.txt', 'x');
      put('$title/v2/v2.rpp', adopted);
      await backupVersion(storage, title, 'v1/v1.rpp', now: when);
      await backupVersion(
        storage,
        title,
        'v1/v1.rpp',
        now: when.add(const Duration(days: 1)),
      );

      final history = await readHistory(storage, '$title/v1');

      expect(history.keys, [id]);
      expect(history[id]!.map((b) => b.created), [
        when.add(const Duration(days: 1)),
        when,
      ]);
      // Each version has its own history.
      expect(await readHistory(storage, '$title/v2'), isEmpty);
      expect(await readHistory(storage, title), isEmpty);
    });

    test('restores a backup after backing up the current state', () async {
      const dir = '$title/v1';
      put('$dir/v1.rpp', adopted);
      final backup = await backupVersion(
        storage,
        title,
        'v1/v1.rpp',
        now: when,
      );
      put('$dir/v1.rpp', '$adopted\n');

      final saved = await restoreBackup(
        storage,
        title,
        'v1/v1.rpp',
        backup,
        now: when.add(const Duration(hours: 1)),
      );

      const history = '$dir/.history';
      expect(read(backup), rebaseProjectPaths(adopted, dir, history));
      expect(
        read('$dir/v1.rpp'),
        rebaseProjectPaths(read(backup), history, dir),
      );
      expect(read(saved), rebaseProjectPaths('$adopted\n', dir, history));
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

    test('suggests a name from title, label and owner', () {
      expect(suggestedVersionName('Song', 'chorus B'), 'Song - chorus B');
      expect(suggestedVersionName('Song', ' '), 'Song');
      expect(
        suggestedVersionName('Song', 'demo', owner: 'Bob'),
        'Song - demo - Bob',
      );
    });
    final owner = MemberId.generate();

    String read(String path) =>
        File(p.joinAll([root.path, ...path.split('/')])).readAsStringSync();

    VersionMetadata? metadataOf(String path) => VersionMetadata.fromExtState(
      RppProject.parse(read(path)).extState(VersionMetadata.section),
    );

    VersionMetadata meta([String label = 'x']) =>
        VersionMetadata(id: VersionId.generate(), owner: owner, label: label);

    /// Node file of the title, created if missing.
    Future<NodeFile> node() async =>
        await readNodeFile(storage, title) ??
        await scaffoldTitle(storage, title, 'title');

    String withoutMetadata(String text) => setExtState(
      text,
      VersionMetadata.section,
      {for (final k in meta().toExtState().keys) k: null},
    );

    bool dir(String path) =>
        Directory(p.joinAll([root.path, ...path.split('/')])).existsSync();

    test('creates a blank version, scanned as adopted', () async {
      await node();
      final m = meta('intro');
      final path = await createVersion(storage, title, 'Song - intro', m);

      expect(path, '$title/Song - intro/Song - intro.RPP');
      expect(dir('$title/Song - intro/Media'), isTrue);
      expect(dir('$title/Song - intro/Renders'), isTrue);
      final root = RppProject.parse(read(path)).document.root;
      expect(root.line('RECORD_PATH')!.params, ['Media', '']);
      expect(root.line('RENDER_FILE')!.params, ['Renders']);
      expect(RppProject.parse(read(path)).extState(VersionMetadata.section), {
        'VERSIONID': m.id,
      });
      final result = await scan(storage, library(Layout.classic()));
      final scanned = result.titles.single.versions.single;
      expect(scanned.folder, 'Song - intro');
      final read2 = scanned.metadata!;
      expect((read2.id, read2.label, read2.owner), (m.id, 'intro', owner));
    });

    test('version actions work on a title without its folders', () async {
      put('$title/v1/v1.rpp', adopted);
      await scan(storage, library(Layout.classic()));
      for (final name in ['Assets', '.trash', 'v1/Media', 'v1/.history']) {
        expect(dir('$title/$name'), isFalse, reason: name);
      }

      expect(await readHistory(storage, '$title/v1'), isEmpty);
      expect(await readTrash(storage, title), isEmpty);

      final created = await createVersion(storage, title, 'Song', meta());
      final backup = await backupVersion(storage, title, 'v1/v1.rpp');
      final trashed = await deleteVersion(storage, title, version('Song'));

      expect(exists(backup), isTrue);
      expect(
        (await readHistory(storage, '$title/v1')).values.single,
        hasLength(1),
      );
      expect(exists(created), isFalse);
      expect(trashed, '$title/.trash/Song');
      expect((await readTrash(storage, title)).map((e) => e.path), [trashed]);
    });

    test('writes no project when the node file is missing', () async {
      await expectLater(
        createVersion(storage, title, 'Song', meta()),
        throwsStateError,
      );
      expect(exists('$title/Song/Song.RPP'), isFalse);
    });

    test('writes no owner when none is given', () async {
      await node();
      final m = VersionMetadata(id: VersionId.generate(), label: 'solo');
      await createVersion(storage, title, 'Song', m);
      final saved = (await readNodeFile(storage, title))!;
      expect(saved.versionLabels, {m.id: 'solo'});
      expect(saved.versionOwners, isEmpty);
    });

    test('creates a version from a template, keeping its content', () async {
      await node();
      final path = await createVersion(
        storage,
        title,
        'Song',
        meta(),
        template: unknown,
      );

      final project = RppProject.parse(read(path));
      expect(project.tracks.length, RppProject.parse(unknown).tracks.length);
      expect(project.document.root.line('RECORD_PATH')!.params.first, 'Media');
    });

    test('refuses invalid or existing names', () async {
      put('$title/Song/Song.RPP', adopted);
      expect(
        () => createVersion(storage, title, 'Song', meta()),
        throwsStateError,
      );
      for (final name in [
        '',
        ' ',
        'a/b',
        '.hidden',
        'end.',
        // Kept by the application, in any case.
        'Assets',
        'media',
        'Renders',
        'BACKUPS',
        '.history',
        '.trash',
        'Media ',
      ]) {
        expect(isValidVersionName(name), isFalse, reason: name);
        expect(
          () => createVersion(storage, title, name, meta()),
          throwsArgumentError,
          reason: name,
        );
      }
      expect(isValidVersionName('Song - take 2'), isTrue);
    });

    test('duplicates a version folder under a new identity', () async {
      const from = '$title/Song';
      final date = DateTime(2025, 3, 4, 5, 6, 7);
      put('$from/Song.RPP', adopted);
      put('$from/Media/kick.wav', 'kick');
      File(p.joinAll([root.path, ...'$from/Media/kick.wav'.split('/')]))
          .setLastModifiedSync(date);
      put('$from/Renders/mix.wav', 'mix');
      put('$from/.history/Song 2026-01-01 000000.RPP', adopted);
      put('$from/notes.txt', 'x');
      await node();
      final m = meta('copy');

      final path = await duplicateVersion(
        storage,
        title,
        version('Song'),
        'Song - copy',
        m,
      );

      const to = '$title/Song - copy';
      expect(path, '$to/Song - copy.RPP');
      expect(metadataOf(path)!.id, m.id);
      expect(withoutMetadata(read(path)), withoutMetadata(adopted));
      expect(read('$to/Media/kick.wav'), 'kick');
      expect(
        File(p.joinAll([root.path, ...'$to/Media/kick.wav'.split('/')]))
            .lastModifiedSync(),
        date,
      );
      expect(dir('$to/Renders'), isTrue);
      expect(exists('$to/Renders/mix.wav'), isFalse);
      expect(dir('$to/.history'), isFalse);
      expect(exists('$to/notes.txt'), isFalse);
      expect(read('$from/Song.RPP'), adopted);
      final saved = (await readNodeFile(storage, title))!;
      expect(saved.versionLabels, {m.id: 'copy'});
      expect(saved.versionOwners, {m.id: owner});
    });

    test('duplicates a version without media', () async {
      put('$title/Song/Song.rpp', adopted);
      await node();

      final path = await duplicateVersion(
        storage,
        title,
        version('Song', 'Song.rpp'),
        'Song 2',
        meta(),
      );

      expect(path, '$title/Song 2/Song 2.rpp');
      expect(dir('$title/Song 2/Media'), isTrue);
    });

    test('separates a Save As copy, its label copied', () async {
      put('$title/Song/Song.RPP', adopted);
      put('$title/Song/Song copy.RPP', adopted);
      await node();
      await setVersionLabel(storage, title, adoptedId, 'chorus B');
      final other = MemberId.generate();
      await setVersionOwner(storage, title, adoptedId, other);

      final id = await separateDuplicateVersion(
        storage,
        title,
        'Song/Song copy.RPP',
        label: 'chorus B',
        owner: owner,
      );

      expect(id, isNot(adoptedId));
      expect(read('$title/Song/Song.RPP'), adopted);
      expect(metadataOf('$title/Song/Song copy.RPP')!.id, id);
      final saved = (await readNodeFile(storage, title))!;
      expect(saved.versionLabels, {adoptedId: 'chorus B', id: 'chorus B'});
      expect(saved.versionOwners, {adoptedId: other, id: owner});
      final versions = {
        for (final v in (await scan(
          storage,
          library(Layout.classic()),
        )).titles.single.versions)
          v.fileName: v.metadata!,
      };
      expect(versions['Song/Song copy.RPP']!.label, 'chorus B');
      expect(versions['Song/Song.RPP']!.owner, other);

      put('$title/Other/Other.RPP', unknown);
      await expectLater(
        separateDuplicateVersion(storage, title, 'Other/Other.RPP', label: 'x'),
        throwsStateError,
      );
    });

    test('separates a Save As copy, the fallback label kept', () async {
      put('$title/Song/Song.RPP', adopted);
      put('$title/Song/Song copy.RPP', adopted);
      await node();

      // The original has no entry: its label is its folder name.
      final id = await separateDuplicateVersion(
        storage,
        title,
        'Song/Song copy.RPP',
        label: 'Song',
      );

      final saved = (await readNodeFile(storage, title))!;
      expect(saved.versionLabels, {id: 'Song'});
      expect(saved.versionOwners, isEmpty);
      expect(metadataOf('$title/Song/Song copy.RPP')!.id, id);
    });

    test('renames a version folder and its project, edits its label', () async {
      put('$title/Song/Song.RPP', adopted);
      put('$title/Song/Media/a.wav', 'a');
      await node();
      final id = metadataOf('$title/Song/Song.RPP')!.id;

      final path = await renameVersion(
        storage,
        title,
        version('Song'),
        'Song B',
      );
      await setVersionLabel(storage, title, id, 'bridge');

      expect(path, '$title/Song B/Song B.RPP');
      expect(dir('$title/Song'), isFalse);
      expect(read('$title/Song B/Media/a.wav'), 'a');
      expect(metadataOf(path)!.id, id);
      final m = (await scan(
        storage,
        library(Layout.classic()),
      )).titles.single.versions.single.metadata!;
      expect((m.id, m.label), (id, 'bridge'));
      put('$title/Other/Other.RPP', unknown);
      expect(
        () => renameVersion(storage, title, version('Other'), 'Song B'),
        throwsStateError,
      );
      expect(
        () => renameVersion(storage, title, version('Other'), 'a/b'),
        throwsArgumentError,
      );
    });

    test('gives the project the name of its folder on a rename', () async {
      put('$title/Take/old name.rpp', adopted);

      final renamed = await renameVersion(
        storage,
        title,
        version('Take', 'old name.rpp'),
        'Take 2',
      );
      // Same folder name: only the project follows it.
      final same = await renameVersion(
        storage,
        title,
        version('Take 2', 'Take 2.rpp'),
        'Take 2',
      );
      put('$title/Mix/other.rpp', adopted);
      final file = await renameVersion(
        storage,
        title,
        version('Mix', 'other.rpp'),
        'Mix',
      );

      expect(renamed, '$title/Take 2/Take 2.rpp');
      expect(same, renamed);
      expect(file, '$title/Mix/Mix.rpp');
      expect(exists(file), isTrue);
      expect(
        () => renameVersion(
          storage,
          'free',
          Version(fileName: 'a/b.rpp', modified: DateTime(2026), size: 0),
          'c',
        ),
        throwsArgumentError,
      );
    });

    test(
      'moves version folders to the trash, free tree files beside',
      () async {
        put('$title/Song/Song.RPP', adopted);
        put('$title/Song/Media/a.wav', 'aa');
        put('$title/.trash/Song/Song.RPP', adopted);
        put('free/member/v2/take.rpp', unknown);

        final trashed = await deleteVersion(storage, title, version('Song'));
        final nested = await deleteVersion(
          storage,
          'free',
          Version(
            fileName: 'member/v2/take.rpp',
            modified: DateTime(2026),
            size: 0,
          ),
        );

        expect(trashed, '$title/.trash/Song (2)');
        expect(read('$trashed/Media/a.wav'), 'aa');
        expect(nested, 'free/member/v2/.trash/take.rpp');
        expect(dir('$title/Song'), isFalse);
        expect((await readTrash(storage, 'free')).map((e) => e.path), [nested]);
        final trash = {
          for (final e in await readTrash(storage, title)) e.path: e,
        };
        expect(trash.keys, unorderedEquals(['$title/.trash/Song', trashed]));
        expect(trash[trashed]!.isDirectory, isTrue);
        expect(trash[trashed]!.size, utf8.encode(adopted).length + 2);
      },
    );

    test('keeps only one version, the others to the trash', () async {
      put('$title/Song/Song.RPP', adopted);
      put('$title/B/B.rpp', unknown);
      put('$title/C/C.rpp', unknown);
      put('$title/.trash/B/B.rpp', unknown);
      put('$title/Assets/score.pdf', 'x');
      put('$title/notes/readme.txt', 'x');

      final trashed = await keepOnlyVersion(storage, title, version('Song'));

      expect(
        trashed,
        unorderedEquals(['$title/.trash/B (2)', '$title/.trash/C']),
      );
      expect(exists('$title/Song/Song.RPP'), isTrue);
      expect(exists('$title/Assets/score.pdf'), isTrue);
      expect(exists('$title/notes/readme.txt'), isTrue);
      expect(dir('$title/B'), isFalse);
      expect(exists('$title/.trash/C/C.rpp'), isTrue);
    });

    test('keeps a version only from its folder, alone in it', () async {
      put('$title/Song/Song.RPP', adopted);
      put('$title/Song/Song copy.RPP', adopted);
      put('$title/B/B.rpp', unknown);
      put('$title/Media/sub.rpp', unknown);

      // Its folder holds another project: nothing moves.
      await expectLater(
        keepOnlyVersion(storage, title, version('Song')),
        throwsA(isA<SharedVersionFolderException>()),
      );
      // Gone since the last scan: nothing moves.
      await expectLater(
        keepOnlyVersion(storage, title, version('Gone')),
        throwsStateError,
      );
      expect(dir('$title/B'), isTrue);

      await keepOnlyVersion(storage, title, version('B', 'B.rpp'));
      // A reserved folder is never a version.
      expect(exists('$title/Media/sub.rpp'), isTrue);
      expect(dir('$title/.trash/Song'), isTrue);
    });

    test('keeps a version whose folder changed case outside the app', () async {
      put('$title/Song/Song.RPP', adopted);
      put('$title/B/B.rpp', unknown);
      Directory(p.joinAll([root.path, ...title.split('/'), 'Song']))
          .renameSync(p.joinAll([root.path, ...title.split('/'), 'song']));

      await keepOnlyVersion(storage, title, version('Song'));

      expect(exists('$title/song/Song.RPP'), isTrue);
      expect(dir('$title/B'), isFalse);
    }, testOn: 'windows || mac-os');

    test('refuses to move or rename a folder of several projects', () async {
      put('$title/Song/Song.RPP', adopted);
      put('$title/Song/Song copy.RPP', adopted);

      await expectLater(
        deleteVersion(storage, title, version('Song')),
        throwsA(isA<SharedVersionFolderException>()),
      );
      await expectLater(
        renameVersion(storage, title, version('Song'), 'Other'),
        throwsA(
          isA<SharedVersionFolderException>().having(
            (e) => e.folder,
            'folder',
            '$title/Song',
          ),
        ),
      );
      expect(exists('$title/Song/Song copy.RPP'), isTrue);
      expect(dir('$title/Other'), isFalse);
      expect(const SharedVersionFolderException('a').toString(), contains('a'));
    });

    test('renames a version by a change of case', () async {
      put('$title/mix/mix.rpp', adopted);

      final path = await renameVersion(
        storage,
        title,
        version('mix', 'mix.rpp'),
        'Mix',
      );

      expect(path, '$title/Mix/Mix.rpp');
      final names = [
        for (final e in Directory(
          p.joinAll([root.path, ...title.split('/')]),
        ).listSync())
          p.basename(e.path),
      ];
      expect(names, ['Mix']);
      expect(
        Directory(p.joinAll([root.path, ...title.split('/'), 'Mix']))
            .listSync()
            .map((e) => p.basename(e.path)),
        ['Mix.rpp'],
      );
    });

    test('purges trash entries only, folders whole', () async {
      put('$title/.trash/Song/Song.RPP', adopted);
      put('$title/.trash/Song/Media/a.wav', 'a');
      put('$title/.trash/score.pdf', 'x');
      put('$title/Song/Song.RPP', adopted);

      for (final path in [
        '$title/Song/Song.RPP',
        '$title/.trash/Song/Song.RPP',
      ]) {
        await expectLater(
          purgeTrash(storage, title, [path]),
          throwsArgumentError,
          reason: path,
        );
      }
      final trash = await readTrash(storage, title);
      expect(
        trash.map((e) => e.path),
        unorderedEquals(['$title/.trash/Song', '$title/.trash/score.pdf']),
      );
      await purgeTrash(storage, title, [for (final e in trash) e.path]);

      expect(dir('$title/.trash/Song'), isFalse);
      expect(exists('$title/.trash/score.pdf'), isFalse);
      expect(exists('$title/Song/Song.RPP'), isTrue);
      expect(await readTrash(storage, title), isEmpty);
    });
  });

  group('adoption', () {
    test('writes the id into the project, label and owner aside', () async {
      put('band/album/song/v1/v1.rpp', unknown);
      final lib = library(Layout.classic());
      expect((await scan(storage, lib)).toAdopt, hasLength(1));
      final metadata = VersionMetadata(
        id: VersionId.generate(),
        owner: MemberId.generate(),
        label: 'chorus B',
      );
      await adoptVersion(storage, 'band/album/song', 'v1/v1.rpp', metadata);
      final result = await scan(storage, lib);
      final read = result.titles.single.versions.single.metadata!;
      expect(
        (read.id, read.owner, read.label),
        (metadata.id, metadata.owner, 'chorus B'),
      );
      expect(result.toAdopt, isEmpty);
      final text = File(
        p.joinAll([root.path, 'band', 'album', 'song', 'v1', 'v1.rpp']),
      ).readAsStringSync();
      expect(RppProject.parse(text).extState(VersionMetadata.section), {
        'VERSIONID': metadata.id,
      });
    });

    test('leaves the project intact when its write fails', () async {
      final memory = MemoryStorage()
        ..put('song/v1.rpp', unknown)
        ..put('song/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');
      final metadata = VersionMetadata(id: VersionId.generate(), label: 'a');
      // Change 1: the node file; change 2: the project.
      memory.failAt = 2;

      await expectLater(
        adoptVersion(memory, 'song', 'v1.rpp', metadata),
        throwsA(isA<InjectedFailure>()),
      );

      expect(memory.text('song/v1.rpp'), unknown);
      // The entry left behind names no version: harmless, and the adoption
      // can simply start again under a new id.
      memory.failAt = null;
      final retry = VersionMetadata(id: VersionId.generate(), label: 'b');
      await adoptVersion(memory, 'song', 'v1.rpp', retry);
      final node = (await readNodeFile(memory, 'song'))!;
      expect(node.versionLabels, {metadata.id: 'a', retry.id: 'b'});
      expect(
        VersionMetadata.fromExtState(
          RppProject.parse(memory.text('song/v1.rpp'))
              .extState(VersionMetadata.section),
        )!.id,
        retry.id,
      );
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
      put('band/loose.rpp', project([r'audio-files\kick.wav', 'sub.rpp']));
      put('band/audio-files/kick.wav', 'kick');
      put('band/sub.rpp', project([r'audio-files\kick.wav']));
      put('band/sub.rpp-PROX', 'proxy');

      final report = await moveProjectToTitle(
        storage,
        'band/loose.rpp',
        'band/_Unassigned/loose',
      );

      const title = 'band/_Unassigned/loose';
      expect(report.items[ReportKind.projectMoved], [
        const ReportItem('$title/loose.rpp'),
      ]);
      // The media shared with the subproject is copied (the subproject is
      // another project of the source folder); the subproject, used by
      // this project only, is moved with its proxy.
      expect(report.items[ReportKind.mediaCopied], [
        const ReportItem('$title/Media/kick.wav', 'band/audio-files/kick.wav'),
      ]);
      expect(report.items[ReportKind.mediaMoved], [
        const ReportItem('$title/Media/sub.rpp', 'band/sub.rpp'),
      ]);
      expect(exists('band/loose.rpp'), isFalse);
      expect(exists('band/sub.rpp'), isFalse);
      expect(exists('band/audio-files/kick.wav'), isTrue);
      expect(exists('$title/Media/sub.rpp-PROX'), isTrue);
      final moved = read('$title/loose.rpp');
      expect(moved.mediaFiles, [r'Media\kick.wav', r'Media\sub.rpp']);
      expect(moved.recordPath, 'Media');
      expect(read('$title/Media/sub.rpp').mediaFiles, ['kick.wav']);
    });

    test(
      'moves unshared media, trashes identical ones, renames others',
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
        put('band/album/song/a.rpp', project([]));

        final report = await moveProjectToTitle(
          storage,
          'band/a.rpp',
          'band/album/song',
        );

        const song = 'band/album/song';
        expect(report.items[ReportKind.projectMoved], [
          const ReportItem('$song/a (2).rpp'),
        ]);
        expect(report.items[ReportKind.mediaCopied], [
          const ReportItem('$song/Media/kick.wav', 'band/audio/kick.wav'),
        ]);
        expect(report.items[ReportKind.mediaTrashed], [
          const ReportItem('$song/.trash/snare.wav', '$song/Media/snare.wav'),
        ]);
        expect(report.items[ReportKind.mediaMoved], [
          const ReportItem('$song/Media/hat (2).wav', 'band/audio/hat.wav'),
        ]);
        expect(exists('band/audio/kick.wav'), isTrue);
        expect(exists('band/audio/snare.wav'), isFalse);
        expect(read('$song/a (2).rpp').mediaFiles, [
          'Media/kick.wav',
          'Media/snare.wav',
          'Media/hat (2).wav',
        ]);
        // The whole title is normalized.
        expect(read('$song/a.rpp').recordPath, 'Media');
      },
    );

    test('copies the media another title uses', () async {
      put('loose.rpp', project([r'audio\x.wav']));
      put('audio/x.wav', 'x');

      final report = await moveProjectToTitle(
        storage,
        'loose.rpp',
        'band/album/song',
        usage: {
          'audio/x.wav': ['band/album/other/v.rpp'],
        },
      );

      expect(report.items[ReportKind.mediaCopied], [
        const ReportItem('band/album/song/Media/x.wav', 'audio/x.wav'),
      ]);
      expect(exists('audio/x.wav'), isTrue);
    });

    test('moves a blocked project, leaving its media in place', () async {
      put(
        'band/loose.rpp',
        project([
          r'audio-files\kick.wav',
          r'C:\elsewhere\x.wav',
          r'audio-files\gone.wav',
        ]),
      );
      put('band/audio-files/kick.wav', 'kick');

      final report = await moveProjectToTitle(
        storage,
        'band/loose.rpp',
        'band/_Unassigned/loose',
      );

      const moved = 'band/_Unassigned/loose/loose.rpp';
      expect(report.items[ReportKind.projectMoved], [const ReportItem(moved)]);
      expect(report.items[ReportKind.missingMedia], [
        const ReportItem(moved, r'..\..\audio-files\gone.wav'),
      ]);
      expect(report.items[ReportKind.externalMedia], [
        const ReportItem(moved, r'C:\elsewhere\x.wav'),
      ]);
      expect(exists('band/audio-files/kick.wav'), isTrue);
      final after = read(moved);
      // References still pointing at the same files.
      expect(after.mediaFiles, [
        r'..\..\audio-files\kick.wav',
        r'C:\elsewhere\x.wav',
        r'..\..\audio-files\gone.wav',
      ]);
      expect(after.recordPath!.replaceAll(r'\', '/'), '../../audio-files');
    });
  });

  group('known values', () {
    test('are pre-filled from the folders of the titles', () async {
      put('band/album/song/v1.rpp', unknown);
      put('band/album/song/Media/x.rpp', unknown);
      put('band/_Unassigned/other/v1.rpp', unknown);
      put('solo/live/song/member/x.rpp', unknown);
      put('loose/a.rpp', unknown);
      put('a/Media/b/x.rpp', unknown);
      put('a/b/c/Backups/x.rpp', unknown);
      put('.collab/m/a/b/x.rpp', unknown);

      expect(await prefillKnownValues(storage, Layout.classic()), const [
        KnownValue('band', [
          KnownValue(Layout.unassigned),
          KnownValue('album'),
        ]),
        KnownValue('solo', [KnownValue('live')]),
      ]);
      expect(
        await prefillKnownValuesIn(root.path, Layout.projectOriented()),
        const [KnownValue('band'), KnownValue('solo')],
      );
      expect(
        await prefillKnownValues(storage, Layout([const LayoutLevel('t')])),
        isEmpty,
      );
    });

    test('recognize misplaced levels with their target', () async {
      final lib = library(Layout.classic()).withKnownValues(const [
        KnownValue('Band', [
          KnownValue('First album'),
          KnownValue(Layout.unassigned),
        ]),
      ]);
      put('Band/First album/Song/v/v.rpp', unknown);
      put('Band/_Unassigned/Other/v/v.rpp', unknown);
      put('First album/Song2/v/v.rpp', unknown);
      put('Loose/v/v.rpp', unknown);
      put('Band/Loose2/v/v.rpp', unknown);
      put('Stranger/Album/Song/v/v.rpp', unknown);

      final result = await scan(storage, lib);

      // Titles placed too high stay visible, tagged as at their target.      expect(result.titles.map((t) => t.path), [        'Band/First album/Song',        'Band/Loose2',        'Band/_Unassigned/Other',        'Loose',      ]);      expect(result.titles.last.tags, {        'artist': Layout.unassigned,        'album': Layout.unassigned,        'title': 'Loose',      });      expect(result.titles.last.versions.single.fileName, 'v/v.rpp');      expect(result.titles[1].tags['artist'], 'Band');
      expect(layoutIssues(result), {
        ReportKind.misplacedLevel: [
          const ReportItem.misplaced(
            'First album',
            level: LayoutLevel('album'),
            target: 'Band/First album',
          ),
        ],
        ReportKind.titleTooHigh: [
          const ReportItem.misplaced(
            'Band/Loose2',
            level: LayoutLevel('title'),
            target: 'Band/_Unassigned/Loose2',
          ),
          const ReportItem.misplaced(
            'Loose',
            level: LayoutLevel('title'),
            target: '_Unassigned/_Unassigned/Loose',
          ),
        ],
        ReportKind.unknownValue: [
          const ReportItem.misplaced('Stranger', level: LayoutLevel('artist')),
        ],
      });
      expect(exists('Stranger/$nodeFileName'), isFalse);
      expect(exists('Stranger/Album/Song/$nodeFileName'), isFalse);

      // Without known values, levels are recognized by depth only.
      final byDepth = await scan(storage, library(Layout.classic()));
      expect(
        byDepth.issues.items.keys,
        isNot(contains(ReportKind.unknownValue)),
      );
      expect(
        byDepth.issues.items.keys,
        isNot(contains(ReportKind.titleTooHigh)),
      );
      expect(
        byDepth.titles.map((t) => t.path),
        contains('Stranger/Album/Song'),
      );
    });

    test('keep a title placed too high hidden if its node is another '
        'level', () async {
      final lib = library(Layout.projectOriented())
          .withKnownValues(const [KnownValue('Band')]);
      put('Band/Song/v/v.rpp', unknown);
      put('Old/v/v.rpp', unknown);
      put('Old/$nodeFileName', '{"nodeId":"N","level":"artist"}');

      final result = await scan(storage, lib);
      expect(result.titles.map((t) => t.path), ['Band/Song']);
      expect(result.issues.items[ReportKind.titleTooHigh], [
        const ReportItem.misplaced(
          'Old',
          level: LayoutLevel('title'),
          target: '_Unassigned/Old',
        ),
      ]);
    });
  });
}
