import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/migration_actions.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'library_env.dart';

/// Moves the title folder [from] to [to]; its project [file] gets the
/// version folder named after it.
OrganizeTitle moveTitle(String from, String to, String file) {
  final name = p.posix.basenameWithoutExtension(file);
  return OrganizeTitle(from, to, [
    FixVersion('$from/$file', folder: name, label: name),
  ], level: 'title');
}

void main() {
  setUpLibraryEnv();
  final en = lookupAppLocalizations(const Locale('en'));

  test('deletes only node files of folders without project', () async {
    final band = folder('Band');
    final song = p.join(band, 'Artist', 'Album', 'Song');
    Directory(song).createSync(recursive: true);
    File('../../test/fixtures/tracks.rpp').copySync(p.join(song, 'v1.rpp'));
    final orphan = File(p.join(band, 'Artist', 'render', '.node.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"nodeId": "01X", "level": "album"}');
    await catalog.addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    final id = container.read(settingsProvider).libraries.single.id;
    expect(index.issues(kind: ReportKind.orphanNode), [
      (
        library: id,
        kind: ReportKind.orphanNode,
        item: const ReportItem('Artist/render/.node.json'),
      ),
    ]);

    await expectLater(
      migration.deleteOrphanNode(id, 'Artist/Album/Song/.node.json'),
      throwsArgumentError,
    );
    await expectLater(
      migration.deleteOrphanNode(id, 'Artist/Album/Song/v1.rpp'),
      throwsArgumentError,
    );
    await migration.deleteOrphanNode(id, 'Artist/render/.node.json');

    expect(orphan.existsSync(), isFalse);
    expect(index.issues(kind: ReportKind.orphanNode), isEmpty);
    expect(File(p.join(song, '.node.json')).existsSync(), isTrue);
  });

  test('checks an orphan node file again in the turn of its library', () async {
    final band = folder('Band');
    File(p.join(band, 'Artist', 'Album', 'Song', '.node.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"nodeId": "01X", "level": "title"}');
    await catalog.addLocal(
      folder: band,
      displayName: '',
      layout: Layout.classic(),
    );
    final entry = container.read(settingsProvider).libraries.single;
    const path = 'Artist/Album/Song/.node.json';
    expect(index.issues(kind: ReportKind.orphanNode).map((i) => i.item.path), [
      path,
    ]);

    // A change asked before gives its folder a project: not deleted.
    final hold = Completer<void>();
    final turns = container.read(libraryTurnsProvider);
    final holding = turns.run(entry.id, () async {
      await hold.future;
      File('../../test/fixtures/tracks.rpp')
          .copySync(p.join(band, 'Artist', 'Album', 'Song', 'v1.rpp'));
      await scans.scan(entry);
    });
    final deleting = migration.deleteOrphanNode(entry.id, path);
    hold.complete();
    await holding;

    await expectLater(deleting, throwsArgumentError);
    expect(File(p.join(band, path)).existsSync(), isTrue);
  });

  test('organizes a title, keeping the date of its projects', () async {
    final song = await bandWithSong();
    final other = p.join(p.dirname(song), 'Other');
    // Same size once normalized (audio -> Media): read again anyway.
    File(p.join(other, 'v.rpp'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '<REAPER_PROJECT 0.1 "7.85/win64" 0\n'
        '  RECORD_PATH Media ""\n'
        '  RENDER_FILE Renders\n'
        '  <TRACK\n    <ITEM\n      <SOURCE WAVE\n'
        '        FILE "audio\\a.wav"\n      >\n    >\n  >\n>\n',
      )
      ..setLastModifiedSync(DateTime(2020, 1, 2));
    File(p.join(other, 'audio', 'a.wav'))
      ..createSync(recursive: true)
      ..writeAsStringSync('a');
    await scans.scanAll();
    final id = container.read(settingsProvider).libraries.single.id;

    await migration.fix(id, [
      moveTitle('Artist/Album/Other', 'Artist/Album/Other', 'v.rpp'),
    ]);

    final project = File(p.join(other, 'v', 'v.rpp'));
    expect(project.readAsStringSync(), contains(r'FILE "Media\a.wav"'));
    expect(project.lastModifiedSync(), DateTime(2020, 1, 2));
    expect(File(p.join(other, 'v', 'Media', 'a.wav')).existsSync(), isTrue);
    // Read again by the scan: one version, adopted.
    final versions = index
        .titles()
        .firstWhere((t) => t.path == 'Artist/Album/Other')
        .versions;
    expect(versions.single.fileName, 'v/v.rpp');
    expect(versions.single.isAdopted, isTrue);
  });

  test('moves a misplaced project into a title', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    // An item with a media next to the project, in its track.
    File(p.join(band, 'Artist', 'loose.rpp')).writeAsStringSync(
      File('../../test/fixtures/render-file.rpp')
          .readAsStringSync()
          .replaceFirstMapped(
            RegExp(r'  <TRACK[^\n]*\n'),
            (m) =>
                '${m[0]}    <ITEM\n      <SOURCE WAVE\n'
                '        FILE "a.wav"\n      >\n    >\n',
          ),
    );
    File(p.join(band, 'Artist', 'a.wav')).writeAsStringSync('a');
    await scans.scanAll();
    final id = container.read(settingsProvider).libraries.single.id;

    final report = await migration.fix(id, [
      MoveProject(
        const FixVersion('Artist/loose.rpp', folder: 'loose', label: 'loose'),
        'Artist/Album/Loose',
        level: 'title',
      ),
    ]);

    final root = container.read(settingsProvider).libraries.single.libraryRoot;
    expect(container.read(tasksProvider).last.error, isNull);
    final title = p.join(root, 'Artist', 'Album', 'Loose');
    // Paths in details are absolute too.
    expect(report!.items[ReportKind.projectMoved], [
      ReportItem(
        p.join(title, 'loose', 'loose.rpp'),
        p.join(root, 'Artist', 'loose.rpp'),
      ),
    ]);
    expect(report.items[ReportKind.mediaMoved], [
      ReportItem(
        p.join(title, 'loose', 'Media', 'a.wav'),
        p.join(root, 'Artist', 'a.wav'),
      ),
    ]);
    expect(
      index.titles().map((t) => t.levels['title']),
      containsAll(['Song', 'Loose']),
    );
    final task = container.read(tasksProvider).last;
    expect(task.openReport, isTrue);
    expect(task.report, same(report));
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(task.label(l10n), 'Fix 1 item');

    // A failed move is reported; the inventory check still passes.
    final failed = await migration.fix(id, [
      MoveProject(
        const FixVersion('Artist/gone.rpp', folder: 'gone', label: 'gone'),
        'A/B/C',
        level: 'title',
      ),
    ]);
    expect(
      failed!.items[ReportKind.fixFailed]!.single.path,
      endsWith('gone.rpp'),
    );
    expect(failed.items[ReportKind.fileLost], isNull);
    expect(container.read(tasksProvider).last.state, TaskState.failed);
    // A fresh inventory for each task.
    expect(Directory(p.join(root, '.migration')).listSync(), hasLength(2));
  });

  test('fixes misplaced folders and projects without losing a file', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    final member = Directory(p.join(song, 'Bob', 'mix'))
      ..createSync(recursive: true);
    File('../../test/fixtures/render-file.rpp')
        .copySync(p.join(member.path, 'take.rpp'));
    final old = Directory(p.join(band, 'Old'))..createSync();
    File('../../test/fixtures/tracks.rpp')
        .copySync(p.join(old.path, 'old.rpp'));
    // With known values, Old is recognized as a title placed too high.
    final entry = container.read(settingsProvider).libraries.single;
    await catalog.setKnownValues(entry, const [
      KnownValue('Artist', [
        KnownValue('Album'),
        KnownValue(Layout.unassigned),
      ]),
    ], read: const []);
    final id = entry.id;

    final report = await migration.fix(id, [
      OrganizeTitle('Artist/Album/Song', 'Artist/Album/Song', [
        const FixVersion(
          'Artist/Album/Song/Bob/mix/take.rpp',
          folder: 'take',
          label: 'take',
          owner: MemberId('bob'),
          status: 'mixing',
        ),
      ], level: 'title'),
      moveTitle('Old', 'Artist/_Unassigned/Old', 'old.rpp'),
    ]);

    expect(report!.hasErrors, isFalse);
    expect(report.items[ReportKind.projectMoved], [
      ReportItem(
        p.join(song, 'take', 'take.rpp'),
        p.join(song, 'Bob', 'mix', 'take.rpp'),
      ),
    ]);
    expect(report.items[ReportKind.folderMoved], [
      ReportItem(
        p.join(band, 'Artist', '_Unassigned', 'Old'),
        p.join(band, 'Old'),
      ),
    ]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(container.read(tasksProvider).last.label(l10n), 'Fix 2 items');
    final lifted = VersionMetadata.fromExtState(
      RppProject.parse(
        File(p.join(song, 'take', 'take.rpp')).readAsStringSync(),
      ).extState(VersionMetadata.section),
    )!.id;
    final node = await readNodeFile(
      MountedFolderStorage(band),
      'Artist/Album/Song',
    );
    expect(node!.versionOwners[lifted], 'bob');
    expect(node.versionStatuses[lifted], 'mixing');
    expect(
      index.titles().map((t) => t.path),
      contains('Artist/_Unassigned/Old'),
    );
  });

  test('moved or kept titles join the known values, steps told', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    for (final name in ['One', 'Two']) {
      final dir = Directory(p.join(band, 'Artist', name, name))
        ..createSync(recursive: true);
      File('../../test/fixtures/tracks.rpp')
          .copySync(p.join(dir.path, '$name.rpp'));
    }
    Directory(p.join(band, 'Artist', 'Live', 'Three', 'v'))
        .createSync(recursive: true);
    File('../../test/fixtures/tracks.rpp')
        .copySync(p.join(band, 'Artist', 'Live', 'Three', 'v', 'three.rpp'));
    final entry = container.read(settingsProvider).libraries.single;
    await catalog.setKnownValues(entry, const [
      KnownValue('Artist', [KnownValue('Album')]),
    ], read: const []);
    List<String> unknown() => [
      for (final i in container.read(issuesProvider))
        if (i.item.level != null) i.item.path,
    ];
    expect(
      unknown(),
      unorderedEquals(['Artist/Live', 'Artist/One', 'Artist/Two']),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    final steps = <String>{};
    container.listen(tasksProvider, (_, tasks) {
      if (tasks.lastOrNull?.step case final step?) steps.add(step(l10n));
    });
    final logs = <String>[];
    final sub = Logger.root.onRecord.listen(
      (r) => logs.add('${r.loggerName} ${r.message}'),
    );
    addTearDown(sub.cancel);

    // Titles moved under a new album, one kept under its album.
    final report = await migration.fix(entry.id, [
      moveTitle('Artist/One/One', 'Artist/New/One', 'One.rpp'),
      moveTitle('Artist/Two/Two', 'Artist/New/Two', 'Two.rpp'),
      OrganizeTitle('Artist/Live/Three', 'Artist/Live/Three', [
        const FixVersion(
          'Artist/Live/Three/v/three.rpp',
          folder: 'v',
          label: 'v',
        ),
      ], level: 'title'),
    ]);

    expect(report!.hasErrors, isFalse);
    expect(unknown(), isEmpty);
    expect(
      container.read(titlesProvider).map((t) => t.path),
      containsAll(['Artist/New/One', 'Artist/New/Two', 'Artist/Live/Three']),
    );
    final known = (await readLibrary(MountedFolderStorage(band)))!.knownValues;
    expect(known.knows(['Artist', 'New']), isTrue);
    expect(known.knows(['Artist', 'Live']), isTrue);
    expect(steps, [
      'Inventory of the files',
      'Fix 1 of 3',
      'Fix 2 of 3',
      'Fix 3 of 3',
      'Checking that no file is lost',
      'Updating the library',
    ]);
    // Every step and every change of the library is logged.
    final name = entry.displayName;
    expect(
      logs,
      containsAllInOrder([
        'tasks Fix 3 items: started',
        'tasks Fix 3 items: Inventory of the files',
        'tasks Fix 3 items: Fix 1 of 3',
        startsWith(
          'library.migration $name: '
          'organizeTitle Artist/One/One -> Artist/New/One',
        ),
        'tasks Fix 3 items: Fix 2 of 3',
        startsWith(
          'library.migration $name: '
          'organizeTitle Artist/Two/Two -> Artist/New/Two',
        ),
        'tasks Fix 3 items: Fix 3 of 3',
        'tasks Fix 3 items: Checking that no file is lost',
        'library.migration $name: inventory checked, no file lost',
        'tasks Fix 3 items: Updating the library',
        'library.migration Known values of $name added: Artist/New, Artist/Live',
        startsWith('library.scans Scanned $name: '),
        startsWith('tasks Fix 3 items: done'),
      ]),
    );
  });

  test('fixes of a library run one after the other', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    for (final name in ['One', 'Two']) {
      final dir = Directory(p.join(band, 'Artist', name))..createSync();
      File('../../test/fixtures/tracks.rpp')
          .copySync(p.join(dir.path, '$name.rpp'));
    }
    final entry = container.read(settingsProvider).libraries.single;
    final states = <TaskState>{};
    container.listen(tasksProvider, (_, tasks) {
      for (final task in tasks) {
        states.add(task.state);
      }
    });

    // The second is asked while the first runs: it is not taken for an
    // interrupted fix, and its task is shown queued.
    final reports = await Future.wait([
      migration.fix(entry.id, [
        moveTitle('Artist/One', 'Artist/New/One', 'One.rpp'),
      ]),
      migration.fix(entry.id, [
        moveTitle('Artist/Two', 'Artist/New/Two', 'Two.rpp'),
      ]),
      migration.offerUndo(entry),
    ]);

    expect(reports[2], isFalse);
    expect((reports[0]! as Report).hasErrors, isFalse);
    expect((reports[1]! as Report).hasErrors, isFalse);
    expect(container.read(interruptedFixesProvider), isEmpty);
    expect(states, contains(TaskState.queued));
    expect(
      Directory(p.join(band, 'Artist', 'New', 'One')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(band, 'Artist', 'New', 'Two')).existsSync(),
      isTrue,
    );
  });

  test('a batch asked during the startup scan waits for it', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    Directory(p.join(band, 'Artist', 'One')).createSync();
    File('../../test/fixtures/tracks.rpp')
        .copySync(p.join(band, 'Artist', 'One', 'One.rpp'));
    final entry = container.read(settingsProvider).libraries.single;
    final logs = <String>[];
    final sub = Logger.root.onRecord.listen(
      (r) => logs.add('${r.loggerName} ${r.message}'),
    );
    addTearDown(sub.cancel);

    final starting = migration.startup();
    final report = await migration.fix(entry.id, [
      moveTitle('Artist/One', 'Artist/New/One', 'One.rpp'),
    ]);
    await starting;

    expect(report!.hasErrors, isFalse);
    // Queued until the scan of its library ended.
    expect(
      logs,
      containsAllInOrder([
        'tasks Scan of the libraries: started',
        allOf(startsWith('tasks Fix'), endsWith(': queued')),
        startsWith('library.scans Scanned ${entry.displayName}: '),
        allOf(startsWith('tasks Fix'), endsWith(': started')),
        allOf(startsWith('tasks Fix'), contains(': done')),
      ]),
    );
    expect(
      Directory(p.join(band, 'Artist', 'New', 'One')).existsSync(),
      isTrue,
    );
  });

  test('tasks of two libraries run together', () async {
    await bandWithSong();
    final other = folder('Other');
    await catalog.addLocal(
      folder: other,
      displayName: 'Other',
      layout: Layout.classic(),
    );
    final [band, second] = container.read(settingsProvider).libraries;
    final tasks = container.read(tasksProvider.notifier);
    final hold = Completer<void>();
    final running = tasks.run(
      (l10n) => 'Hold',
      (_) => hold.future,
      library: band.id,
    );

    // The scan of the other library does not wait for the first one.
    await scans.scanTask(second);

    expect(container.read(tasksProvider).last.state, TaskState.done);
    expect(
      container.read(tasksProvider).firstWhere((t) => t.label(en) == 'Hold'),
      isA<BackgroundTask>().having((t) => t.state, 'state', TaskState.running),
    );
    hold.complete();
    await running;
  });

  test('a cancelled fix stops before the next one, library updated', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    for (final name in ['One', 'Two']) {
      final dir = Directory(p.join(band, 'Artist', name))..createSync();
      File('../../test/fixtures/tracks.rpp')
          .copySync(p.join(dir.path, '$name.rpp'));
    }
    final entry = container.read(settingsProvider).libraries.single;
    await catalog.setKnownValues(entry, const [
      KnownValue('Artist', [KnownValue('Album')]),
    ], read: const []);
    final l10n = lookupAppLocalizations(const Locale('en'));
    container.listen(tasksProvider, (_, tasks) {
      final task = tasks.last;
      if (task.step?.call(l10n) == 'Fix 1 of 2' && !task.cancelling) {
        container.read(tasksProvider.notifier).cancel(task.id);
      }
    });

    final report = await migration.fix(entry.id, [
      moveTitle('Artist/One', 'Artist/New/One', 'One.rpp'),
      moveTitle('Artist/Two', 'Artist/New/Two', 'Two.rpp'),
    ]);

    expect(report, isNull);
    final task = container.read(tasksProvider).last;
    expect(task.state, TaskState.cancelled);
    expect(task.report!.items[ReportKind.folderMoved], [
      ReportItem(
        p.join(band, 'Artist', 'New', 'One'),
        p.join(band, 'Artist', 'One'),
      ),
    ], reason: 'what was done before stopping is reported');
    expect(
      Directory(p.join(band, 'Artist', 'New', 'One')).existsSync(),
      isTrue,
    );
    expect(Directory(p.join(band, 'Artist', 'Two')).existsSync(), isTrue);
    expect(
      container.read(titlesProvider).map((t) => t.path),
      contains('Artist/New/One'),
    );
    final known = (await readLibrary(MountedFolderStorage(band)))!.knownValues;
    expect(known.knows(['Artist', 'New']), isTrue);
  });
}
