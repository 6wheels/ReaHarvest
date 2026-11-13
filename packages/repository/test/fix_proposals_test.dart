import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

const _lib = LibraryId('L1');
const _other = LibraryId('L2');
const _alice = Member(MemberId('alice'), 'Alice');
const _bob = Member(MemberId('bob'), 'Bob');
const _me = Member(MemberId('me'), 'Me');
const _statuses = {
  'idea': 'Idea',
  'writing': 'Writing',
  'recording': 'Recording',
  'mixing': 'Mixing',
  'done': 'Done',
};

Library _library({List<Member> members = const [], Layout? layout}) => Library(
  id: _lib,
  mode: LibraryMode.local,
  layout: layout ?? Layout.classic(),
  members: members,
);

Title _title(
  String path, {
  LibraryId library = _lib,
  List<String> files = const [],
}) {
  final tags = Layout.classic().tagsOf(path.split('/')) ?? {};
  return Title(
    id: NodeId(path),
    libraryId: library,
    path: path,
    tags: tags,
    versions: [
      for (final f in files)
        Version(fileName: f, modified: DateTime(2026), size: 1),
    ],
  );
}

FixIssue _issue(
  String path, {
  LayoutLevel? level,
  String? target,
  LibraryId library = _lib,
}) => (
  library: library,
  item: level == null && target == null
      ? ReportItem(path)
      : ReportItem.misplaced(path, level: level, target: target),
);

FixProposals _propose(
  ReportKind kind,
  List<FixIssue> issues, {
  Map<LibraryId, Library>? libraries,
  List<Title> titles = const [],
  MemberId? identity,
  int? level,
}) => proposeFixes(
  kind,
  issues,
  libraries: libraries ?? {_lib: _library()},
  titles: titles,
  statusLabels: _statuses,
  identity: identity,
  level: level,
);

FixChoices _choices(
  FixProposals proposals, {
  Set<int>? checked,
  List<String> levelValues = const [],
  MemberId? owner,
  Map<String, String?> statuses = const {},
}) => (
  checked: checked ?? {for (var i = 0; i < proposals.items.length; i++) i},
  levelValues: levelValues,
  owner: owner,
  statuses: statuses,
);

