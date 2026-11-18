import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/app.dart';
import 'package:reaharvest/app_paths.dart';
import 'package:reaharvest/logs.dart';
import 'package:reaharvest/state/library_catalog.dart';
import 'package:reaharvest/state/library_scans.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/ui/widgets.dart' show Dropdown;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

/// Runs the real app on a throwaway library, with its own settings and
/// index, and manages versions through the UI (#51):
/// `flutter test integration_test -d windows` in `apps/desktop`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String song;
  late ProviderContainer container;

  /// Whether REAPER is reported running (SPEC §5.7).
  var reaperRunning = false;

  /// Fixture [name], found from the working directory upwards.
  String fixture(String name) {
    for (var dir = Directory.current.absolute; ; dir = dir.parent) {
      final candidate = File(p.join(dir.path, 'test', 'fixtures', name));
      if (candidate.existsSync()) return candidate.path;
      if (dir.parent.path == dir.path) throw StateError('No fixture $name');
    }
  }

  File file(String relative) => File(p.joinAll([song, ...relative.split('/')]));

  VersionMetadata? metadataOf(String relative) => VersionMetadata.fromExtState(
    RppProject.parse(file(relative).readAsStringSync())
        .extState(VersionMetadata.section),
  );

  /// Label of the version [id] in the node file of the title (SPEC §4.2).
  String? labelOf(VersionId id) =>
      ((jsonDecode(file('.node.json').readAsStringSync())
                  as Map)['versionLabels']
              as Map?)?[id]
          as String?;

  setUp(() async {
    reaperRunning = false;
    root = Directory.systemTemp.createTempSync('reaharvest_it_');
    final band = p.join(root.path, 'Band');
    song = p.join(band, 'Artist', 'Album', 'Song');
    Directory(p.join(song, 'v1')).createSync(recursive: true);
    File(fixture('tracks.rpp')).copySync(p.join(song, 'v1', 'v1.rpp'));
    File(p.join(song, 'v1', 'Media', 'take.wav'))
      ..createSync(recursive: true)
      ..writeAsStringSync('take');
    final templates = p.join(root.path, 'resources', 'ProjectTemplates');
    Directory(templates).createSync(recursive: true);
    File(fixture('project-template.rpp'))
        .copySync(p.join(templates, 'Band template.rpp'));

    final data = p.join(root.path, 'data');
    Directory(data).createSync();
    final settingsFile = SettingsFile(p.join(data, 'settings.json'));
    final indexPath = p.join(data, 'index.sqlite');
    await createIndex(indexPath);
    container = ProviderContainer(
      overrides: [
        settingsFileProvider.overrideWithValue(settingsFile),
        initialSettingsProvider.overrideWithValue(
          AppSettings(
            identity: LocalIdentity(MemberId.generate(), 'Tester'),
            language: 'en',
          ),
        ),
        indexPathProvider.overrideWithValue(indexPath),
        localIndexProvider.overrideWithValue(
          LocalIndex.open(indexPath, readOnly: true),
        ),
        defaultReaperResourcesProvider.overrideWithValue(
          p.join(root.path, 'resources'),
        ),
        reaperRunningProvider.overrideWithValue(() async => reaperRunning),
        logFolderProvider.overrideWithValue(p.join(data, 'logs')),
      ],
    );
    await container
        .read(libraryCatalogProvider)
        .addLocal(folder: band, displayName: 'Band', layout: Layout.classic());
  });

  tearDown(() {
    container.read(localIndexProvider).close();
    container.dispose();
    root.deleteSync(recursive: true);
  });

  /// Pumps until [found] holds: file operations run in isolates, outside
  /// the frames that pumpAndSettle waits for.
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() found, {
    String? reason,
  }) async {
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (!found()) {
      if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  /// Text field labelled [label] in the open dialog.
  Finder field(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextField, label),
  );

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More actions').last);
    await tester.pumpAndSettle();
  }

  testWidgets('manages the versions of a title', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReaHarvestApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Title detail.
    await tapText(tester, 'Song');
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    // A version not adopted is headed by its file name.
    expect(find.text('v1/v1.rpp'), findsOne);

    // New version from a template, with the suggested name of its folder
    // and project.
    await tapText(tester, 'New version');
    await tester.enterText(field('Label'), 'bridge');
    await tester.pumpAndSettle();
    expect(field('Song - bridge'), findsOne);
    await tapText(tester, 'From a template');
    await tester.tap(find.byType(Dropdown<String>));
    await tester.pumpAndSettle();
    await tapText(tester, 'Band template');
    await tapText(tester, 'New version');
    await waitFor(
      tester,
      // Adopted versions are shown by their label.
      () => find.text('bridge').evaluate().isNotEmpty,
      reason: 'version created',
    );
    // A folder with its project, Media/ and Renders/. The project holds
    // its id only; the label is in the node file.
    const bridgeFile = 'Song - bridge/Song - bridge.RPP';
    final bridge = metadataOf(bridgeFile)!;
    expect(
      RppProject.parse(file(bridgeFile).readAsStringSync())
          .extState(VersionMetadata.section)
          .keys,
      ['VERSIONID'],
    );
    expect(labelOf(bridge.id), 'bridge');
    final record = RppProject.parse(file(bridgeFile).readAsStringSync())
        .document
        .root
        .line('RECORD_PATH');
    expect(record?.params.first, 'Media');
    for (final name in ['Media', 'Renders']) {
      expect(
        Directory(p.join(song, 'Song - bridge', name)).existsSync(),
        isTrue,
      );
    }

    // Duplicate the selected version.
    await openMenu(tester);
    await tapText(tester, 'Duplicate…');
    await tapText(tester, 'Copy of “Song - bridge”');
    await tester.enterText(field('Label'), 'solo');
    await tester.pumpAndSettle();
    await tapText(tester, 'Duplicate');
    await waitFor(
      tester,
      () =>
          file('Song - solo/Song - solo.RPP').existsSync() &&
          find.text('solo').evaluate().isNotEmpty,
      reason: 'version duplicated',
    );
    final copy = metadataOf('Song - solo/Song - solo.RPP')!;
    expect(copy.id, isNot(metadataOf(bridgeFile)!.id));

    // Rename it (folder and project) and change its label.
    await openMenu(tester);
    await tapText(tester, 'Rename…');
    const nameField = 'Name of the folder and project';
    await tester.enterText(field(nameField), 'Song - bridge');
    await tester.pumpAndSettle();
    expect(find.text('A version already has this name'), findsOne);
    await tester.enterText(field(nameField), 'Song - guitar solo');
    await tester.enterText(field('Label'), 'guitar');
    await tester.pumpAndSettle();
    await tapText(tester, 'Rename');
    const solo = 'Song - guitar solo/Song - guitar solo.RPP';
    await waitFor(
      tester,
      () =>
          file(solo).existsSync() && find.text('guitar').evaluate().isNotEmpty,
      reason: 'version renamed',
    );
    expect(Directory(p.join(song, 'Song - solo')).existsSync(), isFalse);
    final renamed = metadataOf(solo)!;
    expect((renamed.id, labelOf(renamed.id)), (copy.id, 'guitar'));

    // A label alone: no REAPER warning, the project left untouched.
    reaperRunning = true;
    final bytes = file(solo).readAsBytesSync();
    final date = DateTime(2025, 5, 6);
    file(solo).setLastModifiedSync(date);
    await openMenu(tester);
    await tapText(tester, 'Rename…');
    await tester.enterText(field('Label'), 'lead');
    await tester.pumpAndSettle();
    await tapText(tester, 'Rename');
    expect(find.text('REAPER is open'), findsNothing);
    await waitFor(
      tester,
      () => find.text('lead').evaluate().isNotEmpty,
      reason: 'label edited',
    );
    expect(labelOf(renamed.id), 'lead');
    expect(file(solo).readAsBytesSync(), bytes);
    expect(file(solo).lastModifiedSync(), date);
    reaperRunning = false;

    // Status, written into the title's .node.json.
    await openMenu(tester);
    await tapText(tester, 'Change status');
    await tapText(tester, 'Mixing');
    await waitFor(
      tester,
      () => file('.node.json').readAsStringSync().contains('mixing'),
      reason: 'status written',
    );

    // Backup point, listed in the history of the version.
    await tapText(tester, 'Create a backup point');
    await waitFor(
      tester,
      () => find.text('No backup point yet.').evaluate().isEmpty,
      reason: 'backup listed',
    );
    expect(
      Directory(p.join(song, 'Song - guitar solo', '.history'))
          .listSync()
          .whereType<File>(),
      hasLength(1),
    );

    // Move to the trash: the whole folder.
    await openMenu(tester);
    await tapText(tester, 'Move to the trash');
    expect(find.text('Move “Song - guitar solo” to the trash?'), findsOne);
    await tapText(tester, 'Move to the trash');
    await waitFor(
      tester,
      () =>
          file('.trash/$solo').existsSync() &&
          find.text('lead').evaluate().isEmpty,
      reason: 'version trashed',
    );
    expect(Directory(p.join(song, 'Song - guitar solo')).existsSync(), isFalse);

    // Keep only the selected version: the other one to the trash.
    final versions = ['v1/v1.rpp', bridgeFile];
    await openMenu(tester);
    await tapText(tester, 'Keep only this version…');
    expect(
      find.text(
        'The other version of this title is moved to its trash, with its '
        'folder.',
      ),
      findsOne,
    );
    await tapText(tester, 'Move the others to the trash');
    await waitFor(
      tester,
      () => versions.where((v) => file(v).existsSync()).length == 1,
      reason: 'other versions trashed',
    );

    // Empty the trash: version folders deleted whole.
    await tapText(tester, 'TRASH');
    await waitFor(
      tester,
      () => find.text('Song - guitar solo').evaluate().isNotEmpty,
      reason: 'trash listed',
    );
    await tapText(tester, 'Empty the trash');
    expect(find.text('Delete 2 items permanently?'), findsOne);
    await tapText(tester, 'Empty the trash');
    await waitFor(
      tester,
      () => find.text('The trash is empty.').evaluate().isNotEmpty,
      reason: 'trash purged',
    );
    expect(Directory(p.join(song, '.trash')).listSync(), isEmpty);
    expect(versions.where((v) => file(v).existsSync()), hasLength(1));
  });

  testWidgets('reports misplaced levels of a misorganized folder', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReaHarvestApp(),
      ),
    );
    await tester.pumpAndSettle();

    // A title in place, an album without its artist, a title placed high.
    final mess = p.join(root.path, 'Mess');
    for (final dir in ['Artist/Album/Song', 'Album/Song2', 'Loose']) {
      final folder = p.joinAll([mess, ...dir.split('/')]);
      Directory(folder).createSync(recursive: true);
      File(fixture('tracks.rpp')).copySync(p.join(folder, 'v.rpp'));
    }
    final catalog = container.read(libraryCatalogProvider);
    final values = await tester.runAsync(
      () => catalog.prefillKnownValues(mess, Layout.classic()),
    );
    expect(values, const [
      KnownValue('Artist', [KnownValue('Album')]),
    ]);
    final adding = catalog.addLocal(
      folder: mess,
      displayName: 'Mess',
      layout: Layout.classic(),
      knownValues: values!,
    );
    await waitFor(
      tester,
      () => find.text('Folders at the wrong level · 1').evaluate().isNotEmpty,
      reason: 'report opened',
    );
    await adding;
    expect(find.text('Titles placed too high · 1'), findsOne);
    expect(find.textContaining('Proposed target: Artist/Album'), findsOne);
    expect(
      find.textContaining('Proposed target: _Unassigned/_Unassigned/Loose'),
      findsOne,
    );
    expect(find.textContaining('Expected level: Album'), findsOne);
  });

  testWidgets('runs portable data, tasks, reports and logs (M0)', (
    tester,
  ) async {
    // Logs: the file sink of the app, in the temp folder (#64).
    final logs = Directory(p.join(root.path, 'logs'))..createSync();
    final logFiles = LogFiles(logs.path);
    final logging = Logger.root.onRecord.listen(logFiles.write);
    addTearDown(logging.cancel);

    // Portable mode: an empty settings.json next to the executable wins
    // and starts a new member (#61).
    final exe = Directory(p.join(root.path, 'app'))..createSync();
    File(p.join(exe.path, 'settings.json')).writeAsStringSync('');
    final portable = dataFilePath(
      'settings.json',
      appData: p.join(root.path, 'data'),
      executableDir: exe.path,
    );
    expect(portable, p.join(exe.path, 'settings.json'));
    final second = await tester.runAsync(() => SettingsFile(portable).load());
    expect(
      second!.identity.memberId,
      isNot(container.read(settingsProvider).identity.memberId),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReaHarvestApp(),
      ),
    );
    await tester.pumpAndSettle();
    List<BackgroundTask> tasks() => container.read(tasksProvider);

    // A second library, to cancel the scan between two libraries (#62).
    final other = p.join(root.path, 'Other', 'Artist', 'Album', 'Song');
    Directory(other).createSync(recursive: true);
    File(fixture('render-file.rpp')).copySync(p.join(other, 'v.rpp'));
    final catalog = container.read(libraryCatalogProvider);
    final scans = container.read(libraryScansProvider);
    final adding = catalog.addLocal(
      folder: p.join(root.path, 'Other'),
      displayName: 'Other',
      layout: Layout.classic(),
    );
    await waitFor(
      tester,
      () => tasks().length == 2 && !tasks().last.isRunning,
      reason: 'library added',
    );
    await adding;
    // Its report opens at the end of the launched action (#63).
    expect(find.text('Libraries scanned · 1'), findsOne);
    await tapText(tester, 'Close');

    final cancelled = scans.scanAll();
    container.read(tasksProvider.notifier).cancel(tasks().last.id);
    await waitFor(
      tester,
      () => !tasks().last.isRunning,
      reason: 'scan cancelled',
    );
    await cancelled;
    expect(tasks().last.state, TaskState.cancelled);
    expect(find.text('Cancelled'), findsOne);

    final scanning = scans.scanAll();
    await waitFor(tester, () => !tasks().last.isRunning, reason: 'scan done');
    await scanning;
    expect(tasks().last.state, TaskState.warning);
    expect(tasks().last.progress, 1);

    // The report of the startup-like scan waits in the tasks zone (#63).
    expect(find.text('Libraries scanned · 2'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Report').last);
    await tester.pumpAndSettle();
    expect(find.text('Libraries scanned · 2'), findsOne);
    await tapText(tester, 'Close');
    await tapText(tester, 'TASKS // 4');
    expect(find.text('Scan of “Other”'), findsOne);
    await tapText(tester, 'Clear finished');
    expect(tasks(), isEmpty);

    // Outcomes and reports are in the log of the day (#64).
    final log = File(logFiles.pathFor(DateTime.now())).readAsStringSync();
    expect(log, contains('INFO tasks: Scan of “Other”: done'));
    expect(log, contains('WARNING tasks: Scan of the libraries: cancelled'));
    expect(log, contains('INFO tasks: Scan of the libraries: done'));
    expect(log, contains('libraryScanned (2)'));
  });
}
