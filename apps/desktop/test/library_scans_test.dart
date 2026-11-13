import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/library_catalog.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_env.dart';

void main() {
  setUpLibraryEnv();

  test('the index is written in the background, read-only here', () async {
    final revision = container.read(indexRevisionProvider);
    await bandWithSong();
    expect(title().path, 'Artist/Album/Song');
    expect(container.read(indexRevisionProvider), greaterThan(revision));
    final ui = container.read(localIndexProvider);
    expect(
      () => ui.update(ui.libraries().single, ScanResult()),
      throwsA(anything),
    );
    expect(title().path, 'Artist/Album/Song');
  });

  test('scan skips unavailable libraries', () async {
    final settings = container.read(settingsProvider.notifier);
    await settings.change(
      (s) => s.addLibrary(
        LibraryEntry(
          id: LibraryId.generate(),
          displayName: 'Gone',
          workspaceRoot: p.join(root.path, 'missing'),
        ),
      ),
    );
    await scans.scanAll();
    expect(index.libraries(), isEmpty);
  });

  test('reports unreadable library files and survives failed scans', () async {
    final broken = folder('Broken');
    File(p.join(broken, libraryFileName)).writeAsStringSync('[]');
    await expectLater(
      catalog.existing(broken),
      throwsA(
        isA<LibraryException>()
            .having((e) => e.problem, 'problem', LibraryProblem.invalidFile)
            .having((e) => e.toString(), 'toString', contains('invalidFile')),
      ),
    );

    await container
        .read(settingsProvider.notifier)
        .change(
          (s) => s.addLibrary(
            LibraryEntry(
              id: LibraryId.generate(),
              displayName: 'Broken',
              workspaceRoot: broken,
            ),
          ),
        );
    await scans.scanAll();
    expect(index.libraries(), isEmpty);
    final task = container.read(tasksProvider).single;
    expect(task.state, TaskState.failed);
    expect(task.openReport, isFalse);
    final failed = task.report!.items[ReportKind.scanFailed]!.single;
    expect(failed.path, broken);
    expect(failed.detail, isNotEmpty);

    // A rescan after a small action fails silently, without task.
    await scans.scan(container.read(settingsProvider).libraries.single);
    expect(container.read(tasksProvider), [task]);
  });

  test('reports misplaced levels through the known values', () async {
    final song = await bandWithSong();
    final band = p.dirname(p.dirname(p.dirname(song)));
    final storage = MountedFolderStorage(band);
    final library = await readLibrary(storage);
    await writeLibrary(
      storage,
      library!.withKnownValues(const [
        KnownValue('Artist', [KnownValue('Album')]),
      ]),
    );
    Directory(p.join(band, 'Album')).createSync();
    File('../../test/fixtures/render-file.rpp')
        .copySync(p.join(band, 'Album', 'loose.rpp'));
    container.read(tasksProvider.notifier).clearFinished();

    await scans.scanAll();
    final report = container.read(tasksProvider).single.report!;
    expect(report.items[ReportKind.misplacedLevel], [
      ReportItem.misplaced(
        p.join(band, 'Album'),
        level: const LayoutLevel('album'),
        target: 'Artist/Album',
      ),
    ]);
    expect(report.items.keys, isNot(contains(ReportKind.unknownValue)));
  });

  test('rescans only the title changed by a version action', () async {
    final song = await bandWithSong();
    final other = p.join(p.dirname(song), 'Other');
    Directory(other).createSync();
    File(p.join(song, 'v1.rpp')).copySync(p.join(other, 'v1.rpp'));
    await scans.scanAll();
    Title titleAt(String name) =>
        index.titles().singleWhere((t) => t.tags['title'] == name);

    // Changes outside the application, in both titles.
    File(p.join(song, 'v1.rpp')).copySync(p.join(song, 'v2.rpp'));
    File(p.join(other, 'v1.rpp')).copySync(p.join(other, 'v2.rpp'));
    final v1 = titleAt('Song').versions.single;
    await versions.setStatusOf(titleAt('Song'), v1, 'mixing');

    expect(titleAt('Song').statusOf(v1), 'mixing');
    expect(titleAt('Song').versions, hasLength(2));
    expect(titleAt('Other').versions, hasLength(1), reason: 'not listed');
    await scans.scanAll();
    expect(titleAt('Other').versions, hasLength(2));
  });

  test('scans the whole library once a folder is no longer a title', () async {
    final band = folder('Band');
    for (final dir in ['A', p.join('A', 'B')]) {
      Directory(p.join(band, dir)).createSync();
      File('../../test/fixtures/tracks.rpp')
          .copySync(p.join(band, dir, 'v.rpp'));
    }
    await catalog.addLocal(folder: band, displayName: '', layout: null);
    final a = index.titles().single;
    expect(a.versions.map((v) => v.fileName), ['B/v.rpp', 'v.rpp']);

    await versions.trashVersion(a, a.versions.last);

    expect(index.titles().single.path, 'A/B');
  });

  test('scans the whole library when the title scan fails', () async {
    final song = await bandWithSong();
    final entry = container.read(settingsProvider).libraries.single;
    final stale = title();
    // Renamed outside the application: its folder cannot be listed.
    Directory(song).renameSync(p.join(p.dirname(song), 'Renamed'));

    await scans.rescanTitle(entry, stale);

    expect(title().path, 'Artist/Album/Renamed');
  });

  test('a failed title rescan is only logged', () async {
    final song = await bandWithSong();
    final entry = container.read(settingsProvider).libraries.single;
    File(p.join(song, 'v1.rpp')).copySync(p.join(song, 'v2.rpp'));
    // Hidden on Windows: replaced, not overwritten.
    File(p.join(entry.libraryRoot, libraryFileName))
      ..deleteSync()
      ..writeAsStringSync('[]');

    await scans.rescanTitle(entry, title());

    expect(title().versions, hasLength(1));
  });

  test('scans as background tasks', () async {
    await scans.scanAll();
    expect(container.read(tasksProvider), isEmpty, reason: 'no library');

    await catalog.addLocal(
      folder: folder('Band'),
      displayName: 'Band',
      layout: null,
    );
    // A library whose .library.json is gone (unmounted drive) is skipped.
    final gone = folder('Gone');
    await container
        .read(settingsProvider.notifier)
        .change(
          (s) => s.addLibrary(
            LibraryEntry(
              id: LibraryId.generate(),
              displayName: 'Gone',
              workspaceRoot: gone,
            ),
          ),
        );
    await scans.scanAll();
    final tasks = container.read(tasksProvider);
    expect([for (final t in tasks) t.state], [TaskState.done, TaskState.done]);
    expect([for (final t in tasks) t.openReport], [true, false]);
    expect(tasks.last.progress, 1);
    expect(tasks.first.report!.items[ReportKind.libraryScanned], [
      ReportItem(folder('Band')),
    ]);
    expect(tasks.last.report!.items[ReportKind.libraryUnavailable], [
      ReportItem(gone),
    ]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(tasks.first.label(l10n), 'Scan of “Band”');
    expect(tasks.last.label(l10n), 'Scan of the libraries');
  });
}
