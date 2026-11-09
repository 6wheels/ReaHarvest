import 'dart:convert';
import 'dart:math';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ulid', () {
    test('generates valid, time-sortable ids', () {
      final a = newUlid(now: DateTime.utc(2026, 1, 1));
      final b = newUlid(now: DateTime.utc(2026, 1, 2));
      expect(isUlid(a), isTrue);
      expect(a.length, 26);
      expect(a.compareTo(b), lessThan(0));
      expect(
        newUlid(now: DateTime.fromMillisecondsSinceEpoch(0), random: Random(1)),
        startsWith('0000000000'),
      );
    });

    test('rejects invalid ids', () {
      expect(isUlid('not-a-ulid'), isFalse);
      expect(isUlid('01ARZ3NDEKTSV4RRFFQ69G5FAI'), isFalse); // I is excluded
      expect(isUlid('81ARZ3NDEKTSV4RRFFQ69G5FAV'), isFalse); // overflow
      expect(isUlid('01ARZ3NDEKTSV4RRFFQ69G5FAV'), isTrue);
    });

    test('typed ids generate ulids', () {
      expect(isUlid(MemberId.generate()), isTrue);
      expect(isUlid(VersionId.generate()), isTrue);
      expect(isUlid(NodeId.generate()), isTrue);
    });
  });

  group('hlc', () {
    const a = MemberId('A');
    const b = MemberId('B');
    final t0 = DateTime.fromMillisecondsSinceEpoch(1000);

    test('tick advances with wall clock or counter', () {
      final h1 = const Hlc.zero(a).tick(t0);
      expect((h1.millis, h1.counter), (1000, 0));
      final h2 = h1.tick(t0);
      expect((h2.millis, h2.counter), (1000, 1));
      final h3 = h2.tick(DateTime.fromMillisecondsSinceEpoch(500));
      expect((h3.millis, h3.counter), (1000, 2));
      expect(h1 < h2 && h2 < h3, isTrue);
    });

    test('receive moves past remote clock', () {
      const local = Hlc(1000, 3, a);
      const remote = Hlc(2000, 5, b);
      final h = local.receive(remote, t0);
      expect((h.millis, h.counter, h.node), (2000, 6, a));
      expect(h > remote, isTrue);
      final same = local.receive(const Hlc(1000, 7, b), t0);
      expect((same.millis, same.counter), (1000, 8));
      final ahead = local.receive(const Hlc(500, 9, b), t0);
      expect((ahead.millis, ahead.counter), (1000, 4));
    });

    test('equal clocks have equal hash codes', () {
      expect(Hlc(1, 2, a).hashCode, Hlc(1, 2, a).hashCode);
      expect(Hlc(1, 2, a), isNot(Hlc(1, 2, b)));
    });

    test('ties are broken by node', () {
      expect(const Hlc(1, 1, a) < const Hlc(1, 1, b), isTrue);
    });

    test('string form round-trips and sorts like the clock', () {
      const h = Hlc(1700000000000, 42, a);
      expect(Hlc.parse(h.toString()), h);
      expect(
        const Hlc(9, 0, a).toString().compareTo(const Hlc(10, 0, a).toString()),
        lessThan(0),
      );
    });
  });

  group('layout', () {
    test('provides templates with leaf level and default render mapping', () {
      final classic = Layout.classic();
      expect(classic.leaf.key, 'title');
      expect(classic.renderMetadata, {
        'artist': 'artist',
        'album': 'album',
        'title': 'title',
      });
      expect(Layout.projectOriented().levels, hasLength(2));
      expect(Layout.film().leaf.key, 'scene');
    });

    test('enforces 1 to 4 unique levels', () {
      expect(() => Layout(const []), throwsArgumentError);
      expect(
        () => Layout([for (var i = 0; i < 5; i++) LayoutLevel('l$i')]),
        throwsArgumentError,
      );
      expect(
        () => Layout(const [LayoutLevel('a'), LayoutLevel('a')]),
        throwsArgumentError,
      );
    });

    test('labels custom keys with English then key fallback', () {
      const level = LayoutLevel('take', labels: {'en': 'Take', 'fr': 'Prise'});
      expect(level.label('fr'), 'Prise');
      expect(level.label('de'), 'Take');
      expect(const LayoutLevel('take').label('fr'), 'take');
      expect(const LayoutLevel('take').toJson(), {'key': 'take'});
      expect(LayoutLevel.fromJson(level.toJson()).labels, level.labels);
    });

    test('derives tags from a matching path', () {
      final layout = Layout.classic();
      expect(layout.tagsOf(['Artist', Layout.unassigned, 'Song']), {
        'artist': 'Artist',
        'album': '_Unassigned',
        'title': 'Song',
      });
      expect(layout.tagsOf(['Artist', 'Song']), isNull);
    });
  });

  group('library', () {
    test('round-trips .library.json', () {
      final library = Library(
        id: LibraryId.generate(),
        mode: LibraryMode.collab,
        layout: Layout.classic(),
        collab: CollabSettings(
          groupId: GroupId.generate(),
          backendUrl: 'https://example.org',
        ),
      );
      final json =
          jsonDecode(jsonEncode(library.toJson())) as Map<String, Object?>;
      expect(json['schemaVersion'], 1);
      expect(json['mode'], 'collab');
      expect((json['collab'] as Map)['store'], 'journal');
      final read = Library.fromJson(json);
      expect(read.id, library.id);
      expect(read.mode, LibraryMode.collab);
      expect(read.layout!.levels.map((l) => l.key), [
        'artist',
        'album',
        'title',
      ]);
      expect(
        (json['layout'] as Map)['levels'],
        everyElement(isNot(contains('labels'))),
      );
      expect(read.collab!.groupId, library.collab!.groupId);
      expect(read.collab!.backendUrl, 'https://example.org');
    });

    test('omits collab block outside collab mode', () {
      final json = Library(
        id: LibraryId.generate(),
        mode: LibraryMode.local,
        layout: Layout.classic(),
      ).toJson();
      expect(json.containsKey('collab'), isFalse);
    });

    test('enforces mode rules', () {
      final id = LibraryId.generate();
      expect(
        Library(id: id, mode: LibraryMode.local, layout: null).isFreeTree,
        isTrue,
      );
      expect(
        () => Library(id: id, mode: LibraryMode.cloud, layout: null),
        throwsArgumentError,
      );
      expect(
        () =>
            Library(id: id, mode: LibraryMode.collab, layout: Layout.classic()),
        throwsArgumentError,
      );
      expect(
        () => Library(
          id: id,
          mode: LibraryMode.cloud,
          layout: Layout.classic(),
          collab: CollabSettings(groupId: GroupId.generate()),
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown schema version', () {
      expect(
        () => Library.fromJson({'schemaVersion': 2}),
        throwsFormatException,
      );
    });
  });

  group('version metadata', () {
    test('round-trips EXTSTATE values', () {
      final meta = VersionMetadata(
        id: VersionId.generate(),
        owner: MemberId.generate(),
        label: 'chorus B',
      );
      final read = VersionMetadata.fromExtState(meta.toExtState())!;
      expect(
        (read.id, read.owner, read.label),
        (meta.id, meta.owner, meta.label),
      );
    });

    test('reads keys case-insensitively and requires id and owner', () {
      expect(
        VersionMetadata.fromExtState({'versionid': 'V', 'owner': 'M'})!.label,
        '',
      );
      expect(VersionMetadata.fromExtState({'VERSIONID': 'V'}), isNull);
      expect(VersionMetadata.fromExtState(const {}), isNull);
    });
  });

  group('title', () {
    Version version(String fileName, {String? id}) => Version(
      fileName: fileName,
      modified: DateTime.utc(2026),
      size: 1,
      metadata: id == null
          ? null
          : VersionMetadata(id: VersionId(id), owner: const MemberId('M')),
    );

    test('keys version statuses by version id, else by file name', () {
      final adopted = version('a.rpp', id: 'V1');
      final free = version('sub/b.rpp');
      final title = Title(
        id: NodeId.generate(),
        libraryId: LibraryId.generate(),
        path: 'Artist/Album/Song',
        tags: const {'title': 'Song'},
        versions: [adopted, free],
        status: 'mixing',
        versionStatuses: const {'V1': 'done', 'sub/b.rpp': 'idea'},
      );
      expect((adopted.isAdopted, adopted.key), (true, 'V1'));
      expect((free.isAdopted, free.key), (false, 'sub/b.rpp'));
      expect(title.statusOf(adopted), 'done');
      expect(title.statusOf(free), 'idea');
      expect(title.statusOf(version('c.rpp')), isNull);
    });

    test('finds versions sharing a version id', () {
      Title title(String path, List<Version> versions) => Title(
        id: NodeId.generate(),
        libraryId: const LibraryId('L'),
        path: path,
        tags: const {},
        versions: versions,
      );
      final first = title('A', [version('a.rpp', id: 'V1'), version('b.rpp')]);
      final second = title('B', [
        version('c.rpp', id: 'V1'),
        version('d.rpp', id: 'V2'),
      ]);
      final duplicates = duplicateVersions([first, second]);
      expect(duplicates.keys, ['V1']);
      expect(
        [for (final (t, v) in duplicates['V1']!) '${t.path}/${v.fileName}'],
        ['A/a.rpp', 'B/c.rpp'],
      );
    });
  });

  test('plugin refs round-trip JSON and compare by value', () {
    final plugin = PluginRef(
      kind: 'VST3',
      name: 'ReaEQ (Cockos)',
      identifier: 'reaeq.vst3',
    );
    final read = PluginRef.fromJson(
      jsonDecode(jsonEncode(plugin.toJson())) as Map<String, Object?>,
    );
    expect(read, plugin);
    expect(read.hashCode, plugin.hashCode);
    expect(
      read,
      isNot(PluginRef(kind: 'JS', name: plugin.name, identifier: 'x')),
    );
  });

  test('storage entries and exports hold their values', () {
    final entry = StorageEntry(
      path: 'a/b.rpp',
      isDirectory: false,
      size: 3,
      modified: DateTime.utc(2026),
    );
    expect((entry.path, entry.isDirectory, entry.size), ('a/b.rpp', false, 3));
    expect(CanonicalExport([]).records, isEmpty);
  });

  test('media presence follows size', () {
    expect(const MediaRef('Media/a.wav', size: 10).isPresent, isTrue);
    expect(const MediaRef('Media/b.wav').isPresent, isFalse);
  });

  group('sync state', () {
    SyncState s(String? base, String? local, String? remote) =>
        SyncState.of(base: base, local: local, remote: remote);

    test('derives state from hashes', () {
      expect(s(null, null, 'r'), SyncState.notCheckedOut);
      expect(s('h', 'h', 'h'), SyncState.upToDate);
      expect(s('h', 'l', 'h'), SyncState.localChanges);
      expect(s('h', 'h', 'r'), SyncState.remoteChanges);
      expect(s('h', 'l', 'r'), SyncState.conflict);
      expect(s('h', 'x', 'x'), SyncState.upToDate);
    });

    test('handles files missing on one side', () {
      expect(s(null, 'l', null), SyncState.localChanges);
      expect(s('h', 'h', null), SyncState.remoteChanges);
      expect(s('h', 'l', null), SyncState.conflict);
      expect(s(null, 'l', 'r'), SyncState.conflict);
    });
  });

  test('collab filter matches entity and fields', () {
    const author = MemberId('M');
    final record = CollabRecord(
      uid: newUlid(),
      groupId: const GroupId('G'),
      libraryId: const LibraryId('L'),
      entity: CollabEntity.task,
      author: author,
      hlc: const Hlc(1, 0, author),
      fields: const {'titleId': 'T', 'done': false},
    );
    expect(const CollabFilter().matches(record), isTrue);
    expect(
      const CollabFilter(
        entity: CollabEntity.task,
        fields: {'titleId': 'T'},
      ).matches(record),
      isTrue,
    );
    expect(
      const CollabFilter(entity: CollabEntity.note).matches(record),
      isFalse,
    );
    expect(const CollabFilter(fields: {'done': true}).matches(record), isFalse);
  });
}
