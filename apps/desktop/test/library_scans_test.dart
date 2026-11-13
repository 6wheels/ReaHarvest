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
