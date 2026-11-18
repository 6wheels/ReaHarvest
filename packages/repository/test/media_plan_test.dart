import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const song = 'Band/Album/Song';

StorageEntry entry(String path, {bool directory = false}) => StorageEntry(
  path: path,
  isDirectory: directory,
  size: 1,
  modified: DateTime(2026),
);

/// Facts of a fix built in memory: [files] and [projects] (with their
/// facts) by path, listed when inside [root]; [target] exists when
/// [targetNames] is given.
FixFacts facts({
  Set<String> files = const {},
  Map<String, ProjectFacts> projects = const {},
  Map<String, String> unreadable = const {},
  String root = song,
  String? target,
  Set<String>? targetNames,
}) {
  final all = {...files, ...projects.keys};
  return FixFacts(
    entries: [
      for (final path in all)
        if (path.startsWith('$root/')) entry(path),
      if (!all.contains('$root/.node.json')) entry('$root/.node.json'),
    ],
    projects: projects,
    unreadable: unreadable,
    files: {for (final path in all) path: entry(path)},
    target: targetNames == null ? null : entry(target!, directory: true),
    targetNames: targetNames ?? const {},
  );
}

/// Facts of an adopted project referencing [media], record path `Media`.
ProjectFacts project(List<String> media, {Set<String> named = const {}}) =>
    ProjectFacts(
      media,
      recordPath: const ['Media', ''],
      namedFiles: named,
      versionId: const VersionId('01JADOPTED'),
    );

FixVersion version(String source, String folder) =>
    FixVersion(source, folder: folder, label: folder);

OrganizeTitle organize(List<FixVersion> versions) =>
    OrganizeTitle(song, song, versions, level: 'title');

/// Moves and copies of [plan], as text.
List<String> files(MediaPlan plan) => [
  for (final op in plan.operations)
    if (op is MoveFile || op is CopyFile) '$op',
];

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

