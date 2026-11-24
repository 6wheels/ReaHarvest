import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

const fixtures = '../../test/fixtures';

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

/// Version [source] of a fix, its folder and label named [folder] (by
/// default the file name without extension).
FixVersion version(
  String source, {
  String? folder,
  MemberId? owner,
  String? status,
  String? statusFolder,
}) {
  final name = folder ?? p.posix.basenameWithoutExtension(source);
  return FixVersion(
    source,
    folder: name,
    label: name,
    owner: owner,
    status: status,
    statusFolder: statusFolder,
  );
}

/// Organizes the candidate [root] in place.
OrganizeTitle organize(String root, List<FixVersion> versions) =>
    OrganizeTitle(root, root, versions, level: 'title');

void main() {
  late Directory root;
  late MountedFolderStorage storage;

  File file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  void put(String path, [String content = '']) {
    final f = file(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  void title(String dir) =>
      put('$dir/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');

  Map<String, Object?> node(String dir) =>
      (jsonDecode(file('$dir/.node.json').readAsStringSync()) as Map).cast();

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

  String media(String path) =>
      RppProject.parse(file(path).readAsStringSync()).mediaFiles.join('|');

  VersionId? idOf(String path) => VersionMetadata.fromExtState(
    RppProject.parse(file(path).readAsStringSync())
        .extState(VersionMetadata.section),
  )?.id;

  setUp(() {
    root = Directory.systemTemp.createTempSync('reaharvest_fixes_');
    storage = MountedFolderStorage(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('each fix is journaled between its start and its end', () async {
    title('a');
    put('a/v/v.rpp', rpp([], record: 'Media'));
    final date = DateTime(2020, 1, 2, 3, 4, 5);
    file('a/v/v.rpp').setLastModifiedSync(date);
    final m = await migration();

    final report = await applyFixes(m, [
      OrganizeTitle('a', 'b', [version('a/v/v.rpp')], level: 'title'),
      organize('c', [version('c/gone.rpp')]),
    ]);

    expect(report.items[ReportKind.folderMoved], [const ReportItem('b', 'a')]);
    expect(report.items[ReportKind.fixFailed]!.single.path, 'c');
    final lines = [
      for (final l in const LineSplitter().convert(
        file('${m.folder}/${MigrationJournal.fileName}').readAsStringSync(),
      ))
        jsonDecode(l) as Map,
    ];
    expect(lines.first, {
      'op': 'fixStart',
      'fix': 1,
      'kind': 'organizeTitle',
      'path': 'a',
    });
    expect(lines[1], {'op': 'move', 'from': 'a', 'to': 'b'});
    expect(
      [
        for (final l in lines)
          if (l['op'] case 'fixStart' || 'fixEnd') l,
      ].skip(1),
      [
        {'op': 'fixEnd', 'fix': 1, 'ok': true},
        {'op': 'fixStart', 'fix': 2, 'kind': 'organizeTitle', 'path': 'c'},
        {'op': 'fixEnd', 'fix': 2, 'ok': false},
      ],
    );
    expect(m.journal.unfinishedFix, 2);
    // Adopted, its date kept.
    expect(idOf('b/v/v.rpp'), isNotNull);
    expect(file('b/v/v.rpp').lastModifiedSync(), date);
    expect(await noLoss(m), isTrue);
  });

  test('organizes a title: one version folder per project', () async {
    title(song);
    put(
      '$song/a.rpp',
      rpp([r'audio\x.wav', 'take.wav', 'shared.wav'], record: 'audio'),
    );
    put('$song/b.rpp', rpp(['shared.wav']));
    put('$song/audio/x.wav', 'x');
    put('$song/take.wav', 'take');
    put('$song/shared.wav', 'shared');
    final date = DateTime(2021, 5, 6, 7, 8, 9);
    file('$song/a.rpp').setLastModifiedSync(date);
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [
        version(
          '$song/a.rpp',
          folder: 'A take',
          owner: const MemberId('alice'),
          status: 'mixing',
        ),
        version('$song/b.rpp'),
      ]),
    ]);

    expect(report.hasErrors || report.hasWarnings, isFalse);
    const a = '$song/A take/a.rpp';
    const b = '$song/b/b.rpp';
    expect(media(a), r'Media\x.wav|Media\take.wav|Media\shared.wav');
    expect(media(b), r'Media\shared.wav');
    expect(RppProject.parse(file(a).readAsStringSync()).recordPath, 'Media');
    // The shared media is copied for the first project, moved for the last.
    expect(report.items[ReportKind.mediaCopied], [
      const ReportItem('$song/A take/Media/shared.wav', '$song/shared.wav'),
    ]);
    expect(report.items[ReportKind.mediaMoved], hasLength(3));
    expect(file('$song/shared.wav').existsSync(), isFalse);
    expect(file('$song/b/Media/shared.wav').readAsStringSync(), 'shared');
    expect(Directory(file('$song/A take/Renders').path).existsSync(), isTrue);
    expect(report.items[ReportKind.projectMoved]!.map((i) => i.path), [a, b]);
    // Adopted, label, owner and status in the node file, date kept.
    final id = idOf(a)!;
    final n = node(song);
    expect(n['versionLabels'], {id: 'A take', idOf(b): 'b'});
    expect(n['versionOwners'], {id: 'alice'});
    expect(n['versionStatuses'], {id: 'mixing'});
    expect(file(a).lastModifiedSync(), date);
    expect(await noLoss(m), isTrue);
  });

  test('a project alone in a folder moves with it, or stays', () async {
    title(song);
    put('$song/v1/song-final.rpp', rpp([r'Media\x.wav'], record: 'Media'));
    put('$song/v1/Media/x.wav', 'x');
    put('$song/v1/Backups/song-final.rpp-bak', 'bak');
    put('$song/v2/v2.rpp', rpp([r'Media\y.wav'], record: 'Media'));
    put('$song/v2/Media/y.wav', 'y');
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [
        version('$song/v1/song-final.rpp', folder: 'Final'),
        version('$song/v2/v2.rpp'),
      ]),
    ]);

    expect(report.items[ReportKind.folderMoved], [
      const ReportItem('$song/Final', '$song/v1'),
    ]);
    expect(media('$song/Final/song-final.rpp'), r'Media\x.wav');
    expect(file('$song/Final/Media/x.wav').existsSync(), isTrue);
    expect(file('$song/Final/Backups/song-final.rpp-bak').existsSync(), isTrue);
    expect(file('$song/v2/v2.rpp').existsSync(), isTrue);
    expect(report.items[ReportKind.mediaMoved], isNull);
    expect(await noLoss(m), isTrue);
  });

  test('several projects of one folder: each gets its own', () async {
    title(song);
    put('$song/v1/v1.rpp', rpp([r'Media\x.wav'], record: 'Media'));
    put('$song/v1/v1 copy.rpp', rpp([r'Media\x.wav'], record: 'Media'));
    put('$song/v1/Media/x.wav', 'x');
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [
        version('$song/v1/v1.rpp'),
        // Taken by the first one: a free name.
        version('$song/v1/v1 copy.rpp', folder: 'v1'),
      ]),
    ]);

    expect(file('$song/v1/v1.rpp').existsSync(), isTrue);
    expect(file('$song/v1 (2)/v1 copy.rpp').existsSync(), isTrue);
    expect(report.items[ReportKind.fileRenamed], [
      const ReportItem('$song/v1 (2)', 'v1'),
    ]);
    // Used by both: copied for the second.
    expect(file('$song/v1/Media/x.wav').existsSync(), isTrue);
    expect(file('$song/v1 (2)/Media/x.wav').existsSync(), isTrue);
    expect(media('$song/v1 (2)/v1 copy.rpp'), r'Media\x.wav');
    expect(await noLoss(m), isTrue);
  });

  test('member and status subfolders give one version each', () async {
    title(song);
    put('$song/Alice/a.rpp', rpp(['a.wav']));
    put('$song/Alice/a.wav', 'a');
    put('$song/live/b.rpp', rpp([]));
    put('$song/live/c.rpp', rpp([]));
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [
        version('$song/Alice/a.rpp', owner: const MemberId('alice')),
        version('$song/live/b.rpp', status: 'live', statusFolder: 'live'),
        version('$song/live/c.rpp', statusFolder: 'live'),
      ]),
    ]);

    // Alone in its member folder: the folder becomes its version folder.
    expect(file('$song/a/a.rpp').existsSync(), isTrue);
    expect(media('$song/a/a.rpp'), r'Media\a.wav');
    expect(file('$song/b/b.rpp').existsSync(), isTrue);
    expect(file('$song/c/c.rpp').existsSync(), isTrue);
    expect(report.items[ReportKind.statusFolderUnmatched], [
      const ReportItem('$song/c/c.rpp', 'live'),
    ]);
    final n = node(song);
    expect(n['versionOwners'], {idOf('$song/a/a.rpp'): 'alice'});
    expect(n['versionStatuses'], {idOf('$song/b/b.rpp'): 'live'});
    expect(await noLoss(m), isTrue);
  });

  test('moves the title to its position first, unless taken', () async {
    title('Artist/Lonely');
    put('Artist/Lonely/v1/v1.rpp', rpp([], record: 'Media'));
    title('Artist/Taken');
    put('Artist/Taken/v1/v1.rpp', rpp([], record: 'Media'));
    put('Artist/Album/Taken/x.txt', 'x');
    final m = await migration();

    final report = await applyFixes(m, [
      OrganizeTitle('Artist/Lonely', 'Artist/_Unassigned/Lonely', [
        version('Artist/Lonely/v1/v1.rpp'),
      ], level: 'title'),
      OrganizeTitle('Artist/Taken', 'Artist/Album/Taken', [
        version('Artist/Taken/v1/v1.rpp'),
      ], level: 'title'),
      OrganizeTitle('Artist/Taken', 'Artist/Taken/Inner', [
        version('Artist/Taken/v1/v1.rpp'),
      ], level: 'title'),
    ]);

    expect(file('Artist/_Unassigned/Lonely/v1/v1.rpp').existsSync(), isTrue);
    expect(report.items[ReportKind.targetExists], [
      const ReportItem('Artist/Taken', 'Artist/Album/Taken'),
    ]);
    expect(report.items[ReportKind.fixFailed]!.single.path, 'Artist/Taken');
    expect(file('Artist/Taken/v1/v1.rpp').existsSync(), isTrue);
    expect(await noLoss(m), isTrue);
  });

  test('a candidate above the title level makes a new title', () async {
    put('Artist/song.rpp', rpp(['x.wav']));
    put('Artist/x.wav', 'x');
    final m = await migration();

    await applyFixes(m, [
      OrganizeTitle(
        'Artist',
        'Artist/_Unassigned/song',
        [version('Artist/song.rpp')],
        level: 'title',
        titleFolder: false,
      ),
    ]);

    const dir = 'Artist/_Unassigned/song';
    expect(node(dir)['level'], 'title');
    expect(media('$dir/song/song.rpp'), r'Media\x.wav');
    expect(file('$dir/song/Media/x.wav').existsSync(), isTrue);
    expect(file('Artist/x.wav').existsSync(), isFalse);
    expect(await noLoss(m), isTrue);
  });

  test('attaches versions to an existing title, names freed', () async {
    title(song);
    put('$song/v1/v1.rpp', rpp([], record: 'Media'));
    title('Old/Song');
    put('Old/Song/v1/v1.rpp', rpp([r'Media\x.wav'], record: 'Media'));
    put('Old/Song/v1/Media/x.wav', 'x');
    final m = await migration();

    final report = await applyFixes(m, [
      AttachVersions('Old/Song', song, [
        version('Old/Song/v1/v1.rpp', status: 'demo'),
      ], level: 'title'),
      AttachVersions('Old/Song', 'Missing', const [], level: 'title'),
    ]);

    const moved = '$song/v1 (2)/v1.rpp';
    expect(media(moved), r'Media\x.wav');
    expect(file('$song/v1 (2)/Media/x.wav').existsSync(), isTrue);
    expect(report.items[ReportKind.fileRenamed], [
      const ReportItem('$song/v1 (2)', 'v1'),
    ]);
    expect(node(song)['versionStatuses'], {idOf(moved): 'demo'});
    // What is left of the source stays.
    expect(file('Old/Song/.node.json').existsSync(), isTrue);
    expect(report.items[ReportKind.fixFailed]!.single.path, 'Old/Song');
    expect(await noLoss(m), isTrue);
  });

  test('moves a project to another title, created if missing', () async {
    title(song);
    put('$song/a.rpp', rpp(['x.wav', 'y.wav']));
    put('$song/b.rpp', rpp(['y.wav']));
    put('$song/x.wav', 'x');
    put('$song/y.wav', 'y');
    put('Other/file.txt', 'not a title');
    final m = await migration();

    final usage = {
      '$song/x.wav': ['$song/a.rpp'],
      '$song/y.wav': ['$song/a.rpp', '$song/b.rpp'],
    };
    final report = await applyFixes(m, [
      MoveProject(version('$song/a.rpp'), 'Band/New', level: 'title'),
      MoveProject(version('$song/b.rpp'), 'Other', level: 'title'),
    ], usage: usage);

    expect(node('Band/New')['level'], 'title');
    expect(media('Band/New/a/a.rpp'), r'Media\x.wav|Media\y.wav');
    // Used by the other project: copied.
    expect(file('$song/y.wav').existsSync(), isTrue);
    expect(file('$song/x.wav').existsSync(), isFalse);
    expect(report.items[ReportKind.targetExists], [
      const ReportItem('$song/b.rpp', 'Other'),
    ]);
    expect(await noLoss(m), isTrue);
  });

  test(
    'a project alone in its folder moves with it to another title',
    () async {
      put('Loose/v1/v1.rpp', rpp([r'Media\x.wav'], record: 'Media'));
      put('Loose/v1/Media/x.wav', 'x');
      final m = await migration();

      await applyFixes(m, [
        MoveProject(
          version('Loose/v1/v1.rpp', folder: 'Take'),
          song,
          level: 'title',
        ),
      ]);

      expect(media('$song/Take/v1.rpp'), r'Media\x.wav');
      expect(file('$song/Take/Media/x.wav').existsSync(), isTrue);
      expect(await noLoss(m), isTrue);
    },
  );

  test('a media used by another title is copied', () async {
    title(song);
    put('$song/a.rpp', rpp([r'..\Other\x.wav']));
    put('Band/Album/Other/x.wav', 'x');
    final m = await migration();

    final report = await applyFixes(
      m,
      [
        organize(song, [version('$song/a.rpp')]),
      ],
      usage: {
        'Band/Album/Other/x.wav': ['$song/a.rpp', 'Band/Album/Other/o.rpp'],
      },
    );

    expect(report.items[ReportKind.mediaCopied], hasLength(1));
    expect(file('Band/Album/Other/x.wav').existsSync(), isTrue);
    expect(media('$song/a/a.rpp'), r'Media\x.wav');
  });

  test('a version with a missing or external media is left intact', () async {
    title(song);
    final text = rpp([r'audio\x.wav', 'gone.wav', r'C:\abs.wav']);
    put('$song/a.rpp', text);
    put('$song/b.rpp', rpp([r'audio\x.wav']));
    put('$song/audio/x.wav', 'x');
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [version('$song/a.rpp'), version('$song/b.rpp')]),
    ]);

    expect(report.items[ReportKind.missingMedia], [
      const ReportItem('$song/a.rpp', 'gone.wav'),
    ]);
    expect(report.items[ReportKind.externalMedia], [
      const ReportItem('$song/a.rpp', r'C:\abs.wav'),
    ]);
    expect(file('$song/a.rpp').readAsStringSync(), text);
    // Its media are kept for it: copied for the other one.
    expect(file('$song/audio/x.wav').existsSync(), isTrue);
    expect(file('$song/b/Media/x.wav').existsSync(), isTrue);
  });

  test(
    'forced, a version with a missing or external media is organized',
    () async {
      title(song);
      put('$song/a.rpp', rpp([r'audio\x.wav', 'gone.wav', r'C:\abs.wav']));
      put('$song/audio/x.wav', 'x');
      final date = DateTime(2022, 2, 3);
      file('$song/a.rpp').setLastModifiedSync(date);
      final m = await migration();

      final report = await applyFixes(m, [
        OrganizeTitle(
          song,
          song,
          [version('$song/a.rpp')],
          level: 'title',
          force: true,
        ),
      ]);

      // Still reported: REAPER asks for them when the project opens.
      expect(report.items[ReportKind.missingMedia], hasLength(1));
      expect(report.items[ReportKind.externalMedia], hasLength(1));
      expect(media('$song/a/a.rpp'), r'Media\x.wav|gone.wav|C:\abs.wav');
      expect(file('$song/a/Media/x.wav').existsSync(), isTrue);
      expect(file('$song/a/a.rpp').lastModifiedSync(), date);
      expect(await noLoss(m), isTrue);
    },
  );

  test('forced, a valid reference outside a moved title follows', () async {
    title('Artist/Lonely');
    put('Artist/Lonely/a.rpp', rpp([r'..\shared.wav', 'gone.wav']));
    put('Artist/shared.wav', 'shared');
    final m = await migration();

    await applyFixes(m, [
      OrganizeTitle(
        'Artist/Lonely',
        'Artist/_Unassigned/Lonely',
        [version('Artist/Lonely/a.rpp')],
        level: 'title',
        force: true,
      ),
    ]);

    const moved = 'Artist/_Unassigned/Lonely/a';
    // Only the reference already wrong is left as written.
    expect(media('$moved/a.rpp'), r'Media\shared.wav|gone.wav');
    expect(file('$moved/Media/shared.wav').readAsStringSync(), 'shared');
    expect(await noLoss(m), isTrue);
  });

  test('a subproject takes its proxy along, its references follow', () async {
    title(song);
    put('$song/a.rpp', rpp(['sub.rpp']));
    put('$song/sub.rpp', rpp([r'audio\v.wav']));
    put('$song/sub.rpp-PROX', 'proxy');
    put('$song/audio/v.wav', 'voice');
    final date = DateTime(2019, 3, 4);
    file('$song/sub.rpp').setLastModifiedSync(date);
    final m = await migration();

    await applyFixes(m, [
      organize(song, [version('$song/a.rpp')]),
    ]);

    expect(media('$song/a/a.rpp'), r'Media\sub.rpp');
    expect(file('$song/a/Media/sub.rpp-PROX').readAsStringSync(), 'proxy');
    expect(media('$song/a/Media/sub.rpp'), r'..\..\audio\v.wav');
    expect(file('$song/a/Media/sub.rpp').lastModifiedSync(), date);
    expect(await noLoss(m), isTrue);
  });

  test('a subproject follows a media moved after it', () async {
    title(song);
    put('$song/a.rpp', rpp([r'Media\sub.rpp', r'audio\v.wav']));
    put('$song/Media/sub.rpp', rpp([r'..\audio\v.wav']));
    put('$song/audio/v.wav', 'voice');
    final m = await migration();

    await applyFixes(m, [
      organize(song, [version('$song/a.rpp')]),
    ]);

    // In a media folder, not a version: moved.
    expect(file('$song/Media/sub.rpp').existsSync(), isFalse);
    expect(media('$song/a/a.rpp'), r'Media\sub.rpp|Media\v.wav');
    expect(media('$song/a/Media/sub.rpp'), 'v.wav');
    expect(file('$song/a/Media/v.wav').readAsStringSync(), 'voice');
    expect(await noLoss(m), isTrue);
  });

  for (final subFirst in [false, true]) {
    test('a subproject that is a version of the fix keeps its media'
        '${subFirst ? ', organized first' : ''}', () async {
      title(song);
      put('$song/a.rpp', rpp(['sub.rpp']));
      put('$song/sub.rpp', rpp([r'audio\v.wav']));
      put('$song/audio/v.wav', 'voice');
      final m = await migration();
      final versions = [version('$song/a.rpp'), version('$song/sub.rpp')];

      await applyFixes(m, [
        organize(song, subFirst ? versions.reversed.toList() : versions),
      ]);

      expect(media('$song/sub/sub.rpp'), r'Media\v.wav');
      expect(media('$song/a/Media/sub.rpp'), r'..\..\sub\Media\v.wav');
      expect(file('$song/sub/Media/v.wav').readAsStringSync(), 'voice');
      expect(await noLoss(m), isTrue);
    });
  }

  test('a Save As copy in the fix gets its own version id', () async {
    const id = VersionId('01JKNOWNVERSION0000000003');
    final text = rpp([]).replaceFirst(
      RegExp(r'>\n$'),
      '  <EXTSTATE\n    <REAHARVEST\n      VERSIONID $id\n    >\n  >\n>\n',
    );
    title(song);
    put('$song/a.rpp', text);
    put('$song/b.rpp', text);
    final m = await migration();

    await applyFixes(m, [
      organize(song, [version('$song/a.rpp'), version('$song/b.rpp')]),
    ]);

    expect(idOf('$song/a/a.rpp'), id);
    final copy = idOf('$song/b/b.rpp');
    expect(copy, isNot(anyOf(isNull, id)));
    expect(node(song)['versionLabels'], {'$id': 'a', '$copy': 'b'});
  });

  test('a copy attached to its title gets its own version id', () async {
    const id = VersionId('01JKNOWNVERSION0000000004');
    final text = rpp([]).replaceFirst(
      RegExp(r'>\n$'),
      '  <EXTSTATE\n    <REAHARVEST\n      VERSIONID $id\n    >\n  >\n>\n',
    );
    title(song);
    put('$song/v1/v1.rpp', text);
    put('Band/Album/Copy/v.rpp', text);
    final m = await migration();

    await applyFixes(m, [
      AttachVersions('Band/Album/Copy', song, [
        version('Band/Album/Copy/v.rpp'),
      ], level: 'title'),
    ]);

    expect(idOf('$song/v1/v1.rpp'), id);
    final copy = idOf('$song/v/v.rpp');
    expect(copy, isNot(anyOf(isNull, id)));
    expect(node(song)['versionLabels'], {'$copy': 'v'});
  });

  test('a subproject in the media folder follows a media moved', () async {
    title(song);
    put('$song/X/x.rpp', rpp([r'Media\sub.rpp', 'loop.wav']));
    put('$song/X/Media/sub.rpp', rpp([r'..\loop.wav']));
    put('$song/X/loop.wav', 'loop');
    final m = await migration();

    await applyFixes(m, [
      organize(song, [version('$song/X/x.rpp', folder: 'X')]),
    ]);

    expect(media('$song/X/x.rpp'), r'Media\sub.rpp|Media\loop.wav');
    expect(media('$song/X/Media/sub.rpp'), 'loop.wav');
    expect(file('$song/X/Media/loop.wav').readAsStringSync(), 'loop');
    expect(await noLoss(m), isTrue);
  });

  test('a subproject that is a version too is copied', () async {
    title(song);
    put('$song/a.rpp', rpp(['sub.rpp']));
    put('$song/sub.rpp', rpp([], record: 'Media'));
    final m = await migration();

    await applyFixes(m, [
      organize(song, [version('$song/a.rpp'), version('$song/sub.rpp')]),
    ]);

    expect(file('$song/a/Media/sub.rpp').existsSync(), isTrue);
    expect(file('$song/sub/sub.rpp').existsSync(), isTrue);
  });

  test('a media name taken twice leaves the version intact', () async {
    title(song);
    final text = rpp([r'one\x.wav', r'two\x.wav']);
    put('$song/a.rpp', text);
    put('$song/one/x.wav', '1');
    put('$song/two/x.wav', '2');
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [version('$song/a.rpp')]),
    ]);

    // Nothing else to do: the fix fails.
    expect(
      report.items[ReportKind.fixFailed]!.single.detail,
      contains('Name taken in its media folder: x.wav'),
    );
    expect(file('$song/a.rpp').readAsStringSync(), text);
  });

  test('a fix with an unreadable project changes nothing', () async {
    title(song);
    put('$song/a.rpp', rpp([r'audio\v.wav']));
    put('$song/audio/v.wav', 'v');
    file('$song/bad.rpp').writeAsBytesSync([0xC3, 0x28]);
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [version('$song/a.rpp'), version('$song/bad.rpp')]),
    ]);

    expect(report.items[ReportKind.fixFailed]!.single.path, song);
    expect(file('$song/audio/v.wav').existsSync(), isTrue);
    expect(media('$song/a.rpp'), r'audio\v.wav');
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
    title(song);
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

    final report = await applyFixes(m, [
      organize(song, [for (final name in sources.keys) version('$song/$name')]),
    ]);

    expect(report.hasErrors || report.hasWarnings, isFalse, reason: '$report');
    for (final MapEntry(key: name, value: before) in sources.entries) {
      final dir = '$song/${p.posix.basenameWithoutExtension(name)}';
      final after = file('$dir/$name').readAsStringSync();
      final project = RppProject.parse(after);
      expect(resolveMedia(dir, project.recordPath!), '$dir/Media');
      final mediaBefore = RppProject.parse(before).mediaFiles;
      expect(project.mediaFiles, hasLength(mediaBefore.length));
      for (final ref in project.mediaFiles) {
        final path = resolveMedia(dir, ref);
        expect(path, startsWith('$dir/Media/'));
        expect(file(path).existsSync(), isTrue, reason: '$name: $ref');
      }
    }
    expect(await noLoss(m), isTrue);
  });

  test('leaves the media-paths fixture intact and reports it', () async {
    title(song);
    final text = File('$fixtures/media-paths.rpp').readAsStringSync();
    put('$song/media-paths.rpp', text);
    for (final name in ['a.wav', 'Loops/loop.wav', 'b.flac', 'c.mp3']) {
      put('$song/$name', name);
    }
    put('$song/d.mid', 'midi');
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [version('$song/media-paths.rpp')]),
    ]);

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
    expect(file('$song/Loops/loop.wav').existsSync(), isTrue);
  });

  test('leaves a record path written .\\Media as is', () async {
    title(song);
    final text = rpp([r'Media\a.wav'], record: r'.\Media');
    put('$song/v/Media/a.wav', 'a');
    put('$song/v/v.rpp', text);
    final m = await migration();

    final report = await applyFixes(m, [
      organize(song, [version('$song/v/v.rpp')]),
    ]);

    expect(report.items.keys, [ReportKind.mediaNormalized]);
    final after = file('$song/v/v.rpp').readAsStringSync();
    expect(after, contains(r'RECORD_PATH ".\Media" ""'));
    expect(media('$song/v/v.rpp'), r'Media\a.wav');
  });

  group('preview', () {
    test('plans the fixes of a library folder, nothing written', () async {
      title(song);
      put('$song/a.rpp', rpp(['x.wav']));
      put('$song/x.wav', 'x');
      final fix = organize(song, [version('$song/a.rpp')]);

      final preview = planFixesOn(root.path, [
        fix,
        organize('Gone', [version('Gone/g.rpp')]),
      ], usage: const {});
      final plans = await preview.plans;
      await preview.cancel();

      final ops = plans[song]!.operations;
      expect(ops.whereType<MoveFile>().map((o) => '$o'), [
        'move $song/a.rpp -> $song/a/a.rpp',
        'move $song/x.wav -> $song/a/Media/x.wav',
      ]);
      expect(ops.whereType<CreateFolder>(), hasLength(2));
      expect(ops.whereType<SetVersionEntries>().single.label, 'a');
      expect(ops.whereType<RewriteProject>().single.versionId, isNotNull);
      expect(countPlan(plans[song]!), (
        moved: 1,
        copied: 0,
        rewritten: 1,
        blocked: 0,
      ));
      expect(plans['Gone']!.blocked.items[ReportKind.fixFailed], hasLength(1));
      expect(file('$song/a.rpp').existsSync(), isTrue);
    });

    test('a cancelled preview fails at once', () async {
      title(song);
      put('$song/a.rpp', rpp([]));
      final preview = planFixesOn(root.path, [
        organize(song, [version('$song/a.rpp')]),
      ], usage: const {});

      final cancelled = preview.cancel();
      await expectLater(preview.plans, throwsA(isA<PreviewCancelled>()));
      await cancelled;
    });
  });

  test('media usage lists the versions of titles and candidates', () {
    Version v(String fileName, List<String> media) => Version(
      fileName: fileName,
      modified: DateTime(2026),
      size: 0,
      media: media,
    );
    final usage = mediaUsage(
      ScanResult(
        titles: [
          Title(
            id: NodeId.generate(),
            libraryId: const LibraryId('L'),
            path: song,
            levels: const {},
            versions: [
              v('a/a.rpp', [r'Media\x.wav', r'C:\abs.wav']),
            ],
          ),
        ],
        candidates: [
          ScanCandidate(
            root: song,
            title: song,
            versions: [
              v('a/a.rpp', [r'Media\x.wav']),
            ],
          ),
          ScanCandidate(
            root: 'Loose',
            versions: [
              v('b.rpp', [r'..\Band\Album\Song\a\Media\x.wav']),
            ],
          ),
        ],
      ),
    );
    expect(usage, {
      '$song/a/Media/x.wav': ['$song/a/a.rpp', 'Loose/b.rpp'],
    });
  });

  test('describes its fixes and operations', () {
    final fix = MoveProject(
      version('a/b.rpp', owner: const MemberId('m'), status: 'demo'),
      'T',
      level: 'title',
    );
    expect('$fix', 'moveProject a/b.rpp -> T\n  a/b.rpp -> b, b, m, demo');
    expect(
      '${AttachVersions('a', 'T', const [], level: 'title', force: true)}',
      'attachVersions a -> T, forced',
    );
    const entries = SetVersionEntries(
      'T',
      VersionId('01J'),
      label: 'l',
      owner: MemberId('m'),
      status: 's',
    );
    expect('$entries', 'version 01J in T: l, m, s');
    const rewrite = RewriteProject(
      'a.rpp',
      {'x': 'y'},
      recordPath: ['Media', ''],
      versionId: VersionId('01J'),
    );
    expect(
      '$rewrite',
      'rewrite a.rpp, x -> y, RECORD_PATH Media , VERSIONID 01J',
    );
    expect('${const CopyFile('a', 'b')}', 'copy a -> b');
    expect('${const CreateFolder('a')}', 'create a/');
    expect('${const CreateTitle('a', 'title')}', 'create title a');
  });
}
