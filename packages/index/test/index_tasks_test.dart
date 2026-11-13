import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode, SqliteException, sqlite3;
import 'package:test/test.dart';

const fixtures = '../../test/fixtures';

void main() {
  late Directory dir;
  late String indexPath;

  /// The read-only connection of the UI isolate.
  late LocalIndex ui;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('reaharvest_index_tasks_');
    indexPath = p.join(dir.path, 'index.sqlite');
    await createIndex(indexPath);
    ui = LocalIndex.open(indexPath, readOnly: true);
  });

  tearDown(() {
    ui.close();
    dir.deleteSync(recursive: true);
  });

  Library library() => Library(
    id: LibraryId.generate(),
    mode: LibraryMode.local,
    layout: Layout.classic(),
  );

  /// Copies a project to [relative] (split on `/`) below [root].
  void project(String root, String relative) {
    final target = p.joinAll([root, ...relative.split('/')]);
    Directory(p.dirname(target)).createSync(recursive: true);
    File(p.join(fixtures, 'tracks.rpp')).copySync(target);
  }

  String folder(String name) =>
      (Directory(p.join(dir.path, name))..createSync()).path;

  Set<String> paths(LibraryId id) => {
    for (final t in ui.titles(library: id)) t.path,
  };

  group('read-only connection', () {
    test('reads what a writing connection stored', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      final lib = library();
      await scanIntoIndex(indexPath, root, lib);
      expect(ui.libraries().single.id, lib.id);
      expect(paths(lib.id), {'A/B/Song'});
    });

    test('refuses writes instead of blocking', () {
      final lib = library();
      expect(
        () => ui.update(lib, const ScanResult()),
        throwsA(isA<SqliteException>()),
      );
      expect(() => ui.removeLibrary(lib.id), throwsA(isA<SqliteException>()));
      expect(ui.libraries(), isEmpty);
    });
  });

  group('scanIntoIndex', () {
    test(
      'stores the scan and reports its issues relative to the root',
      () async {
        final root = folder('Band');
        project(root, 'A/B/Song/v1.rpp');
        project(root, 'A/loose.rpp');
        final lib = library();
        final report = await scanIntoIndex(indexPath, root, lib);
        expect(paths(lib.id), {'A/B/Song'});
        final reported = {
          for (final items in report.items.values)
            for (final i in items) i.path,
        };
        expect(reported, isNotEmpty);
        expect(reported, {
          for (final i in ui.issues(library: lib.id)) i.item.path,
        });
        expect(reported.every((path) => !path.startsWith(root)), isTrue);
      },
    );

    test('rescans incrementally, or fully on demand', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      final lib = library();
      await scanIntoIndex(indexPath, root, lib);
      project(root, 'A/B/Song/v2.rpp');
      await scanIntoIndex(indexPath, root, lib);
      expect(ui.titles(library: lib.id).single.versions, hasLength(2));
      await scanIntoIndex(indexPath, root, lib, full: true);
      expect(ui.titles(library: lib.id).single.versions, hasLength(2));
    });

    test('writes no node file without writeNodes', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      final lib = library();
      await scanIntoIndex(indexPath, root, lib, writeNodes: false);
      expect(paths(lib.id), isEmpty);
      expect(
        File(p.join(root, 'A', 'B', 'Song', '.node.json')).existsSync(),
        isFalse,
      );
    });

    test(
      'a failed scan keeps the stored state and closes its connection',
      () async {
        final root = folder('Band');
        project(root, 'A/B/Song/v1.rpp');
        final lib = library();
        await scanIntoIndex(indexPath, root, lib);
        await expectLater(
          scanIntoIndex(indexPath, p.join(dir.path, 'Missing'), lib),
          throwsA(isA<FileSystemException>()),
        );
        expect(paths(lib.id), {'A/B/Song'});

        // Recovery: the next scan is stored.
        project(root, 'A/B/Other/v1.rpp');
        await scanIntoIndex(indexPath, root, lib);
        expect(paths(lib.id), {'A/B/Song', 'A/B/Other'});

        // No connection left open by the tasks: the index can be deleted
        // (Windows refuses to delete an open file).
        ui.close();
        File(indexPath).deleteSync();
        ui = LocalIndex.inMemory();
      },
    );

    test('waits for another writer instead of failing', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      final lib = library();
      final other = sqlite3.open(indexPath, mode: OpenMode.readWrite);
      other.execute('BEGIN IMMEDIATE');
      final scanning = scanIntoIndex(indexPath, root, lib);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      other
        ..execute('COMMIT')
        ..close();
      await scanning;
      expect(paths(lib.id), {'A/B/Song'});
    });

    test('scans of two libraries at once are both stored', () async {
      final a = folder('A');
      final b = folder('B');
      project(a, 'X/Y/One/v1.rpp');
      project(b, 'X/Y/Two/v1.rpp');
      final (libA, libB) = (library(), library());
      await Future.wait([
        scanIntoIndex(indexPath, a, libA),
        scanIntoIndex(indexPath, b, libB),
      ]);
      expect(paths(libA.id), {'X/Y/One'});
      expect(paths(libB.id), {'X/Y/Two'});
    });

    test('a read during a write sees the previous or the new state', () async {
      const count = 150;
      final root = folder('Band');
      for (var i = 0; i < count; i++) {
        project(root, 'A/B/Old$i/v1.rpp');
      }
      final lib = library();
      await scanIntoIndex(indexPath, root, lib);
      for (var i = 0; i < count; i++) {
        Directory(p.join(root, 'A', 'B', 'Old$i')).deleteSync(recursive: true);
        project(root, 'A/B/New$i/v1.rpp');
        project(root, 'A/B/New$i/v2.rpp');
      }

      String state() {
        final titles = ui.titles(library: lib.id);
        if (titles.length == count &&
            titles.every(
              (t) => t.path.startsWith('A/B/Old') && t.versions.length == 1,
            )) {
          return 'previous';
        }
        if (titles.length == count &&
            titles.every(
              (t) => t.path.startsWith('A/B/New') && t.versions.length == 2,
            )) {
          return 'new';
        }
        return 'mixed: ${titles.length} titles, '
            '${titles.map((t) => '${t.path}:${t.versions.length}').take(3)}';
      }

      var done = false;
      final writing = scanIntoIndex(
        indexPath,
        root,
        lib,
      ).whenComplete(() => done = true);
      final seen = <String>{};
      while (!done) {
        seen.add(state());
        await Future<void>.delayed(Duration.zero);
      }
      await writing;
      seen.add(state());
      expect(seen, everyElement(anyOf('previous', 'new')));
      expect(seen, contains('new'));
    });
  });

  group('scanTitleIntoIndex', () {
    test('stores the rescanned title', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      project(root, 'A/B/Other/v1.rpp');
      final lib = library();
      await scanIntoIndex(indexPath, root, lib);
      project(root, 'A/B/Song/v2.rpp');
      expect(
        await scanTitleIntoIndex(indexPath, root, lib, 'A/B/Song'),
        isTrue,
      );
      final titles = {for (final t in ui.titles(library: lib.id)) t.path: t};
      expect(titles['A/B/Song']!.versions, hasLength(2));
      expect(titles['A/B/Other']!.versions, hasLength(1));
    });

    test('is false for a title not indexed, writing nothing', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      final lib = library();
      expect(
        await scanTitleIntoIndex(indexPath, root, lib, 'A/B/Song'),
        isFalse,
      );
      expect(ui.libraries(), isEmpty);
    });

    test('is false for a folder no longer a title, writing nothing', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      final lib = library();
      await scanIntoIndex(indexPath, root, lib);
      File(p.join(root, 'A', 'B', 'Song', 'v1.rpp')).deleteSync();
      expect(
        await scanTitleIntoIndex(indexPath, root, lib, 'A/B/Song'),
        isFalse,
      );
      expect(paths(lib.id), {'A/B/Song'});
    });

    test('a failed rescan keeps the stored state', () async {
      final root = folder('Band');
      project(root, 'A/B/Song/v1.rpp');
      final lib = library();
      await scanIntoIndex(indexPath, root, lib);
      Directory(p.join(root, 'A', 'B', 'Song')).deleteSync(recursive: true);
      await expectLater(
        scanTitleIntoIndex(indexPath, root, lib, 'A/B/Song'),
        throwsA(isA<FileSystemException>()),
      );
      expect(paths(lib.id), {'A/B/Song'});
    });
  });

  test('removeLibraryFromIndex forgets the library', () async {
    final root = folder('Band');
    project(root, 'A/B/Song/v1.rpp');
    final lib = library();
    await scanIntoIndex(indexPath, root, lib);
    await removeLibraryFromIndex(indexPath, lib.id);
    expect(ui.libraries(), isEmpty);
    expect(ui.titles(), isEmpty);
  });

  test('createIndex rebuilds an outdated schema', () async {
    ui.close();
    final db = sqlite3.open(indexPath)..userVersion = 1;
    db.close();
    await createIndex(indexPath);
    ui = LocalIndex.open(indexPath, readOnly: true);
    expect(ui.libraries(), isEmpty);
  });
}
