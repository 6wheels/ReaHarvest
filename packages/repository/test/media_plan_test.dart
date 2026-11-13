import 'dart:convert';
import 'dart:io';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const song = 'Band/Album/Song';
const other = 'Band/Album/Other';

StorageEntry entry(String path, int size) => StorageEntry(
  path: path,
  isDirectory: false,
  size: size,
  modified: DateTime(2026),
);

/// Facts of the title [title] built in memory: [files] by path with their
/// content (its length is the size, the content itself the hash), listed
/// when inside the title; [projects] by path, listed too.
TitleFacts facts({
  Map<String, String> files = const {},
  Map<String, ProjectFacts> projects = const {},
  Map<String, String> unreadable = const {},
  String title = song,
}) {
  final all = {...files, for (final path in projects.keys) path: path};
  return TitleFacts(
    titleDir: title,
    entries: [
      for (final MapEntry(:key, :value) in all.entries)
        if (key.startsWith('$title/')) entry(key, value.length),
    ],
    projects: projects,
    unreadable: unreadable,
    files: {
      for (final MapEntry(:key, :value) in all.entries)
        key: entry(key, value.length),
    },
    contentKeys: {
      for (final MapEntry(:key, :value) in all.entries)
        key.toLowerCase(): value,
    },
  );
}

