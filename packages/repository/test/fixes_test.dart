import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

/// Minimal project with relative, Windows-style and absolute media.
const project = '''
<REAPER_PROJECT 0.1 "7.0" 0
  RECORD_PATH "audio" ""
  <TRACK
    <ITEM
      <SOURCE WAVE
        FILE "audio\\x.wav"
      >
    >
    <ITEM
      <SOURCE WAVE
        FILE "take.wav"
      >
    >
    <ITEM
      <SOURCE WAVE
        FILE "C:\\abs.wav"
      >
    >
  >
>
''';

const fixtures = '../../test/fixtures';

void main() {
  late Directory root;
  late MountedFolderStorage storage;

  File file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  void put(String path, [String content = '']) {
    final f = file(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  Future<String> hash(String path) async =>
      base64.encode([...await storage.read(path).expand((c) => c).toList()]);

  Future<Migration> migration() async {
    final m = Migration.start(storage);
    await m.inventory.take(hash);
    return m;
  }

  /// Whether the inventory check of [m] finds no gap.
  Future<bool> noLoss(Migration m) async =>
      (await m.inventory.check(hash, locate: m.journal.locate)).isEmpty;

  /// Library path of the media [ref] of a project in [dir].
  String resolveMedia(String dir, String ref) =>
      p.posix.normalize('$dir/${ref.replaceAll(r'\', '/')}');

  setUp(() {
    root = Directory.systemTemp.createTempSync('reaharvest_fixes_');
    storage = MountedFolderStorage(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('each fix is journaled between its start and its end', () async {
    put('a/v.rpp', 'original');
    final date = DateTime(2020, 1, 2, 3, 4, 5);
    file('a/v.rpp').setLastModifiedSync(date);
    final m = await migration();

    final report = await applyFixes(m, const [
      MoveFolder('a', 'b'),
      MoveFolder('missing', 'c'),
    ]);

    expect(report.items[ReportKind.fixFailed], hasLength(1));
    final lines = [
      for (final l in const LineSplitter().convert(
        file('${m.folder}/${MigrationJournal.fileName}').readAsStringSync(),
      ))
        jsonDecode(l),
    ];
    expect(lines, [
      {'op': 'fixStart', 'fix': 1, 'kind': 'moveFolder', 'path': 'a'},
      {'op': 'move', 'from': 'a', 'to': 'b'},
      {'op': 'fixEnd', 'fix': 1, 'ok': true},
      {'op': 'fixStart', 'fix': 2, 'kind': 'moveFolder', 'path': 'missing'},
      {'op': 'move', 'from': 'missing', 'to': 'c'},
      {'op': 'fixEnd', 'fix': 2, 'ok': false},
    ]);
    expect(m.journal.unfinishedFix, 2);

    // On disk too, a rewritten project keeps its date (version date).
    await m.storage.write('b/v.rpp', Stream.value(utf8.encode('rewritten')));
    expect(file('b/v.rpp').lastModifiedSync(), date);
    expect(
      file('${m.folder}/originals/a/v.rpp').readAsStringSync(),
      'original',
    );
  });

  test('lifts a project into its title, references kept', () async {
    put('Song/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');
    put('Song/a.rpp', 'already there');
    put('Song/Alice/mix/a.rpp', project);
    final m = await migration();

    final moved = await liftProject(
      m.storage,
      'Song/Alice/mix/a.rpp',
      'Song',
      owner: const MemberId('alice'),
      status: 'mixing',
    );

    expect(moved, 'Song/a (2).rpp');
    final text = file(moved).readAsStringSync();
    final lifted = RppProject.parse(text);
    // Without a separator, the platform one is used, like REAPER does.
    final sep = Platform.isWindows ? r'\' : '/';
    expect(lifted.mediaFiles, [
      r'Alice\mix\audio\x.wav',
      'Alice${sep}mix${sep}take.wav',
      r'C:\abs.wav',
    ]);
    expect(lifted.document.root.line('RECORD_PATH')!.params, [
      'Alice${sep}mix${sep}audio',
      '',
    ]);
    final metadata = VersionMetadata.fromExtState(
      lifted.extState(VersionMetadata.section),
    )!;
    expect(metadata.owner, 'alice');
    final node = (await readNodeFile(storage, 'Song'))!;
    expect(node.versionStatuses, {metadata.id: 'mixing'});
    expect(await noLoss(m), isTrue);

    // An adopted project keeps its metadata; no status is set without one.
    put('Root/sub/b.rpp', text);
    final again = await migration();
    final top = await liftProject(
      again.storage,
      'Root/sub/b.rpp',
      'Root',
      owner: const MemberId('bob'),
    );
    expect(top, 'Root/b.rpp');
    final kept = VersionMetadata.fromExtState(
      RppProject.parse(file(top).readAsStringSync())
          .extState(VersionMetadata.section),
    )!;
    expect(kept.id, metadata.id);
    expect(kept.owner, 'alice');
    expect(await readNodeFile(storage, 'Root'), isNull);
  });

  test('lifts a project of a library whose root is the title', () async {
    put('sub/c.rpp', '<REAPER_PROJECT\n>\n');
    final m = await migration();
    final moved = await liftProject(
      m.storage,
      'sub/c.rpp',
      '',
      owner: const MemberId('bob'),
    );
    expect(moved, 'c.rpp');
  });

  test('applies fixes one by one and reports each', () async {
    put('Song/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');
    put('Old/v.rpp', '<REAPER_PROJECT\n>\n');
    put('Taken/v.rpp', '<REAPER_PROJECT\n>\n');
    put('Band/Taken');
    put('loose.rpp', '<REAPER_PROJECT\n>\n');
    put('Song/demo/d.rpp', '<REAPER_PROJECT\n>\n');
    final m = await migration();

    final report = await applyFixes(m, const [
      MoveFolder('Old', 'Band/_Unassigned/Old'),
      MoveFolder('Taken', 'Band/Taken'),
      MoveProject('loose.rpp', 'Song'),
      LiftProject(
        'Song/demo/d.rpp',
        'Song',
        owner: MemberId('bob'),
        statusFolder: 'demo',
      ),
      MoveFolder('Gone', 'Band/Gone'),
    ]);

    expect(report.items[ReportKind.folderMoved], [
      const ReportItem('Band/_Unassigned/Old'),
    ]);
    expect(report.items[ReportKind.targetExists], [
      const ReportItem('Taken', 'Band/Taken'),
    ]);
    expect(report.items[ReportKind.projectMoved], [
      const ReportItem('Song/loose.rpp'),
      const ReportItem('Song/d.rpp'),
    ]);
    expect(report.items[ReportKind.statusFolderUnmatched], [
      const ReportItem('Song/d.rpp', 'demo'),
    ]);
    expect(report.items[ReportKind.fixFailed]!.single.path, 'Gone');
    expect(file('Band/_Unassigned/Old/v.rpp').existsSync(), isTrue);
    expect(await noLoss(m), isTrue);
  });

  test('merges a title moved onto an existing title', () async {
    const media =
        '<REAPER_PROJECT\n  <SOURCE WAVE\n    FILE "Media\\kick.wav"\n  >\n>\n';
    final a = newUlid();
    final b = newUlid();
    put(
      'Song/.node.json',
      '{"nodeId":"${newUlid()}","level":"title",'
          '"status":"mixing","versionStatuses":{"$a":"demo","$b":"demo"}}',
    );
    put('Song/Song.rpp', media);
    put('Song/Media/kick.wav', 'mine');
    put('Song/Media/snare.wav', 'snare');
    put('Song/Assets/tab.txt');
    put(
      'Band/_Unassigned/Song/.node.json',
      '{"nodeId":"${newUlid()}","level":"title",'
          '"status":"final","versionStatuses":{"$b":"mixing"}}',
    );
    put('Band/_Unassigned/Song/Song.rpp', media);
    put('Band/_Unassigned/Song/Media/kick.wav', 'theirs');
    final m = await migration();

    final report = await applyFixes(m, const [
      MoveFolder('Song', 'Band/_Unassigned/Song'),
    ]);

    const title = 'Band/_Unassigned/Song';
    expect(report.items[ReportKind.folderMerged], [
      const ReportItem(title, 'Song'),
    ]);
    expect(report.items[ReportKind.fileRenamed], [
      const ReportItem('$title/Media/kick (2).wav', 'Song/Media/kick.wav'),
      const ReportItem('$title/Song (2).rpp', 'Song/Song.rpp'),
    ]);
    expect(report.items[ReportKind.titleStatusDropped], [
      const ReportItem(title, 'mixing'),
    ]);
    // The moved project follows its renamed media; the other is untouched.
    expect(
      RppProject.parse(file('$title/Song (2).rpp').readAsStringSync())
          .mediaFiles,
      [r'Media\kick (2).wav'],
    );
    expect(file('$title/Song.rpp').readAsStringSync(), media);
    expect(file('$title/Media/kick.wav').readAsStringSync(), 'theirs');
    expect(file('$title/Media/kick (2).wav').readAsStringSync(), 'mine');
    expect(file('$title/Media/snare.wav').existsSync(), isTrue);
    expect(file('$title/Assets/tab.txt').existsSync(), isTrue);
    final node = (await readNodeFile(storage, title))!;
    expect(node.status, 'final');
    expect(node.versionStatuses, {a: 'demo', b: 'mixing'});
    // What is left of the source is kept in the migration folder.
    expect(await storage.stat('Song'), isNull);
    expect(file('${m.folder}/merged/Song/.node.json').existsSync(), isTrue);
    expect(await noLoss(m), isTrue);
  });

  test('merges intermediate folders recursively', () async {
    // Unreadable node files and projects are moved as they are.
    put('Band 2/.node.json', '{');
    put('Band 2/Album/Two/bad.rpp');
    file('Band 2/Album/Two/bad.rpp').writeAsBytesSync([0xff, 0xfe]);
    put('Band 2/Album/One/one.rpp', '<REAPER_PROJECT\n>\n');
    put('Band 2/Album/Two/two.rpp', '<REAPER_PROJECT\n>\n');
    put('Band/.node.json', '{"nodeId":"${newUlid()}","level":"artist"}');
    put('Band/Album/One/one.rpp', '<REAPER_PROJECT\n>\n');
    final m = await migration();

    final report = await applyFixes(m, const [MoveFolder('Band 2', 'Band')]);

    expect(report.items[ReportKind.fileRenamed], [
      const ReportItem(
        'Band/Album/One/one (2).rpp',
        'Band 2/Album/One/one.rpp',
      ),
    ]);
    expect(report.items[ReportKind.titleStatusDropped], isEmpty);
    expect(file('Band/Album/Two/two.rpp').existsSync(), isTrue);
    expect(file('${m.folder}/merged/Band 2/.node.json').existsSync(), isTrue);
    expect(await noLoss(m), isTrue);
  });

  test('does not merge a folder into itself or its parent', () async {
    put('Band/Song/s.rpp', '<REAPER_PROJECT\n>\n');
    final m = await migration();

    final report = await applyFixes(m, const [
      MoveFolder('Band/Song', 'Band'),
      MoveFolder('Band', 'band'),
    ]);

    expect(report.items[ReportKind.targetExists], hasLength(2));
    expect(file('Band/Song/s.rpp').existsSync(), isTrue);
  });

  group('media normalization', () {
    const song = 'Band/Album/Song';

    /// Project referencing [media], with the record path [record].
    String rpp(List<String> media, {String record = 'audio-files'}) => [
      '<REAPER_PROJECT 0.1 "7.0" 0',
      '  RECORD_PATH "$record" ""',
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

    String media(String path) =>
        RppProject.parse(file(path).readAsStringSync()).mediaFiles.join('|');

    test('brings the media of a title into its pool', () async {
      put('$song/audio-files/kick.wav', 'kick');
      put('$song/Alice/audio/snare.wav', 'snare');
      put('$song/Media/bass.wav', 'bass');
      put('$song/old/bass.wav', 'bass');
      put('$song/x/bass.wav', 'other bass');
      put('$song/audio-files/hat.wav', 'hat');
      put('Band/Album/Other/Media/pad.wav', 'pad');
      put(
        '$song/a.rpp',
        rpp([
          r'audio-files\kick.wav',
          r'Alice\audio\snare.wav',
          r'Media\bass.wav',
          r'..\Other\Media\pad.wav',
        ]),
      );
      put(
        '$song/b.rpp',
        rpp([
          r'.\audio-files\kick.wav',
          r'old\bass.wav',
          r'x\bass.wav',
          r'audio-files\hat.wav',
        ], record: 'Media'),
      );
      final blocked = rpp([r'audio-files\hat.wav', r'gone.wav', r'D:\c.wav']);
      put('$song/c.rpp', blocked);
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(report.items[ReportKind.mediaMoved], [
        const ReportItem('$song/Media/kick.wav', '$song/audio-files/kick.wav'),
        const ReportItem(
          '$song/Media/snare.wav',
          '$song/Alice/audio/snare.wav',
        ),
        const ReportItem('$song/Media/bass (2).wav', '$song/x/bass.wav'),
      ]);
      expect(report.items[ReportKind.mediaCopied], [
        const ReportItem(
          '$song/Media/pad.wav',
          'Band/Album/Other/Media/pad.wav',
        ),
        const ReportItem('$song/Media/hat.wav', '$song/audio-files/hat.wav'),
      ]);
      expect(report.items[ReportKind.mediaTrashed], [
        const ReportItem('$song/.trash/bass.wav', '$song/Media/bass.wav'),
      ]);
      expect(report.items[ReportKind.missingMedia], [
        const ReportItem('$song/c.rpp', 'gone.wav'),
      ]);
      expect(report.items[ReportKind.externalMedia], [
        const ReportItem('$song/c.rpp', r'D:\c.wav'),
      ]);
      expect(report.items[ReportKind.mediaNormalized], [
        const ReportItem('$song/a.rpp'),
        const ReportItem('$song/b.rpp'),
      ]);

      expect(
        media('$song/a.rpp'),
        r'Media\kick.wav|Media\snare.wav|Media\bass.wav|Media\pad.wav',
      );
      expect(
        media('$song/b.rpp'),
        r'Media\kick.wav|Media\bass.wav|Media\bass (2).wav|Media\hat.wav',
      );
      expect(
        RppProject.parse(file('$song/a.rpp').readAsStringSync()).recordPath,
        'Media',
      );
      // The blocked project keeps its files and its text.
      expect(file('$song/c.rpp').readAsStringSync(), blocked);
      expect(file('$song/audio-files/hat.wav').existsSync(), isTrue);
      expect(file('Band/Album/Other/Media/pad.wav').existsSync(), isTrue);
      expect(file('$song/Media/pad.wav').readAsStringSync(), 'pad');
      expect(file('$song/.trash/bass.wav').readAsStringSync(), 'bass');
      expect(file('$song/Media/bass (2).wav').readAsStringSync(), 'other bass');
      expect(file('${m.folder}/originals/$song/a.rpp').existsSync(), isTrue);
      expect(await noLoss(m), isTrue);

      // Normalized: nothing left to do.
      final again = await applyFixes(m, const [NormalizeMedia(song)]);
      expect(again.items.keys, {
        ReportKind.missingMedia,
        ReportKind.externalMedia,
      });
    });

    test('takes a subproject along with its proxy', () async {
      put('$song/audio/v.wav', 'voice');
      put('$song/sub.rpp', rpp([r'audio\v.wav'], record: 'Media'));
      put('$song/sub.rpp-PROX', 'proxy');
      // A subproject of another title, copied.
      put('Band/Album/Other/Media/i.wav', 'inner');
      put('Band/Album/Other/inner.rpp', rpp([r'Media\i.wav'], record: 'Media'));
      put('Band/Album/Other/inner.rpp-PROX', 'inner proxy');
      put(
        '$song/main.rpp',
        [
          '<REAPER_PROJECT 0.1 "7.0" 0',
          '  RECORD_PATH "Media" ""',
          '  <TRACK',
          '    <ITEM',
          '      <SOURCE RPP_PROJECT',
          '        FILE "sub.rpp"',
          '      >',
          '    >',
          '    <ITEM',
          '      <SOURCE RPP_PROJECT',
          r'        FILE "..\Other\inner.rpp"',
          '      >',
          '    >',
          '  >',
          '>',
          '',
        ].join('\n'),
      );
      final m = await migration();

      await applyFixes(m, const [NormalizeMedia(song)]);

      expect(media('$song/main.rpp'), r'Media\sub.rpp|Media\inner.rpp');
      expect(
        file('$song/Media/inner.rpp-PROX').readAsStringSync(),
        'inner proxy',
      );
      expect(file('Band/Album/Other/inner.rpp-PROX').existsSync(), isTrue);
      expect(media('$song/Media/inner.rpp'), r'..\..\Other\Media\i.wav');
      expect(file('$song/sub.rpp').existsSync(), isFalse);
      expect(file('$song/Media/sub.rpp-PROX').readAsStringSync(), 'proxy');
      // Next to its media in the pool.
      expect(media('$song/Media/sub.rpp'), 'v.wav');
      expect(file('$song/Media/v.wav').readAsStringSync(), 'voice');
      expect(await noLoss(m), isTrue);
    });

    test('non-regression: every fixture keeps its media', () async {
      final empty = File('$fixtures/empty.rpp').readAsStringSync();
      // Not tested here: media-paths.rpp is blocked (tested on its own),
      // windows-1252.rpp is not UTF-8 (see project_file_test.dart).
      const skipped = {'media-paths.rpp', 'windows-1252.rpp'};
      final sources = {
        for (final f in Directory(fixtures).listSync().whereType<File>())
          if (isProjectFile(f.path) && !skipped.contains(p.basename(f.path)))
            p.basename(f.path): f.readAsStringSync(),
      };
      for (final MapEntry(key: name, value: text) in sources.entries) {
        put('$song/$name', text);
        for (final ref in RppProject.parse(text).mediaFiles) {
          final path = resolveMedia(song, ref);
          if (file(path).existsSync()) continue;
          // A subproject must be readable.
          put(path, isProjectFile(path) ? empty : p.posix.basename(path));
        }
      }
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(report.hasErrors || report.hasWarnings, isFalse);
      for (final MapEntry(key: name, value: before) in sources.entries) {
        final after = file('$song/$name').readAsStringSync();
        final a = before.split('\n');
        final b = after.split('\n');
        expect(b, hasLength(a.length));
        for (var i = 0; i < a.length; i++) {
          if (a[i] == b[i]) continue;
          // Only media references and the record path change.
          expect(b[i].trim(), matches(RegExp(r'^(FILE|RECORD_PATH) ')));
        }
        final project = RppProject.parse(after);
        expect(resolveMedia(song, project.recordPath!), '$song/Media');
        for (final ref in project.mediaFiles) {
          final path = resolveMedia(song, ref);
          expect(path, startsWith('$song/Media/'));
          expect(file(path).existsSync(), isTrue, reason: '$name: $ref');
        }
      }
      expect(await noLoss(m), isTrue);
    });

    test('blocks a title whose media another title uses', () async {
      const other = 'Band/Album/Other';
      final mine = rpp([r'audio\x.wav'], record: 'Media');
      final theirs = rpp([r'..\Song\audio\x.wav', r'Media\y.wav']);
      put('$song/a.rpp', mine);
      put('$song/audio/x.wav', 'x');
      put('$other/b.rpp', theirs);
      put('$other/Media/y.wav', 'y');
      put('$other/Media/sub.rpp', rpp([r'..\..\Song\audio\x.wav']));
      final library = Library(
        id: LibraryId.generate(),
        mode: LibraryMode.local,
        layout: Layout.classic(),
      );
      Future<Map<String, List<String>>> usage() async =>
          mediaUsage(await scan(storage, library));
      expect(await usage(), {
        '$song/audio/x.wav': [
          '$other/b.rpp',
          '$song/a.rpp',
          '$other/Media/sub.rpp',
        ],
        '$other/Media/y.wav': ['$other/b.rpp'],
      });
      final m = await migration();

      final blocked = await applyFixes(m, const [
        NormalizeMedia(song),
      ], usage: await usage());

      expect(blocked.items, {
        ReportKind.mediaUsedElsewhere: [
          const ReportItem(
            '$song/audio/x.wav',
            '$other/b.rpp\n$other/Media/sub.rpp',
          ),
        ],
      });
      expect(file('$song/a.rpp').readAsStringSync(), mine);
      expect(file('$song/audio/x.wav').existsSync(), isTrue);

      // Normalizing the other title first copies the file into its pool.
      await applyFixes(m, const [NormalizeMedia(other)], usage: await usage());
      expect(media('$other/b.rpp'), r'Media\x.wav|Media\y.wav');
      expect(media('$other/Media/sub.rpp'), 'x.wav');
      final done = await applyFixes(m, const [
        NormalizeMedia(song),
      ], usage: await usage());
      expect(done.items[ReportKind.mediaUsedElsewhere], isNull);
      expect(media('$song/a.rpp'), r'Media\x.wav');
      expect(await noLoss(m), isTrue);
    });

    test('leaves the media-paths fixture intact and reports it', () async {
      final text = File('$fixtures/media-paths.rpp').readAsStringSync();
      put('$song/media-paths.rpp', text);
      for (final name in ['a.wav', 'Loops/loop.wav', 'b.flac', 'c.mp3']) {
        put('$song/$name', name);
      }
      put('$song/d.mid', 'midi');
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(report.items[ReportKind.missingMedia], [
        const ReportItem('$song/media-paths.rpp', 'gone.wav'),
      ]);
      expect(report.items[ReportKind.externalMedia], [
        const ReportItem(
          '$song/media-paths.rpp',
          r'D:\ReaHarvestTests\Samples\kick.wav',
        ),
      ]);
      expect(file('$song/media-paths.rpp').readAsStringSync(), text);
      // Its media are left for it.
      expect(file('$song/Loops/loop.wav').existsSync(), isTrue);
      expect(file('$song/d.mid').existsSync(), isTrue);
    });

    test('leaves a pool record path written .\\Media as is', () async {
      final text = rpp([r'Media\a.wav'], record: r'.\Media');
      put('$song/Media/a.wav', 'a');
      put('$song/a.rpp', text);
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(report.isEmpty, isTrue);
      expect(file('$song/a.rpp').readAsStringSync(), text);
    });

    test('merges the media used by no project into the pool', () async {
      for (final member in ['Alice', 'Bob']) {
        put('$song/$member/Media/take.wav', 'take');
        put('$song/$member/notes.txt', 'notes');
      }
      put('$song/loose.mid', 'midi');
      put('$song/Renders/mix.wav', 'mix');
      put('$song/a.rpp', rpp([], record: 'Media'));
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(report.items[ReportKind.mediaMoved], [
        const ReportItem('$song/Media/take.wav', '$song/Alice/Media/take.wav'),
        const ReportItem('$song/Media/loose.mid', '$song/loose.mid'),
      ]);
      expect(report.items[ReportKind.mediaTrashed], [
        const ReportItem('$song/.trash/take.wav', '$song/Media/take.wav'),
      ]);
      // Other files (Assets, #70) and renders stay.
      expect(file('$song/Bob/notes.txt').existsSync(), isTrue);
      expect(file('$song/Renders/mix.wav').existsSync(), isTrue);
      expect(await noLoss(m), isTrue);
    });

    test('keeps the media of the projects not lifted yet', () async {
      put('$song/Alice/Media/take.wav', 'take');
      put('$song/Alice/a.rpp', rpp([r'Media\take.wav']));
      put('$song/b.rpp', rpp([r'Alice\Media\take.wav']));
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(report.items[ReportKind.mediaCopied], [
        const ReportItem('$song/Media/take.wav', '$song/Alice/Media/take.wav'),
      ]);
      expect(file('$song/Alice/Media/take.wav').existsSync(), isTrue);
      expect(media('$song/b.rpp'), r'Media\take.wav');
    });

    test('normalizes the subprojects of the pool', () async {
      put('$song/audio/v.wav', 'voice');
      put('$song/Media/sub.rpp', rpp([r'..\audio\v.wav'], record: 'Media'));
      put('$song/Media/abs.rpp', rpp([r'C:\Users\someone\x.wav']));
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(media('$song/Media/sub.rpp'), 'v.wav');
      expect(file('$song/Media/v.wav').readAsStringSync(), 'voice');
      expect(report.items[ReportKind.externalMedia], [
        const ReportItem('$song/Media/abs.rpp', r'C:\Users\someone\x.wav'),
      ]);
      // Its record path is the one of a project in the pool: left as is.
      expect(
        RppProject.parse(file('$song/Media/sub.rpp').readAsStringSync())
            .recordPath,
        'Media',
      );
    });

    test('leaves a title intact if a project cannot be read', () async {
      put('$song/audio/v.wav', 'voice');
      put('$song/a.rpp', rpp([r'audio\v.wav']));
      file('$song/bad.rpp').writeAsBytesSync([0xC3, 0x28]);
      final m = await migration();

      final report = await applyFixes(m, const [NormalizeMedia(song)]);

      expect(report.items[ReportKind.fixFailed]!.single.path, song);
      expect(file('$song/audio/v.wav').existsSync(), isTrue);
      expect(media('$song/a.rpp'), r'audio\v.wav');
    });
  });
}