void main() {
  test('hashes a streamed content with XXH3-64', () async {
    expect(await xxh3Hash(const Stream.empty()), '2d06800538d394c2');
    expect(
      await xxh3Hash(Stream.fromIterable([utf8.encode('a'), utf8.encode('b')])),
      await xxh3Hash(Stream.value(utf8.encode('ab'))),
    );
  });

  group('plan', () {
    test('a media is copied for each user, moved for the last one', () {
      final plan = planFix(
        organize([version('$song/a.rpp', 'a'), version('$song/b.rpp', 'b')]),
        facts(
          files: {'$song/x.wav'},
          projects: {
            '$song/a.rpp': project(['x.wav']),
            '$song/b.rpp': project(['x.wav']),
          },
        ),
      );

      expect(files(plan), [
        'move $song/a.rpp -> $song/a/a.rpp',
        'copy $song/x.wav -> $song/a/Media/x.wav',
        'move $song/b.rpp -> $song/b/b.rpp',
        'move $song/x.wav -> $song/b/Media/x.wav',
      ]);
      expect(countPlan(plan), (moved: 1, copied: 1, rewritten: 2, blocked: 0));
    });

    test('a media used by a project outside the fix is copied', () {
      final plan = planFix(
        organize([version('$song/a.rpp', 'a')]),
        facts(
          files: {'$song/x.wav'},
          projects: {
            '$song/a.rpp': project(['x.wav']),
          },
        ),
        usage: {
          '$song/x.wav': ['$song/a.rpp', 'Other/o.rpp'],
        },
      );

      expect(files(plan).last, 'copy $song/x.wav -> $song/a/Media/x.wav');
    });

    test('a folder whose files are used from outside is not moved', () {
      final plan = planFix(
        organize([version('$song/v1/a.rpp', 'Take')]),
        facts(
          files: {'$song/v1/Media/x.wav'},
          projects: {
            '$song/v1/a.rpp': project([r'Media\x.wav']),
          },
        ),
        usage: {
          '$song/v1/Media/x.wav': ['$song/v1/a.rpp', 'Other/o.rpp'],
        },
      );

      expect(files(plan), [
        'move $song/v1/a.rpp -> $song/Take/a.rpp',
        'copy $song/v1/Media/x.wav -> $song/Take/Media/x.wav',
      ]);
    });

    test('a folder whose files a version left intact uses stays', () {
      final plan = planFix(
        organize([
          version('$song/v1/a.rpp', 'Take'),
          version('$song/b.rpp', 'b'),
        ]),
        facts(
          files: {'$song/v1/Media/x.wav'},
          projects: {
            '$song/v1/a.rpp': project([r'Media\x.wav']),
            '$song/b.rpp': project([r'v1\Media\x.wav', 'gone.wav']),
          },
        ),
      );

      expect(files(plan), [
        'move $song/v1/a.rpp -> $song/Take/a.rpp',
        'copy $song/v1/Media/x.wav -> $song/Take/Media/x.wav',
      ]);
      expect(plan.blocked.items[ReportKind.missingMedia], hasLength(1));
    });

    test('a title is not moved away from what a version left uses', () {
      final plan = planFix(
        OrganizeTitle(song, 'Band/Other/Song', [
          version('$song/a.rpp', 'a'),
        ], level: 'title'),
        facts(
          files: {'Band/Album/x.wav'},
          projects: {
            '$song/a.rpp': project([r'..\x.wav', 'gone.wav']),
          },
        ),
      );

      expect(plan.operations, isEmpty);
      expect(
        plan.blocked.items[ReportKind.fixFailed]!.single.detail,
        contains('Band/Album/x.wav'),
      );
    });

    test('a project in a reserved folder never moves it', () {
      final plan = planFix(
        organize([version('$song/Media/a.rpp', 'a')]),
        facts(projects: {'$song/Media/a.rpp': project(const [])}),
      );

      expect(files(plan), ['move $song/Media/a.rpp -> $song/a/a.rpp']);
    });

    test('creates the node file of a title without one', () {
      final plan = planFix(
        OrganizeTitle('Loose', 'Loose', [
          version('Loose/a.rpp', 'a'),
        ], level: 'song'),
        FixFacts(
          entries: [entry('Loose/a.rpp')],
          projects: {'Loose/a.rpp': project(const [])},
          target: entry('Loose', directory: true),
          targetNames: const {'a.rpp'},
        ),
      );

      expect('${plan.operations.first}', 'create title Loose');
      expect((plan.operations.first as CreateTitle).level, 'song');
    });

    test('a folder that is not a title is not a target', () {
      final plan = planFix(
        AttachVersions(song, 'Band/Other', [
          version('$song/a.rpp', 'a'),
        ], level: 'title'),
        facts(
          projects: {'$song/a.rpp': project(const [])},
          target: 'Band/Other',
          targetNames: {'notes.txt'},
        ),
      );

      expect(plan.operations, isEmpty);
      expect(plan.blocked.items[ReportKind.targetExists], [
        const ReportItem(song, 'Band/Other'),
      ]);
      expect(countPlan(plan), (moved: 0, copied: 0, rewritten: 0, blocked: 1));
    });

    test('an unreadable project blocks the whole fix', () {
      final plan = planFix(
        organize([version('$song/a.rpp', 'a')]),
        facts(unreadable: {'$song/a.rpp': 'bad'}),
      );

      expect(plan.operations, isEmpty);
      expect(
        plan.blocked.items[ReportKind.fixFailed]!.single.detail,
        contains('$song/a.rpp (bad)'),
      );
    });

    test('a file named by a plugin state and not referenced stays', () {
      final plan = planFix(
        organize([version('$song/a.rpp', 'a')]),
        facts(
          files: {'$song/samples/hat.wav', '$song/x.wav'},
          projects: {
            '$song/a.rpp': project(['x.wav'], named: {'hat.wav', 'x.wav'}),
          },
        ),
      );

      expect(plan.blocked.items[ReportKind.referencedByPlugin], [
        const ReportItem('$song/samples/hat.wav', '$song/a.rpp'),
      ]);
      expect(files(plan).last, 'move $song/x.wav -> $song/a/Media/x.wav');
    });

    test('an adopted version in place, record path set: no rewrite', () {
      final plan = planFix(
        organize([version('$song/v/v.rpp', 'v')]),
        facts(
          files: {'$song/v/Media/x.wav', '$song/v/Media', '$song/v/Renders'},
          projects: {
            '$song/v/v.rpp': project([r'Media\x.wav']),
          },
        ),
      );

      expect(plan.operations.map((op) => '$op'), [
        'version 01JADOPTED in $song: v',
      ]);
    });
  });

  group('gather', () {
    late MemoryStorage storage;

    setUp(() => storage = MemoryStorage());

    test('reads each project once, one at a time, text not kept', () async {
      storage
        ..put('$song/a.rpp', rpp([r'audio\x.wav', r'.\sub.rpp']))
        ..put('$song/b.rpp', rpp([r'audio\x.wav', 'gone.wav']))
        ..put('$song/sub.rpp', rpp([r'audio\y.wav']))
        ..put('$song/sub.rpp-PROX', 'proxy')
        ..put('$song/audio/x.wav', 'x')
        ..put('Band/Album/Other/.node.json', '{}');

      final gathered = await gatherFix(
        storage,
        AttachVersions(song, 'Band/Album/Other', [
          version('$song/a.rpp', 'a'),
          version('$song/b.rpp', 'b'),
        ], level: 'title'),
      );

      expect(gathered.projects.keys, [
        '$song/a.rpp',
        '$song/b.rpp',
        '$song/sub.rpp',
      ]);
      expect(gathered.projects['$song/a.rpp']!.recordPath, ['audio-files', '']);
      expect(storage.reads, [...gathered.projects.keys]);
      expect(storage.maxOpenProjectReads, 1);
      expect(gathered.files.keys, [
        '$song/audio/x.wav',
        '$song/sub.rpp',
        '$song/sub.rpp-PROX',
      ]);
      expect(gathered.targetNames, {'.node.json'});
      expect(storage.listed, ['$song/**', 'Band/Album/Other']);
    });

    test('stops at an unreadable or missing project', () async {
      storage.put('$song/a.rpp', rpp([]));
      final gathered = await gatherFix(
        storage,
        organize([
          version('$song/a.rpp', 'a'),
          version('$song/gone.rpp', 'gone'),
        ]),
      );
      expect(gathered.unreadable.keys, ['$song/gone.rpp']);
    });

    test('lists the root of a candidate above the title level only', () async {
      storage
        ..put('a.rpp', rpp([]))
        ..put('Deep/b.rpp', rpp([]));

      await gatherFix(
        storage,
        OrganizeTitle(
          '',
          'X/a',
          [version('a.rpp', 'a')],
          level: 'title',
          titleFolder: false,
        ),
      );

      expect(storage.listed, ['']);
    });
  });

  group('apply', () {
    late MemoryStorage storage;

    setUp(() => storage = MemoryStorage());

    Future<String> hash(String path) async =>
        base64.encode(await storage.read(path).expand((c) => c).toList());

    /// Every file but the projects and the node file: moved or copied,
    /// never lost.
    Set<String> contents() => {
      for (final MapEntry(:key, :value) in storage.files.entries)
        if (!isProjectFile(key) &&
            !key.startsWith('.migration/') &&
            !key.endsWith('.node.json'))
          utf8.decode(value.bytes),
    };

    final fix = organize([
      version('$song/a.rpp', 'a'),
      version('$song/b.rpp', 'b'),
    ]);

    void title() => storage
      ..put('$song/.node.json', '{"nodeId":"${newUlid()}","level":"title"}')
      ..put('$song/a.rpp', rpp([r'audio\x.wav', r'.\sub.rpp']))
      ..put('$song/b.rpp', rpp([r'audio\x.wav', r'old\bass.wav']))
      ..put('$song/sub.rpp', rpp([r'audio\y.wav'], record: 'Media'))
      ..put('$song/sub.rpp-PROX', 'proxy')
      ..put('$song/old/bass.wav', 'bass')
      ..put('$song/audio/x.wav', 'x')
      ..put('$song/audio/y.wav', 'y');

    test('makes the operations in order, one project at a time', () async {
      title();
      final plan = planFix(fix, await gatherFix(storage, fix));
      storage.reads.clear();

      final report = await applyPlan(storage, plan);

      expect(report.items[ReportKind.mediaMoved], [
        const ReportItem('$song/a/Media/sub.rpp', '$song/sub.rpp'),
        const ReportItem('$song/b/Media/x.wav', '$song/audio/x.wav'),
        const ReportItem('$song/b/Media/bass.wav', '$song/old/bass.wav'),
      ]);
      expect(report.items[ReportKind.mediaCopied], [
        const ReportItem('$song/a/Media/x.wav', '$song/audio/x.wav'),
      ]);
      expect(report.items[ReportKind.mediaNormalized], [
        const ReportItem('$song/a/a.rpp'),
        const ReportItem('$song/b/b.rpp'),
      ]);
      // Each project read once: the subproject, then each version.
      expect(storage.reads.where(isProjectFile), [
        '$song/a/Media/sub.rpp',
        '$song/a/a.rpp',
        '$song/b/b.rpp',
      ]);
      expect(storage.maxOpenProjectReads, 1);
      expect(storage.text('$song/a/Media/sub.rpp-PROX'), 'proxy');
      expect(
        RppProject.parse(storage.text('$song/a/Media/sub.rpp')).mediaFiles,
        [r'..\..\audio\y.wav'],
      );
    });

    test('a failure stops the fix: no file lost, all journaled', () async {
      // From 2: the first change is the start line of the fix.
      for (var k = 2; ; k++) {
        storage = MemoryStorage();
        title();
        final m = Migration.start(storage);
        await m.inventory.take(hash);
        storage.failAt = storage.changes + k;

        Report report;
        try {
          report = await applyFixes(m, [fix]);
        } on InjectedFailure {
          // The end line of the fix, after its last change.
          storage.failAt = null;
          expect(contents(), {'proxy', 'bass', 'x', 'y'});
          expect(m.journal.unfinishedFix, isNotNull);
          break;
        }

        storage.failAt = null;
        // Every file is still somewhere: moved or copied, never lost.
        expect(contents(), {'proxy', 'bass', 'x', 'y'}, reason: 'change $k');
        expect(report.items.keys, contains(ReportKind.fixFailed));
        // Left to undo from the journal (#94), which records each change
        // before it is made.
        expect(m.journal.unfinishedFix, isNotNull, reason: 'change $k');
      }
    });

    test('a project rewrite fails without writing it', () async {
      final plan = (
        operations: <MediaOperation>[
          const RewriteProject('$song/a.rpp', {}, recordPath: ['日本', '']),
        ],
        blocked: const Report(),
      );
      storage.files['$song/a.rpp'] = (
        bytes: latin1.encode('${rpp([])}é'),
        modified: DateTime(2026),
      );

      await expectLater(
        applyPlan(storage, plan),
        throwsA(
          isA<ProjectEncodingException>().having(
            (e) => '$e',
            'message',
            contains('($song/a.rpp)'),
          ),
        ),
      );
      expect(latin1.decode(storage.files['$song/a.rpp']!.bytes), endsWith('é'));
    });
  });
}