/// Operations of [plan], as text.
List<String> ops(MediaPlan plan) => [for (final op in plan.operations) '$op'];

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
  group('plan, one test per rule of #69', () {
    test('1. a file of the title is moved once', () {
      final plan = planNormalization(
        facts(
          files: {'$song/audio/x.wav': 'x'},
          projects: {
            '$song/a.rpp': const ProjectFacts([r'audio\x.wav'], ['Media', '']),
            '$song/b.rpp': const ProjectFacts([r'.\audio\x.wav'], ['Media']),
          },
        ),
      );

      expect(ops(plan), [
        'move $song/audio/x.wav -> $song/Media/x.wav',
        r'rewrite Band/Album/Song/a.rpp, audio\x.wav -> Media\x.wav',
        r'rewrite Band/Album/Song/b.rpp, .\audio\x.wav -> Media\x.wav',
      ]);
      expect(plan.blocked.isEmpty, isTrue);
    });

    test('2. a file outside the title is copied', () {
      final plan = planNormalization(
        facts(
          files: {'$other/Media/pad.wav': 'pad'},
          projects: {
            '$song/a.rpp': const ProjectFacts(
              [r'..\Other\Media\pad.wav'],
              ['Media'],
            ),
          },
        ),
      );

      expect(ops(plan), [
        'copy $other/Media/pad.wav -> $song/Media/pad.wav',
        r'rewrite Band/Album/Song/a.rpp, ..\Other\Media\pad.wav -> '
            r'Media\pad.wav',
      ]);
    });

    test('3. a file identical to a pool file is not brought in', () {
      final plan = planNormalization(
        facts(
          files: {
            '$song/Media/bass.wav': 'bass',
            '$song/.trash/bass.wav': 'older',
            '$song/old/bass.wav': 'bass',
            '$other/Media/bass.wav': 'bass',
          },
          projects: {
            '$song/a.rpp': const ProjectFacts(
              [r'old\bass.wav', r'..\Other\Media\bass.wav'],
              ['Media'],
            ),
          },
        ),
      );

      expect(ops(plan), [
        'trash $song/old/bass.wav -> $song/.trash/bass (2).wav '
            '(same as $song/Media/bass.wav)',
        // Outside the title: left in place, the pool file used instead.
        'reuse $song/Media/bass.wav for $other/Media/bass.wav',
        r'rewrite Band/Album/Song/a.rpp, old\bass.wav -> Media\bass.wav, '
            r'..\Other\Media\bass.wav -> Media\bass.wav',
      ]);
      expect(countPlan(plan), (
        moved: 0,
        copied: 0,
        trashed: 1,
        renamed: 0,
        rewritten: 1,
        blocked: 0,
      ));
    });

    test('4. another name collision gets a free name', () {
      final plan = planNormalization(
        facts(
          files: {
            '$song/Media/bass.wav': 'bass',
            '$song/x/bass.wav': 'other bass',
            '$song/y/bass.wav': 'third bass',
            '$song/z/Bass.wav': 'other bass',
          },
          projects: {
            '$song/a.rpp': const ProjectFacts(
              [r'x\bass.wav', r'y\bass.wav', r'z\Bass.wav'],
              ['Media'],
            ),
          },
        ),
      );

      expect(ops(plan), [
        'move $song/x/bass.wav -> $song/Media/bass (2).wav',
        'move $song/y/bass.wav -> $song/Media/bass (3).wav',
        // Identical to the file brought in just before: the pool fills.
        'trash $song/z/Bass.wav -> $song/.trash/Bass.wav '
            '(same as $song/Media/Bass (2).wav)',
        r'rewrite Band/Album/Song/a.rpp, x\bass.wav -> Media\bass (2).wav, '
            r'y\bass.wav -> Media\bass (3).wav, '
            r'z\Bass.wav -> Media\Bass (2).wav',
      ]);
      expect(countPlan(plan).renamed, 2);
    });

    test('5. a subproject brought in takes its proxy along', () {
      final plan = planNormalization(
        facts(
          files: {
            '$song/audio/v.wav': 'voice',
            '$song/sub.rpp-PROX': 'proxy',
            '$other/inner.rpp-PROX': 'inner proxy',
          },
          projects: {
            '$song/main.rpp': const ProjectFacts(
              [r'.\sub.rpp', r'..\Other\inner.rpp'],
              ['Media'],
            ),
            '$song/sub.rpp': const ProjectFacts([r'audio\v.wav'], ['Media']),
            '$other/inner.rpp': const ProjectFacts([r'Media\i.wav']),
          },
        ),
      );

      expect(ops(plan), [
        'move $song/sub.rpp -> $song/Media/sub.rpp',
        'move $song/sub.rpp-PROX -> $song/Media/sub.rpp-PROX',
        'copy $other/inner.rpp -> $song/Media/inner.rpp',
        'copy $other/inner.rpp-PROX -> $song/Media/inner.rpp-PROX',
        r'rewrite Band/Album/Song/Media/inner.rpp, Media\i.wav -> '
            r'..\..\Other\Media\i.wav',
        'move $song/audio/v.wav -> $song/Media/v.wav',
        r'rewrite Band/Album/Song/main.rpp, .\sub.rpp -> Media\sub.rpp, '
            r'..\Other\inner.rpp -> Media\inner.rpp',
        // From its new place, next to its media.
        r'rewrite Band/Album/Song/Media/sub.rpp, audio\v.wav -> v.wav',
      ]);
      final rewrites = plan.operations.whereType<RewriteProject>();
      expect([for (final r in rewrites) r.reported], [false, true, true]);
      expect(countPlan(plan), (
        moved: 2,
        copied: 1,
        trashed: 0,
        renamed: 0,
        rewritten: 3,
        blocked: 0,
      ));
    });

    test('6. subprojects of the pool are normalized, record path kept', () {
      final plan = planNormalization(
        facts(
          files: {'$song/audio/v.wav': 'voice'},
          projects: {
            '$song/Media/sub.rpp': const ProjectFacts(
              [r'..\audio\v.wav'],
              ['audio-files', ''],
            ),
          },
        ),
      );

      expect(ops(plan), [
        'move $song/audio/v.wav -> $song/Media/v.wav',
        r'rewrite Band/Album/Song/Media/sub.rpp, ..\audio\v.wav -> v.wav',
      ]);
    });

    test('7. a project with a missing or external media is blocked', () {
      final plan = planNormalization(
        facts(
          files: {'$song/audio/hat.wav': 'hat'},
          projects: {
            '$song/a.rpp': const ProjectFacts([r'audio\hat.wav'], ['Media']),
            '$song/c.rpp': const ProjectFacts(
              [
                r'audio\hat.wav',
                r'gone\x.wav',
                r'D:\c.wav',
                r'..\..\..\..\up.wav',
              ],
              ['audio-files', ''],
            ),
          },
        ),
      );

      // Copied: the blocked project keeps its file.
      expect(ops(plan), [
        'copy $song/audio/hat.wav -> $song/Media/hat.wav',
        r'rewrite Band/Album/Song/a.rpp, audio\hat.wav -> Media\hat.wav',
      ]);
      expect(plan.blocked.items, {
        ReportKind.missingMedia: [
          const ReportItem('$song/c.rpp', r'gone\x.wav'),
        ],
        ReportKind.externalMedia: [
          const ReportItem('$song/c.rpp', 'D:\\c.wav\n..\\..\\..\\..\\up.wav'),
        ],
      });
      expect(countPlan(plan).blocked, 1);
    });

    test('8. files of projects not lifted yet are copied', () {
      final plan = planNormalization(
        facts(
          files: {'$song/Alice/Media/take.wav': 'take'},
          projects: {
            '$song/Alice/a.rpp': const ProjectFacts([r'Media\take.wav']),
            '$song/b.rpp': const ProjectFacts(
              [r'Alice\Media\take.wav'],
              ['Media'],
            ),
          },
        ),
      );

      expect(ops(plan), [
        'copy $song/Alice/Media/take.wav -> $song/Media/take.wav',
        r'rewrite Band/Album/Song/b.rpp, Alice\Media\take.wav -> '
            r'Media\take.wav',
      ]);
    });

    test('9. media used by no project are merged into the pool', () {
      final plan = planNormalization(
        facts(
          files: {
            '$song/Alice/Media/take.wav': 'take',
            '$song/Bob/Media/take.wav': 'take',
            '$song/Bob/notes.txt': 'notes',
            '$song/loose.mid': 'midi',
            '$song/Renders/mix.wav': 'mix',
            '$song/Backups/old.wav': 'old',
            '$song/Media/in.wav': 'in',
          },
          projects: {
            '$song/a.rpp': const ProjectFacts([], ['Media']),
          },
        ),
      );

      expect(ops(plan), [
        'move $song/Alice/Media/take.wav -> $song/Media/take.wav',
        'trash $song/Bob/Media/take.wav -> $song/.trash/take.wav '
            '(same as $song/Media/take.wav)',
        'move $song/loose.mid -> $song/Media/loose.mid',
      ]);
    });

    test('10. record path set to Media, .\\Media left as written', () {
      final plan = planNormalization(
        facts(
          projects: {
            '$song/a.rpp': const ProjectFacts([], ['audio-files', 'x']),
            '$song/b.rpp': const ProjectFacts([], [r'.\Media', '']),
            '$song/c.rpp': const ProjectFacts([]),
          },
        ),
      );

      expect(ops(plan), [
        'rewrite $song/a.rpp, RECORD_PATH Media x',
        'rewrite $song/c.rpp, RECORD_PATH Media ',
      ]);
    });

    test('11. a title whose media another title uses is left intact', () {
      final plan = planNormalization(
        facts(
          files: {'$song/audio/x.wav': 'x'},
          projects: {
            '$song/a.rpp': const ProjectFacts([r'audio\x.wav']),
          },
        ),
        usage: {
          '$song/audio/x.wav': ['$other/b.rpp', '$song/a.rpp'],
          // In the pool: not moved, hence not blocking.
          '$song/Media/y.wav': ['$other/b.rpp'],
        },
      );

      expect(plan.operations, isEmpty);
      expect(plan.blocked.items, {
        ReportKind.mediaUsedElsewhere: [
          const ReportItem('$song/audio/x.wav', '$other/b.rpp'),
        ],
      });
    });

    test('12. the title is left intact if a project cannot be read', () {
      final plan = planNormalization(
        facts(
          files: {'$song/audio/x.wav': 'x'},
          projects: {
            '$song/a.rpp': const ProjectFacts([r'audio\x.wav']),
          },
          unreadable: {'$song/bad.rpp': 'Not a project'},
        ),
      );

      expect(plan.operations, isEmpty);
      expect(plan.blocked.items, {
        ReportKind.fixFailed: [
          const ReportItem(
            song,
            'Project unreadable, nothing can be changed in this title: '
            '$song/bad.rpp (Not a project)',
          ),
        ],
      });
    });

    test('7. a blocked subproject is copied, never moved', () {
      final plan = planNormalization(
        facts(
          files: {'$song/audio/y.wav': 'y'},
          projects: {
            '$song/main.rpp': const ProjectFacts([r'.\sub.rpp'], ['Media']),
            '$song/sub.rpp': const ProjectFacts(
              [r'audio\y.wav', r'gone\x.wav'],
              ['Media'],
            ),
          },
        ),
      );

      expect(ops(plan), [
        'copy $song/sub.rpp -> $song/Media/sub.rpp',
        r'rewrite Band/Album/Song/Media/sub.rpp, audio\y.wav -> ..\audio\y.wav, '
            r'gone\x.wav -> ..\gone\x.wav',
        r'rewrite Band/Album/Song/main.rpp, .\sub.rpp -> Media\sub.rpp',
      ]);
      expect(plan.blocked.items.keys, [ReportKind.missingMedia]);
    });

    test('8. a subproject not lifted yet is copied, never moved', () {
      final plan = planNormalization(
        facts(
          files: {'$song/Alice/Media/y.wav': 'y'},
          projects: {
            '$song/main.rpp': const ProjectFacts([r'Alice\sub.rpp'], ['Media']),
            '$song/Alice/sub.rpp': const ProjectFacts([r'Media\y.wav']),
          },
        ),
      );

      expect(ops(plan), [
        'copy $song/Alice/sub.rpp -> $song/Media/sub.rpp',
        r'rewrite Band/Album/Song/Media/sub.rpp, Media\y.wav -> '
            r'..\Alice\Media\y.wav',
        r'rewrite Band/Album/Song/main.rpp, Alice\sub.rpp -> Media\sub.rpp',
      ]);
    });

    test('13. guided move: references kept, unshared media movable', () {
      const title = 'band/album/song';
      final move = planMove(
        const MoveFacts(
          project: 'band/a.rpp',
          titleDir: title,
          facts: ProjectFacts(
            [
              r'audio\kick.wav',
              r'audio\hat.wav',
              r'C:\abs.wav',
              r'audio\used.wav',
            ],
            [r'.\audio-files', ''],
          ),
          shared: {'band/audio/kick.wav'},
          titleNames: {'a.rpp', 'media'},
        ),
        usage: {
          'band/audio/used.wav': ['band/album/other/v.rpp'],
        },
      );

      expect(
        [for (final op in move.operations) '$op'],
        [
          'move band/a.rpp -> $title/a (2).rpp',
          r'rewrite band/album/song/a (2).rpp, '
              r'audio\kick.wav -> ..\..\audio\kick.wav, '
              r'audio\hat.wav -> ..\..\audio\hat.wav, '
              r'audio\used.wav -> ..\..\audio\used.wav, '
              // No secondary record path: none after the move either.
              r'RECORD_PATH ..\..\audio-files ',
        ],
      );
      expect(move.movable, {'band/audio/hat.wav'});
    });
  });

  group('gather', () {
    late MemoryStorage storage;

    setUp(() => storage = MemoryStorage());

    Future<String> hash(String path) async =>
        base64.encode(await storage.read(path).expand((c) => c).toList());

    test('reads each project once, one at a time, text not kept', () async {
      storage
        ..put('$song/a.rpp', rpp([r'audio\x.wav', r'.\sub.rpp']))
        ..put('$song/b.rpp', rpp([r'audio\x.wav']))
        ..put('$song/sub.rpp', rpp([r'audio\y.wav']))
        ..put('$song/Alice/c.rpp', rpp([r'Media\z.wav']))
        ..put('$song/Renders/r.rpp', rpp([]))
        ..put('$song/Backups/old.rpp', rpp([]))
        ..put('$song/audio/x.wav', 'x')
        ..put('$song/audio/y.wav', 'y');

      final gathered = await gatherTitle(storage, song, hash: hash);

      expect(gathered.projects.keys, [
        '$song/a.rpp',
        '$song/b.rpp',
        '$song/sub.rpp',
        '$song/Alice/c.rpp',
      ]);
      expect(gathered.projects['$song/a.rpp']!.recordPath, ['audio-files', '']);
      expect(storage.reads, [...gathered.projects.keys]);
      expect(storage.maxOpenProjectReads, 1);
      expect(gathered.files.keys, [
        '$song/audio/x.wav',
        '$song/sub.rpp',
        '$song/audio/y.wav',
      ]);
      expect(gathered.contentKeys, isEmpty);
    });

    test('hashes only files sharing a name and a size', () async {
      storage
        ..put('$song/a.rpp', rpp([r'x\bass.wav', r'..\Other\Media\pad.wav']))
        ..put('$song/Media/bass (2).wav', 'bass')
        ..put('$song/Media/pad.wav', 'other')
        ..put('$song/x/bass.wav', 'bass')
        ..put('$other/Media/pad.wav', 'pad')
        ..put('$song/Bob/loose.wav', 'loose');

      final gathered = await gatherTitle(storage, song, hash: hash);

      expect(gathered.contentKeys.keys, {
        '$song/x/bass.wav'.toLowerCase(),
        '$song/media/bass (2).wav'.toLowerCase(),
      });
      expect(gathered.files['$other/Media/pad.wav']!.size, 3);
    });

    test('stops at an unreadable project', () async {
      storage
        ..put('$song/a.rpp', rpp([r'audio\x.wav']))
        ..put('$song/bad.rpp', 'not a project')
        ..put('$song/c.rpp', rpp([]))
        ..put('$song/audio/x.wav', 'x');

      final gathered = await gatherTitle(storage, song, hash: hash);

      expect(gathered.unreadable.keys, ['$song/bad.rpp']);
      expect(gathered.projects.keys, ['$song/a.rpp']);
      expect(storage.reads, ['$song/a.rpp', '$song/bad.rpp']);
      expect(storage.log, isEmpty);
    });

    test('stops at an unreadable subproject', () async {
      storage
        ..put('$song/a.rpp', rpp([r'..\Other\bad.rpp', r'audio\x.wav']))
        ..put('$other/bad.rpp', 'not a project')
        ..put('$song/audio/x.wav', 'x');

      final gathered = await gatherTitle(storage, song, hash: hash);

      expect(gathered.unreadable.keys, ['$other/bad.rpp']);
    });

    test('a guided move reads its project, then the others', () async {
      storage
        ..put('band/a.rpp', rpp([r'audio\kick.wav']))
        ..put('band/b.rpp', rpp([r'audio\kick.wav', r'audio\hat.wav']))
        ..put('band/bad.rpp', 'not a project')
        ..put('band/song/a.rpp', rpp([]));

      final move = await gatherMove(storage, 'band/a.rpp', 'band/song');

      expect(move.facts.references, [r'audio\kick.wav']);
      expect(move.shared, {'band/audio/kick.wav', 'band/audio/hat.wav'});
      expect(move.titleNames, {'a.rpp'});
      expect(storage.maxOpenProjectReads, 1);
      // A new title has no entries yet.
      final fresh = await gatherMove(storage, 'band/a.rpp', 'band/new');
      expect(fresh.titleNames, isEmpty);
      storage.put('band/broken.rpp', 'not a project');
      await expectLater(
        gatherMove(storage, 'band/broken.rpp', 'band/song'),
        throwsFormatException,
      );
    });
  });

  group('apply', () {
    late MemoryStorage storage;

    setUp(() => storage = MemoryStorage());

    Future<String> hash(String path) async =>
        base64.encode(await storage.read(path).expand((c) => c).toList());

    /// Every file but the projects: moved or copied, never lost.
    Set<String> contents() => {
      for (final MapEntry(:key, :value) in storage.files.entries)
        if (!isProjectFile(key) && !key.startsWith('.migration/'))
          utf8.decode(value.bytes),
    };

    void title() => storage
      ..put('$song/a.rpp', rpp([r'audio\x.wav', r'.\sub.rpp']))
      ..put('$song/b.rpp', rpp([r'audio\x.wav', r'old\bass.wav']))
      ..put('$song/sub.rpp', rpp([r'audio\y.wav'], record: 'Media'))
      ..put('$song/sub.rpp-PROX', 'proxy')
      ..put('$song/Media/bass.wav', 'bass')
      ..put('$song/old/bass.wav', 'bass')
      ..put('$song/audio/x.wav', 'x')
      ..put('$song/audio/y.wav', 'y');

    test('makes the operations in order, one project at a time', () async {
      title();
      final plan = planNormalization(
        await gatherTitle(storage, song, hash: hash),
      );
      storage.reads.clear();

      final report = await applyPlan(storage, plan);

      expect(report.items[ReportKind.mediaMoved], [
        const ReportItem('$song/Media/x.wav', '$song/audio/x.wav'),
        const ReportItem('$song/Media/sub.rpp', '$song/sub.rpp'),
        const ReportItem('$song/Media/y.wav', '$song/audio/y.wav'),
      ]);
      expect(report.items[ReportKind.mediaTrashed], [
        const ReportItem('$song/.trash/bass.wav', '$song/Media/bass.wav'),
      ]);
      expect(report.items[ReportKind.mediaNormalized], [
        const ReportItem('$song/a.rpp'),
        const ReportItem('$song/b.rpp'),
        const ReportItem('$song/Media/sub.rpp'),
      ]);
      // The duplicate compared byte by byte first, then the projects read
      // once each; the proxy and media moved, not read.
      expect(storage.reads, [
        '$song/old/bass.wav',
        '$song/Media/bass.wav',
        '$song/a.rpp',
        '$song/b.rpp',
        '$song/Media/sub.rpp',
      ]);
      expect(storage.maxOpenProjectReads, 1);
      expect(RppProject.parse(storage.text('$song/b.rpp')).mediaFiles, [
        r'Media\x.wav',
        r'Media\bass.wav',
      ]);
      expect(storage.text('$song/Media/sub.rpp-PROX'), 'proxy');
    });

    test('a failure stops the plan: no file lost, all journaled', () async {
      // From 2: the first change is the start line of the fix.
      for (var k = 2; ; k++) {
        storage = MemoryStorage();
        title();
        final m = Migration.start(storage);
        await m.inventory.take(hash);
        storage.failAt = storage.changes + k;

        Report report;
        try {
          report = await applyFixes(m, const [
            NormalizeMedia(song),
          ], hash: hash);
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

    test('a failure before any change: normalizing again does it', () async {
      title();
      storage.failAt = 1;
      await expectLater(
        normalizeMedia(storage, song, hash: hash),
        throwsA(isA<InjectedFailure>()),
      );
      expect(storage.log, isEmpty);
      storage.failAt = null;

      final report = await normalizeMedia(storage, song, hash: hash);

      expect(report.hasErrors || report.hasWarnings, isFalse);
      for (final project in ['$song/a.rpp', '$song/b.rpp']) {
        expect(
          RppProject.parse(storage.text(project)).mediaFiles,
          everyElement(startsWith(r'Media\')),
        );
      }
      expect(RppProject.parse(storage.text('$song/Media/sub.rpp')).mediaFiles, [
        'y.wav',
      ]);
    });

    test('a duplicate that differs stops the plan before any change', () {
      storage
        ..put('$song/x/bass.wav', 'bass')
        ..put('$song/y/bass.wav', 'BASS')
        ..put('$song/Media/bass.wav', 'bass');
      // As if a stale inventory gave them the same hash.
      const plan = (
        operations: <MediaOperation>[
          MoveFile('$song/x/bass.wav', '$song/Media/bass (2).wav'),
          TrashDuplicate(
            '$song/y/bass.wav',
            '$song/.trash/bass.wav',
            '$song/Media/bass (2).wav',
            sameAs: '$song/x/bass.wav',
          ),
        ],
        blocked: Report(),
      );

      expect(
        applyPlan(storage, plan),
        throwsA(
          isA<ContentMismatch>().having(
            (e) => '$e',
            'message',
            contains('nothing was changed'),
          ),
        ),
      );
      expect(storage.log, isEmpty);
    });

    test('a reused pool file that differs stops the plan', () {
      storage
        ..put('$other/Media/bass.wav', 'bass')
        ..put('$song/Media/bass.wav', 'BASS');
      const plan = (
        operations: <MediaOperation>[
          ReuseDuplicate('$other/Media/bass.wav', '$song/Media/bass.wav'),
        ],
        blocked: Report(),
      );

      expect(applyPlan(storage, plan), throwsA(isA<ContentMismatch>()));
    });

    test('a reused pool file changes nothing', () async {
      storage
        ..put('$other/Media/bass.wav', 'bass')
        ..put('$song/Media/bass.wav', 'bass');
      const plan = (
        operations: <MediaOperation>[
          ReuseDuplicate('$other/Media/bass.wav', '$song/Media/bass.wav'),
        ],
        blocked: Report(),
      );

      expect((await applyPlan(storage, plan)).isEmpty, isTrue);
      expect(storage.log, isEmpty);
    });

    test('compares contents of any size and chunking', () async {
      storage
        ..put('a', 'same')
        ..put('b', 'same')
        ..put('c', 'diff')
        ..put('d', 'longer');
      expect(await sameContent(storage, 'a', 'b'), isTrue);
      expect(await sameContent(storage, 'a', 'c'), isFalse);
      expect(await sameContent(storage, 'a', 'd'), isFalse);
      expect(await sameContent(storage, 'a', 'none'), isFalse);
    });

    test('an unreadable title fails, journaled, nothing changed', () async {
      title();
      storage.put('$song/bad.rpp', 'not a project');
      final m = Migration.start(storage);
      await m.inventory.take(hash);
      final changes = storage.changes;

      final report = await applyFixes(m, const [
        NormalizeMedia(song),
      ], hash: hash);

      expect(
        report.items[ReportKind.fixFailed]!.single.detail,
        contains(
          'Project unreadable, nothing can be changed in this title: '
          '$song/bad.rpp',
        ),
      );
      // Only the start and end lines of the fix, the end not ok.
      expect(storage.changes, changes + 2);
      expect(m.journal.unfinishedFix, isNotNull);
    });

    test('a title used elsewhere is reported without reading', () async {
      title();

      final report = await normalizeMedia(
        storage,
        song,
        usage: {
          '$song/audio/x.wav': ['$other/v.rpp'],
        },
      );

      expect(report.items.keys, [ReportKind.mediaUsedElsewhere]);
      expect(storage.reads, isEmpty);
    });

    test('a project rewrite fails without writing it', () async {
      storage.put('$song/a.rpp', rpp([r'audio\x.wav']));
      const plan = (
        operations: <MediaOperation>[
          RewriteProject('$song/a.rpp', {r'audio\x.wav': 'Mé\u{1F3B5}'}),
        ],
        blocked: Report(),
      );
      // Read as Windows-1252, the emoji cannot be written back.
      storage.files['$song/a.rpp'] = (
        bytes: [
          ...latin1.encode(rpp([r'audio\x.wav', 'é'])),
        ],
        modified: DateTime(2026),
      );

      await expectLater(
        applyPlan(storage, plan),
        throwsA(isA<ProjectEncodingException>()),
      );
      expect(storage.log, isEmpty);
    });

    test('a guided move moves the project, then normalizes', () async {
      storage
        ..put('band/loose.rpp', rpp([r'audio\kick.wav'], record: r'.\audio'))
        ..put('band/audio/kick.wav', 'kick')
        ..put('band/song/a.rpp', rpp([], record: 'Media'));

      final report = await moveProjectToTitle(
        storage,
        'band/loose.rpp',
        'band/song',
        hash: hash,
      );

      expect(report.items[ReportKind.projectMoved], [
        const ReportItem('band/song/loose.rpp'),
      ]);
      expect(report.items[ReportKind.mediaMoved], [
        const ReportItem('band/song/Media/kick.wav', 'band/audio/kick.wav'),
      ]);
      final moved = RppProject.parse(storage.text('band/song/loose.rpp'));
      expect(moved.mediaFiles, [r'Media\kick.wav']);
      expect(moved.recordPath, 'Media');
      expect(storage.maxOpenProjectReads, 1);
    });
  });

  test('previews the plans of the titles of a library folder', () async {
    final root = Directory.systemTemp.createTempSync('reaharvest_preview_');
    addTearDown(() => root.deleteSync(recursive: true));
    final storage = MountedFolderStorage(root.path);
    await storage.write(
      '$song/a.rpp',
      Stream.value(utf8.encode(rpp([r'audio\bass.wav']))),
    );
    await storage.write('$song/audio/bass.wav', Stream.value([1, 2]));
    await storage.write('$song/Media/bass.wav', Stream.value([1, 2]));
    // Hashes from the inventory for the files unchanged since.
    await Migration.start(storage).inventory.take((path) async => 'same');

    final plans = await planNormalizationOn(root.path, const [
      song,
      'Band/None',
    ], usage: const {}).plans;

    expect(ops(plans[song]!), [
      'trash $song/audio/bass.wav -> $song/.trash/bass.wav '
          '(same as $song/Media/bass.wav)',
      'rewrite $song/a.rpp, audio\\bass.wav -> Media\\bass.wav, '
          'RECORD_PATH Media ',
    ]);
    expect(plans['Band/None']!.blocked.items.keys, [ReportKind.fixFailed]);
    // A title whose media another title uses is not read.
    final blocked = await planNormalizationOn(
      root.path,
      const [song],
      usage: {
        '$song/audio/bass.wav': ['$other/v.rpp'],
      },
    ).plans;
    expect(blocked[song]!.blocked.items.keys, [ReportKind.mediaUsedElsewhere]);
    // Nothing written.
    expect(File('${root.path}/$song/audio/bass.wav').existsSync(), isTrue);

    // An error of the isolate fails the plans.
    final broken = Directory.systemTemp.createTempSync('reaharvest_broken_');
    addTearDown(() => broken.deleteSync(recursive: true));
    File('${broken.path}/.migration').writeAsStringSync('not a folder');
    await expectLater(
      planNormalizationOn(broken.path, const [song], usage: const {}).plans,
      throwsStateError,
    );

    // Cancelled: the isolate is stopped, the plans fail.
    final cancelled = planNormalizationOn(root.path, const [
      song,
    ], usage: const {});
    final ended = cancelled.cancel();
    await expectLater(cancelled.plans, throwsA(isA<PreviewCancelled>()));
    await cancelled.cancel();
    await ended;
    // Cancelled once the isolate runs.
    final later = planNormalizationOn(root.path, const [song], usage: const {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Either done before the cancellation, or cancelled; then the isolate
    // has ended and closed its files (the folder can be deleted).
    final stopped = later.cancel();
    try {
      await later.plans;
    } on PreviewCancelled {
      // Expected when still running.
    }
    await stopped;
  });
}
