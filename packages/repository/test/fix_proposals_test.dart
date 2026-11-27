import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const _lib = LibraryId('L1');
const _alice = Member(MemberId('alice'), 'Alice');
const _statuses = {
  'idea': 'Idea',
  'writing': 'Writing',
  'recording': 'Recording',
  'mixing': 'Mixing',
  'done': 'Done',
};

Library _library({List<Member> members = const []}) => Library(
  id: _lib,
  mode: LibraryMode.local,
  layout: Layout.classic(),
  knownValues: const [
    KnownValue('Artist', [KnownValue('Album')]),
  ],
  members: members,
);

const _project = '<REAPER_PROJECT 0.1 "7.0" 0\n  RECORD_PATH "Media" ""\n>\n';

void main() {
  group('proposeStatus', () {
    test('matches a key, a label or a prefix of at least three letters', () {
      expect(proposeStatus(_statuses, 'Mix'), 'mixing');
      expect(proposeStatus(_statuses, 'rec'), 'recording');
      expect(proposeStatus(_statuses, 'Done'), 'done');
      expect(proposeStatus({'writing': 'Écriture'}, 'écriture'), 'writing');
      expect(proposeStatus(_statuses, 'demo'), isNull);
      expect(proposeStatus(_statuses, 'mi'), isNull);
    });
  });

  group('proposeFix', () {
    late MemoryStorage storage;

    setUp(() => storage = MemoryStorage());

    /// Scans the library and proposes the fix of the candidate [root].
    Future<MigrationFix> propose(String root, {Library? library}) async {
      final lib = library ?? _library();
      final result = await scan(storage, lib);
      final candidate = result.candidates.firstWhere((c) => c.root == root);
      return proposeFix(
        candidate,
        lib,
        nodes: result.nodes,
        statusLabels: _statuses,
      );
    }

    String describe(MigrationFix fix) => '$fix';

    test('organizes a title in place, one version per project', () async {
      storage
        ..put('Artist/Album/Song/a.rpp', _project)
        ..put('Artist/Album/Song/v1/take 1.rpp', _project);

      final fix = await propose('Artist/Album/Song');

      expect(fix, isA<OrganizeTitle>());
      expect((fix as OrganizeTitle).titleFolder, isTrue);
      expect(describe(fix), '''
organizeTitle Artist/Album/Song -> Artist/Album/Song
  Artist/Album/Song/a.rpp -> a, a
  Artist/Album/Song/v1/take 1.rpp -> take 1, take 1''');
      expect(fix.level, 'title');
    });

    test('member and status subfolders give owner and status', () async {
      storage
        ..put('Artist/Album/Song/Alice/mixing/a.rpp', _project)
        ..put('Artist/Album/Song/done/b.rpp', _project);

      final fix = await propose(
        'Artist/Album/Song',
        library: _library(members: [_alice]),
      );

      final [a, b] = fix.versions;
      expect(a.owner, _alice.id);
      expect(a.statusFolder, 'mixing');
      expect(a.status, 'mixing');
      expect(b.owner, isNull);
      expect(b.statusFolder, 'done');
      expect(b.status, 'done');
    });

    test('no owner when the library declares no members', () async {
      storage.put('Artist/Album/Song/Alice/a.rpp', _project);

      final fix = await propose('Artist/Album/Song');

      expect(fix.versions.single.owner, isNull);
    });

    test('label, owner and status of an adopted version', () async {
      const id = '01JKNOWNVERSION0000000000';
      storage.put(
        'Artist/Album/Song/v/v.rpp',
        _project.replaceFirst(
          '>\n',
          '  <EXTSTATE\n    <REAHARVEST\n      VERSIONID $id\n    >\n  >\n>\n',
        ),
      );
      storage.put(
        'Artist/Album/Song/.node.json',
        '{"nodeId":"${newUlid()}","level":"title",'
            '"versionLabels":{"$id":"Chorus B"},'
            '"versionOwners":{"$id":"alice"},'
            '"versionStatuses":{"$id":"done"}}',
      );
      storage.put('Artist/Album/Song/v/other.rpp', _project);

      final fix = await propose(
        'Artist/Album/Song',
        library: _library(members: [_alice]),
      );

      final adopted = fix.versions.firstWhere(
        (v) => v.source.endsWith('/v.rpp'),
      );
      expect(adopted.label, 'Chorus B');
      expect(adopted.folder, 'Chorus B');
      expect(adopted.owner, _alice.id);
      expect(adopted.status, 'done');
    });

    test('a label that cannot name a folder: the file name', () async {
      const id = '01JKNOWNVERSION0000000001';
      storage
        ..put(
          'Artist/Album/Song/v.rpp',
          _project.replaceFirst(
            '>\n',
            '  <EXTSTATE\n    <REAHARVEST\n      VERSIONID $id\n'
                '    >\n  >\n>\n',
          ),
        )
        ..put(
          'Artist/Album/Song/.node.json',
          '{"nodeId":"${newUlid()}","level":"title",'
              '"versionLabels":{"$id":"A/B"}}',
        );

      final fix = await propose('Artist/Album/Song');

      expect(fix.versions.single.label, 'A/B');
      expect(fix.versions.single.folder, 'v');
    });

    test('no valid name: a default folder name', () async {
      storage.put('Artist/Album/Song/take..rpp', _project);

      final fix = await propose('Artist/Album/Song');

      expect(fix.versions.single.folder, 'Version');
    });

    test('a title placed too high goes to its target', () async {
      storage.put('Artist/Lonely/v1/v1.rpp', _project);

      final fix = await propose('Artist/Lonely');

      expect(fix.target, 'Artist/_Unassigned/Lonely');
    });

    test('a folder at the wrong level takes its titles along', () async {
      storage.put('Album/Song/v1/v1.rpp', _project);

      final fix = await propose('Album/Song');

      expect(fix.target, 'Artist/Album/Song');
    });

    test('projects above the title level make a new title', () async {
      storage.put('Artist/song.rpp', _project);

      final fix = await propose('Artist');

      expect(fix, isA<OrganizeTitle>());
      expect((fix as OrganizeTitle).titleFolder, isFalse);
      expect(fix.target, 'Artist/_Unassigned/song');
    });

    test('projects at the library root make a new title', () async {
      storage.put('song.rpp', _project);

      final fix = await propose('');

      expect(fix.target, '_Unassigned/_Unassigned/song');
    });

    test('a candidate matched to a title is attached to it', () async {
      const id = '01JKNOWNVERSION0000000002';
      storage
        ..put(
          'Artist/Album/Song/.node.json',
          '{"nodeId":"${newUlid()}","level":"title",'
              '"versionLabels":{"$id":"Moved"}}',
        )
        ..put('Artist/Album/Song/v1/v1.rpp', _project)
        ..put(
          'Artist/Album/Copy/v/v.rpp',
          _project.replaceFirst(
            '>\n',
            '  <EXTSTATE\n    <REAHARVEST\n      VERSIONID $id\n'
                '    >\n  >\n>\n',
          ),
        );

      final fix = await propose('Artist/Album/Copy');

      expect(fix, isA<AttachVersions>());
      expect(fix.target, 'Artist/Album/Song');
      // The label the title knows it by, not its file name.
      expect(fix.versions.single.label, 'Moved');
    });

    test('the moves of a title and of its ancestors are composed', () {
      final layout = Layout.classic();
      final candidate = ScanCandidate(
        root: 'Jazz/Song',
        versions: [
          Version(fileName: 'v.rpp', modified: DateTime(2020), size: 0),
        ],
        issues: Report({
          ReportKind.titleTooHigh: [
            ReportItem.misplaced(
              'Jazz/Song',
              level: layout.leaf,
              target: 'Jazz/_Unassigned/Song',
            ),
          ],
          ReportKind.misplacedLevel: [
            ReportItem.misplaced(
              'Jazz',
              level: layout.levels.first,
              target: 'Rock',
            ),
          ],
        }),
      );
      final fix = proposeFix(candidate, _library());

      expect(fix.target, 'Rock/_Unassigned/Song');
      expect(
        [for (final m in proposedMoves(candidate)) '${m.path} -> ${m.target}'],
        ['Jazz/Song -> Jazz/_Unassigned/Song', 'Jazz -> Rock'],
      );
      // The move of the ancestor left out.
      expect(
        proposeFix(candidate, _library(), moveAncestors: false).target,
        'Jazz/_Unassigned/Song',
      );
    });

    test('a candidate above the title level has no move to compose', () {
      final candidate = ScanCandidate(
        root: 'Artist',
        versions: [
          Version(fileName: 'song.rpp', modified: DateTime(2020), size: 0),
        ],
        issues: Report({
          ReportKind.projectTooShallow: [
            ReportItem.misplaced(
              'Artist/song.rpp',
              level: Layout.classic().leaf,
            ),
          ],
        }),
      );
      expect(proposedMoves(candidate), isEmpty);
    });
  });

  group('levelSuggestions', () {
    Title title(String path, {LibraryId library = _lib}) => Title(
      id: NodeId(path),
      libraryId: library,
      path: path,
      levels: const {},
    );

    test('known values and the folders of the indexed titles', () {
      final titles = [
        title('Artist/Album/Song'),
        title('artist/Live/Tune'),
        title('Other/Album/Song'),
        // Placed too high, or of another library: left out.
        title('Artist/Lonely'),
        title('Artist/Elsewhere/Song', library: const LibraryId('L2')),
      ];
      final library = _library();

      expect(levelSuggestions(library, titles, const []), ['Artist', 'Other']);
      expect(levelSuggestions(library, titles, const ['ARTIST']), [
        'Album',
        'Live',
      ]);
      expect(levelSuggestions(library, titles, const ['Artist', 'Album']), [
        'Song',
      ]);
      expect(levelSuggestions(library, titles, const ['Nobody']), isEmpty);
      // No level below the title.
      expect(
        levelSuggestions(library, titles, const ['Artist', 'Album', 'Song']),
        isEmpty,
      );
    });

    test('nothing for a free tree', () {
      final free = Library(id: _lib, mode: LibraryMode.local, layout: null);
      expect(levelSuggestions(free, [title('a/b')], const []), isEmpty);
    });
  });

  group('layoutTarget', () {
    final layout = Layout.classic();

    test('joins the values, a missing level unassigned', () {
      expect(
        layoutTarget(layout, const [' Artist ', 'Album', 'Song']),
        'Artist/Album/Song',
      );
      expect(
        layoutTarget(layout, const ['Artist', '', 'Song']),
        'Artist/_Unassigned/Song',
      );
    });

    test('refuses a missing title or a value that cannot name a folder', () {
      for (final values in const [
        ['Artist', 'Album', ''],
        ['Artist', 'A/B', 'Song'],
        ['Artist', 'Assets', 'Song'],
        ['Artist', 'Song'],
      ]) {
        expect(layoutTarget(layout, values), isNull, reason: '$values');
      }
    });
  });
}
