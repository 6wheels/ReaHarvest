import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/state/version_actions.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_env.dart';

void main() {
  setUpLibraryEnv();

  test('manages the versions of a title', () async {
    final band = folder('Band');
    final song = Directory(p.join(band, 'Artist', 'Album', 'Song'))
      ..createSync(recursive: true);
    File('../../test/fixtures/tracks.rpp')
        .copySync(p.join(song.path, 'v1.rpp'));
    File(p.join(song.path, 'Media', 'unused.wav'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    await catalog.addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    Title title() => index.titles().single;
    Version version(String name) =>
        title().versions.firstWhere((v) => v.fileName == name);

    expect(
      await versions.addVersion(title(), 'Song - a.RPP', ' a '),
      'Song - a.RPP',
    );
    final blank = version('Song - a.RPP').metadata!;
    // No declared members: no owner (SPEC §4.2).
    expect((blank.owner, blank.label), (null, 'a'));
    await versions.addVersion(
      title(),
      'copy.RPP',
      'b',
      source: version('Song - a.RPP'),
    );
    final copy = version('copy.RPP').metadata!;
    expect(copy.id, isNot(blank.id));
    expect(copy.label, 'b');

    expect(
      await versions.editVersion(
        title(),
        version('copy.RPP'),
        fileName: 'Song - c.RPP',
        label: 'c',
      ),
      'Song - c.RPP',
    );
    final edited = version('Song - c.RPP').metadata!;
    expect((edited.id, edited.label), (copy.id, 'c'));

    // A label edit leaves the project byte for byte, with its date.
    final file = File(p.join(song.path, 'Song - c.RPP'));
    final bytes = file.readAsBytesSync();
    final date = DateTime(2025, 3, 4);
    file.setLastModifiedSync(date);
    await versions.editVersion(
      title(),
      version('Song - c.RPP'),
      fileName: 'Song - c.RPP',
      label: 'd',
    );
    expect(version('Song - c.RPP').metadata!.label, 'd');
    expect(file.readAsBytesSync(), bytes);
    expect(file.lastModifiedSync(), date);

    await versions.setStatusOf(title(), version('Song - c.RPP'), 'mixing');
    expect(title().statusOf(version('Song - c.RPP')), 'mixing');

    await versions.trashVersion(title(), version('Song - c.RPP'));
    expect(
      title().versions.map((v) => v.fileName),
      isNot(contains('Song - c.RPP')),
    );
    final trash = await container.read(trashProvider(title().id).future);
    expect(trash.map((e) => e.path), ['Artist/Album/Song/.trash/Song - c.RPP']);

    final unused = await versions.purge(title(), [trash.single.path]);
    expect(
      File(p.join(song.path, '.trash', 'Song - c.RPP')).existsSync(),
      isFalse,
    );
    expect(unused.map((e) => e.path), ['Artist/Album/Song/Media/unused.wav']);
    await versions.purgeUnusedMedia(title(), [unused.single.path]);
    expect(
      File(p.join(song.path, 'Media', 'unused.wav')).existsSync(),
      isFalse,
    );
  });

  test('lists the project templates of a library', () async {
    final templates = Directory(
      p.join(root.path, 'resources', 'ProjectTemplates'),
    )..createSync(recursive: true);
    File(p.join(templates.path, 'band.RPP')).createSync();
    expect(
      await container.read(
        projectTemplatesProvider(LibraryId.generate()).future,
      ),
      [p.join(templates.path, 'band.RPP')],
    );
  });

  test('adopts versions and separates manual duplicates', () async {
    final song = await bandWithSong();
    expect(version('v1.rpp').isAdopted, isFalse);

    await versions.adopt(title(), version('v1.rpp'), ' main ');
    final adopted = version('v1.rpp').metadata!;
    expect((adopted.owner, adopted.label), (null, 'main'));

    File(p.join(song, 'v1.rpp')).copySync(p.join(song, 'dup.rpp'));
    await scans.scanAll();
    expect(duplicateVersions(index.titles()).keys, [adopted.id]);

    await versions.separateDuplicate(title(), version('dup.rpp'));
    final separated = version('dup.rpp').metadata!;
    expect(separated.id, isNot(adopted.id));
    expect((separated.label, separated.owner), ('main', null));
    expect(duplicateVersions(index.titles()), isEmpty);
  });

  test('keeps both changes of one node file asked together', () async {
    final song = await bandWithSong();
    File(p.join(song, 'v1.rpp')).copySync(p.join(song, 'v2.rpp'));
    await scans.scanAll();
    await versions.adopt(title(), version('v1.rpp'), 'one');

    // Each one reads and writes the node file of the title: one after the
    // other in the turn of the library, neither is lost.
    await Future.wait([
      versions.adopt(title(), version('v2.rpp'), 'two'),
      versions.setStatusOf(title(), version('v1.rpp'), 'mixing'),
    ]);

    expect(version('v2.rpp').metadata!.label, 'two');
    expect(title().statusOf(version('v1.rpp')), 'mixing');
    expect(version('v1.rpp').metadata!.label, 'one');
  });

  test('owns the versions of the local member once declared', () async {
    final song = await bandWithSong();
    final entry = container.read(settingsProvider).libraries.single;
    await catalog.setMembers(entry, const [Member(MemberId('M'), 'Me')]);

    await versions.addVersion(title(), 'b.RPP', 'b');
    expect(version('b.RPP').metadata!.owner, const MemberId('M'));
    File(p.join(song, 'b.RPP')).copySync(p.join(song, 'c.RPP'));
    await scans.scanAll();
    await versions.separateDuplicate(title(), version('c.RPP'));
    expect(version('c.RPP').metadata!.owner, const MemberId('M'));
    expect(version('c.RPP').metadata!.label, 'b');
  });

  test('copies the fallback label of the original to its copy', () async {
    final song = await bandWithSong();
    await versions.adopt(title(), version('v1.rpp'), 'main');
    final id = version('v1.rpp').metadata!.id;
    // The node entry is gone (e.g. node file reset): label from the name.
    final root = container.read(settingsProvider).libraries.single.libraryRoot;
    await setVersionLabel(
      MountedFolderStorage(root),
      'Artist/Album/Song',
      id,
      null,
    );
    File(p.join(song, 'v1.rpp')).copySync(p.join(song, 'v1 copy.rpp'));
    await scans.scanAll();
    expect(version('v1.rpp').metadata!.label, 'v1');

    await versions.separateDuplicate(title(), version('v1 copy.rpp'));
    expect(version('v1 copy.rpp').metadata!.label, 'v1');
  });

  test('keeps the shown label on a rename', () async {
    await bandWithSong();
    await versions.adopt(title(), version('v1.rpp'), 'main');
    final id = version('v1.rpp').metadata!.id;
    final root = container.read(settingsProvider).libraries.single.libraryRoot;
    await setVersionLabel(
      MountedFolderStorage(root),
      'Artist/Album/Song',
      id,
      null,
    );
    await scans.scanAll();
    // Shown from the file name fallback, confirmed unchanged in the dialog.
    expect(version('v1.rpp').metadata!.label, 'v1');

    await versions.editVersion(
      title(),
      version('v1.rpp'),
      fileName: 'final.rpp',
      label: 'v1',
    );
    expect(version('final.rpp').metadata!.label, 'v1');
  });

  test('backs up and restores versions', () async {
    await bandWithSong();
    await versions.adopt(title(), version('v1.rpp'), 'main');
    final id = version('v1.rpp').metadata!.id;
    Future<List<Backup>> backups() async =>
        (await container.read(historyProvider(title().id).future))[id] ?? [];

    await versions.backup(title(), version('v1.rpp'));
    final saved = (await backups()).single;
    await versions.editVersion(
      title(),
      version('v1.rpp'),
      fileName: 'v1.rpp',
      label: 'changed',
    );

    await versions.restore(title(), version('v1.rpp'), saved);
    // The label is stored outside the project: a restore keeps it.
    expect(version('v1.rpp').metadata!.id, id);
    expect(version('v1.rpp').metadata!.label, 'changed');
    // The state before the restore is backed up first.
    expect(await backups(), hasLength(2));
  });
}
