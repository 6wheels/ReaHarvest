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

import 'library_env.dart';

void main() {
  setUpLibraryEnv();

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

  test('normalizes a title, keeping the date of its projects', () async {
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
    expect(index.issues(kind: ReportKind.mediaOutsidePool), hasLength(1));

    // The preview plans the operations, without making them.
    final preview = await migration.previewNormalization(id, const [
      'Artist/Album/Other',
    ]).plans;
    expect(preview['Artist/Album/Other']!.operations.map((op) => '$op'), [
      'move Artist/Album/Other/audio/a.wav -> Artist/Album/Other/Media/a.wav',
      r'rewrite Artist/Album/Other/v.rpp, audio\a.wav -> Media\a.wav',
    ]);
    expect(File(p.join(other, 'audio', 'a.wav')).existsSync(), isTrue);

    await migration.fix(id, const [NormalizeMedia('Artist/Album/Other')]);

    expect(
      File(p.join(other, 'v.rpp')).readAsStringSync(),
      contains(r'FILE "Media\a.wav"'),
    );
    expect(index.issues(kind: ReportKind.mediaOutsidePool), isEmpty);
    final title = index.titles().firstWhere((t) => t.tags['title'] == 'Other');
    expect(title.versions.single.modified, DateTime(2020, 1, 2));
    // Read again despite the same size and date.
    expect(title.versions.single.media, [r'Media\a.wav']);
    expect(
      index
          .issues(kind: ReportKind.missingMedia)
          .where((i) => i.item.path.startsWith('Artist/Album/Other/')),
      isEmpty,
    );
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

    final report = await migration.moveToTitle(id, 'Artist/loose.rpp', [
      'Artist',
      'Album',
      'Loose',
    ]);

    final root = container.read(settingsProvider).libraries.single.libraryRoot;
    expect(container.read(tasksProvider).last.error, isNull);
    final title = p.join(root, 'Artist', 'Album', 'Loose');
    expect(report!.items[ReportKind.projectMoved], [
      ReportItem(p.join(title, 'loose.rpp')),
    ]);
    // Paths in details are absolute too.
    expect(report.items[ReportKind.mediaMoved], [
      ReportItem(
        p.join(title, 'Media', 'a.wav'),
        p.join(root, 'Artist', 'a.wav'),
      ),
    ]);
    expect(
      index.titles().map((t) => t.tags['title']),
      containsAll(['Song', 'Loose']),
    );
    final task = container.read(tasksProvider).last;
    expect(task.openReport, isTrue);
    expect(task.report, same(report));
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(task.label(l10n), 'Move of “loose.rpp”');

    // A failed move is reported; the inventory check still passes.
    final failed = await migration.moveToTitle(id, 'Artist/gone.rpp', [
      'A',
      'B',
      'C',
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
    ]);
    final id = entry.id;

    final report = await migration.fix(id, const [
      LiftProject(
        'Artist/Album/Song/Bob/mix/take.rpp',
        'Artist/Album/Song',
        owner: MemberId('bob'),
        status: 'mixing',
      ),
      MoveFolder('Old', 'Artist/_Unassigned/Old'),
    ]);

    expect(report!.hasErrors, isFalse);
    expect(report.items[ReportKind.projectMoved], [
      ReportItem(p.join(song, 'take.rpp')),
    ]);
    expect(report.items[ReportKind.folderMoved], [
      ReportItem(p.join(band, 'Artist', '_Unassigned', 'Old')),
    ]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(container.read(tasksProvider).last.label(l10n), 'Fix 2 items');
    final lifted = index
        .titles()
        .firstWhere((t) => t.tags['title'] == 'Song')
        .versions
        .firstWhere((v) => v.fileName == 'take.rpp');
    expect(lifted.metadata!.owner, 'bob');
    expect(
      index.titles().map((t) => t.path),
      contains('Artist/_Unassigned/Old'),
    );
  });

  test('moved or declared folders join the known values, steps told', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    for (final name in ['One', 'Two']) {
      final dir = Directory(p.join(band, 'Artist', name))..createSync();
      File('../../test/fixtures/tracks.rpp')
          .copySync(p.join(dir.path, '$name.rpp'));
    }
    Directory(p.join(band, 'Artist', 'Live', 'Three'))
        .createSync(recursive: true);
    File('../../test/fixtures/tracks.rpp')
        .copySync(p.join(band, 'Artist', 'Live', 'Three', 'three.rpp'));
    final entry = container.read(settingsProvider).libraries.single;
    await catalog.setKnownValues(entry, const [
      KnownValue('Artist', [KnownValue('Album')]),
    ]);
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

    // Titles moved under a new album, an album declared in place.
    final report = await migration.fix(entry.id, const [
      MoveFolder('Artist/One', 'Artist/New/One'),
      MoveFolder('Artist/Two', 'Artist/New/Two'),
      MoveFolder('Artist/Live', 'Artist/Live'),
    ]);

    expect(report!.hasErrors, isFalse);
    expect(report.items[ReportKind.valueDeclared], [
      ReportItem(p.join(band, 'Artist', 'Live')),
    ]);
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
      'Fix 1 of 2',
      'Fix 2 of 2',
      'Checking that no file is lost',
      'Updating the library',
    ]);
    // Every step and every change of the library is logged.
    final name = entry.displayName;
    expect(
      logs,
      containsAllInOrder([
        'tasks Fix 3 items: started',
        'library.migration $name: folder Artist/Live kept in place',
        'tasks Fix 3 items: Inventory of the files',
        'tasks Fix 3 items: Fix 1 of 2',
        startsWith(
          'library.migration $name: Move folder Artist/One to Artist/New/One',
        ),
        'tasks Fix 3 items: Fix 2 of 2',
        startsWith(
          'library.migration $name: Move folder Artist/Two to Artist/New/Two',
        ),
        'tasks Fix 3 items: Checking that no file is lost',
        'library.migration $name: inventory checked, no file lost',
        'tasks Fix 3 items: Updating the library',
        'library.migration Known values of $name added: Artist/Live, Artist/New',
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
    final l10n = lookupAppLocalizations(const Locale('en'));
    final steps = <String>{};
    container.listen(tasksProvider, (_, tasks) {
      for (final task in tasks) {
        if (task.step case final step?) steps.add(step(l10n));
      }
    });

    // The second is asked while the first runs: it is not taken for an
    // interrupted fix, and its task is shown waiting.
    final reports = await Future.wait([
      migration.fix(entry.id, const [
        MoveFolder('Artist/One', 'Artist/New/One'),
      ]),
      migration.fix(entry.id, const [
        MoveFolder('Artist/Two', 'Artist/New/Two'),
      ]),
      migration.offerUndo(entry),
    ]);

    expect(reports[2], isFalse);
    expect((reports[0]! as Report).hasErrors, isFalse);
    expect((reports[1]! as Report).hasErrors, isFalse);
    expect(container.read(interruptedFixesProvider), isEmpty);
    expect(steps, contains('Waiting for the running task of the library'));
    expect(
      Directory(p.join(band, 'Artist', 'New', 'One')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(band, 'Artist', 'New', 'Two')).existsSync(),
      isTrue,
    );
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
    ]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    container.listen(tasksProvider, (_, tasks) {
      final task = tasks.last;
      if (task.step?.call(l10n) == 'Fix 1 of 2' && !task.cancelling) {
        container.read(tasksProvider.notifier).cancel(task.id);
      }
    });

    final report = await migration.fix(entry.id, const [
      MoveFolder('Artist/One', 'Artist/New/One'),
      MoveFolder('Artist/Two', 'Artist/New/Two'),
    ]);

    expect(report, isNull);
    final task = container.read(tasksProvider).last;
    expect(task.state, TaskState.cancelled);
    expect(task.report!.items[ReportKind.folderMoved], [
      ReportItem(p.join(band, 'Artist', 'New', 'One')),
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