void main() {
  const artist = LayoutLevel('artist');
  const album = LayoutLevel('album');
  const title = LayoutLevel('title');

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

  group('mergesInto', () {
    test('is true onto a folder holding titles of the library', () {
      final titles = [_title('sample artist/album/song')];
      expect(mergesInto(titles, _lib, 'X', 'sample artist'), isTrue);
      expect(mergesInto(titles, _lib, 'X', 'Sample Artist/album/song'), isTrue);
      expect(mergesInto(titles, _lib, 'a/b/c', 'a/b/c'), isFalse);
      expect(mergesInto(titles, _lib, 'X', 'Sample'), isFalse);
      expect(mergesInto(titles, _other, 'X', 'sample artist'), isFalse);
    });
  });

  group('levelValues', () {
    test('lists the values of a level under the values above it', () {
      final titles = [_title('a/x/s1'), _title('a/y/s2'), _title('b/z/s3')];
      final layout = Layout.classic();
      expect(levelValues(titles, {_lib}, layout, 0, []), ['a', 'b']);
      expect(levelValues(titles, {_lib}, layout, 1, ['a']), ['x', 'y']);
      expect(levelValues(titles, {_lib}, layout, 1, ['']), ['x', 'y', 'z']);
      expect(levelValues(titles, {_other}, layout, 0, []), isEmpty);
    });
  });

  group('title too high', () {
    final issues = [
      _issue('Song', level: title, target: 'Artist/Album/Song'),
      _issue('Other', level: title, target: 'Artist/Album/Other'),
    ];

    test('proposes the target of each item and the common values', () {
      final proposals = _propose(ReportKind.titleTooHigh, issues);
      expect(
        [for (final i in proposals.items) i.target],
        ['Artist/Album/Song', 'Artist/Album/Other'],
      );
      expect(proposals.commonValues, ['Artist', 'Album']);
      expect(proposals.level, isNull);
    });

    test('leaves a value empty when the items disagree', () {
      final proposals = _propose(ReportKind.titleTooHigh, [
        issues.first,
        _issue('Other', level: title, target: 'Artist/Other/Other'),
      ]);
      expect(proposals.commonValues, ['Artist', null]);
    });

    test('flags a target merging into an existing folder', () {
      final proposals = _propose(
        ReportKind.titleTooHigh,
        issues,
        titles: [_title('artist/album/song')],
      );
      expect([for (final i in proposals.items) i.merges], [true, false]);
    });

    test('moves to the target, level values replacing the proposals', () {
      final proposals = _propose(ReportKind.titleTooHigh, issues);
      expect(
        {
          for (final f in buildFixes(
            ReportKind.titleTooHigh,
            proposals,
            _choices(proposals, levelValues: ['', ' Band '], checked: {1}),
          )[_lib]!.cast<MoveFolder>())
            f.path: f.target,
        },
        {'Other': 'Artist/Band/Other'},
      );
    });
  });

  group('misplaced level', () {
    test('takes the parents of a folder without target, else Unassigned', () {
      final proposals = _propose(ReportKind.misplacedLevel, [
        _issue('Artist/Song', level: title),
        _issue('Song2', level: title),
      ]);
      expect(
        [for (final i in proposals.items) i.target],
        ['Artist/_Unassigned/Song', '_Unassigned/_Unassigned/Song2'],
      );
      expect(proposals.commonValues, [null, '_Unassigned']);
    });

    test('keeps the folder name at its level', () {
      final proposals = _propose(ReportKind.misplacedLevel, [
        _issue('Artist/Album', level: album, target: 'Artist/Album'),
      ]);
      expect(proposals.items.single.target, 'Artist/Album');
      expect(proposals.commonValues, ['Artist', null]);
    });
  });

  group('unknown value', () {
    final issues = [_issue('Artist/Mystery', level: album)];

    test('starts at the level of the first item', () {
      final proposals = _propose(ReportKind.unknownValue, issues);
      expect(proposals.level, 1);
      expect(proposals.items.single.target, 'Artist/Mystery');
    });

    test('is proposed again at the level chosen by the user', () {
      final proposals = _propose(ReportKind.unknownValue, issues, level: 0);
      expect(proposals.level, 0);
      expect(proposals.items.single.target, 'Mystery');
      expect(proposals.commonValues, [null, null]);
      final deeper = _propose(ReportKind.unknownValue, issues, level: 2);
      expect(deeper.items.single.target, 'Artist/_Unassigned/Mystery');
    });
  });

  group('project too deep', () {
    LayoutLevel lvl = title;
    FixIssue deep(
      String sub, {
      LibraryId library = _lib,
      String song = 'A/B/S',
    }) => _issue('$song/$sub', level: lvl, target: song, library: library);
    final libraries = {
      _lib: _library(members: [_alice, _bob, _me]),
      _other: Library(
        id: _other,
        mode: LibraryMode.local,
        layout: Layout.classic(),
        members: [_bob],
      ),
      const LibraryId('L3'): Library(
        id: const LibraryId('L3'),
        mode: LibraryMode.local,
        layout: Layout.classic(),
      ),
    };

    test('finds the member and the status subfolders', () {
      final proposals = _propose(ReportKind.projectTooDeep, [
        deep('Alice/mix/a.rpp'),
        deep('demo/b.rpp'),
        deep('Alice/d.rpp'),
      ], libraries: libraries);
      expect(
        [
          for (final i in proposals.items)
            (i.target, i.member, i.statusFolder, i.status, i.label),
        ],
        [
          ('A/B/S', _alice, 'mix', 'mixing', 'a'),
          ('A/B/S', null, 'demo', null, 'b'),
          ('A/B/S', _alice, null, null, 'd'),
        ],
      );
    });

    test('proposes the local member as default owner if declared', () {
      final issues = [deep('x/a.rpp')];
      expect(
        _propose(
          ReportKind.projectTooDeep,
          issues,
          libraries: libraries,
          identity: _me.id,
        ).owner,
        _me.id,
      );
      expect(
        _propose(
          ReportKind.projectTooDeep,
          issues,
          libraries: libraries,
          identity: const MemberId('ghost'),
        ).owner,
        _alice.id,
      );
      final none = _propose(
        ReportKind.projectTooDeep,
        [deep('x/a.rpp', library: const LibraryId('L3'))],
        libraries: libraries,
        identity: _me.id,
      );
      expect(none.owner, isNull);
      expect(none.owners, isEmpty);
    });

    test('builds the lifts with owner and status', () {
      final proposals = _propose(
        ReportKind.projectTooDeep,
        [
          deep('Alice/mix/a.rpp'),
          deep('demo/b.rpp'),
          deep('old/c.rpp'),
          deep('Alice/d.rpp'),
        ],
        libraries: libraries,
        identity: _me.id,
      );
      final fixes = buildFixes(
        ReportKind.projectTooDeep,
        proposals,
        _choices(
          proposals,
          checked: {0, 1, 3},
          owner: _bob.id,
          statuses: {'mix': 'mixing', 'demo': 'recording', 'old': null},
        ),
      );
      expect(
        [
          for (final f in fixes[_lib]!.cast<LiftProject>())
            (f.path, f.titleDir, f.owner, f.status, f.statusFolder),
        ],
        [
          ('A/B/S/Alice/mix/a.rpp', 'A/B/S', _alice.id, 'mixing', null),
          ('A/B/S/demo/b.rpp', 'A/B/S', _bob.id, 'recording', null),
          ('A/B/S/Alice/d.rpp', 'A/B/S', _alice.id, null, null),
        ],
      );
    });

    test('keeps the status folder of a status left unset', () {
      final proposals = _propose(ReportKind.projectTooDeep, [
        deep('old/c.rpp'),
      ], libraries: libraries);
      final fix =
          buildFixes(
                ReportKind.projectTooDeep,
                proposals,
                _choices(proposals, statuses: {'old': null}),
              )[_lib]!.single
              as LiftProject;
      expect((fix.status, fix.statusFolder), (null, 'old'));
    });

    test('lifts projects of several libraries, each with its owner', () {
      final proposals = _propose(
        ReportKind.projectTooDeep,
        [
          deep('mix/a.rpp', song: 'S'),
          deep('mix/b.rpp', song: 'S', library: _other),
          deep('mix/c.rpp', song: 'S', library: const LibraryId('L3')),
        ],
        libraries: libraries,
        identity: _me.id,
      );
      final fixes = buildFixes(
        ReportKind.projectTooDeep,
        proposals,
        _choices(proposals, owner: proposals.owner),
      );
      expect(
        {
          for (final MapEntry(:key, :value) in fixes.entries)
            key: [for (final f in value.cast<LiftProject>()) f.owner],
        },
        {
          _lib: [_me.id],
          // The default owner is not declared here: its first member.
          _other: [_bob.id],
          // No declared members: no owner.
          const LibraryId('L3'): [null],
        },
      );
    });

    test('gives a free label when the title already holds the name', () {
      final proposals = _propose(
        ReportKind.projectTooDeep,
        [deep('x/a.rpp'), deep('x/b.rpp'), deep('x/c.rpp')],
        libraries: libraries,
        titles: [
          _title('a/b/s', files: ['A.rpp', 'a (2).rpp', 'c.rpp-bak']),
          _title('a/b/s', library: _other, files: ['b.rpp']),
        ],
      );
      expect([for (final i in proposals.items) i.label], ['a (3)', 'b', 'c']);
    });
  });

  group('media kinds', () {
    test('stand for their title, once', () {
      for (final kind in normalizeKinds) {
        final proposals = _propose(kind, [
          _issue('A/B/S/x.rpp'),
          _issue('A/B/S/Media/y.rpp'),
          _issue('A/B/T/z.rpp'),
        ]);
        expect(proposals.items.map((i) => i.target), everyElement(isNull));
        final fixes = buildFixes(kind, proposals, _choices(proposals));
        expect([for (final f in fixes[_lib]!) f.path], ['A/B/S', 'A/B/T']);
        expect(fixes[_lib], everyElement(isA<NormalizeMedia>()));
      }
    });

    test('mediaTitleOf is the folder, or the title of a pool', () {
      expect(mediaTitleOf('A/S/x.rpp'), 'A/S');
      expect(mediaTitleOf('A/S/media/y.rpp'), 'A/S');
      expect(mediaTitleOf('A/S/Media/y.rpp'), 'A/S');
    });
  });

  test('batch kinds are the folder, lift and media kinds', () {
    expect(
      batchFixKinds,
      containsAll([
        ReportKind.titleTooHigh,
        ReportKind.misplacedLevel,
        ReportKind.unknownValue,
        ReportKind.projectTooDeep,
        ...normalizeKinds,
      ]),
    );
    expect(batchFixKinds, isNot(contains(ReportKind.outsideLayout)));
  });

  test('builds nothing for no checked item', () {
    final proposals = _propose(ReportKind.titleTooHigh, [
      _issue('Song', level: title, target: 'A/B/Song'),
    ]);
    expect(
      buildFixes(
        ReportKind.titleTooHigh,
        proposals,
        _choices(proposals, checked: {}),
      ),
      isEmpty,
    );
    // Used only to keep the layout levels referenced.
    expect([artist, album], hasLength(2));
  });
}
