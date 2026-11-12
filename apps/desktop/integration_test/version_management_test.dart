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
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/ui/overview.dart';
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
    Directory(song).createSync(recursive: true);
    File(fixture('tracks.rpp')).copySync(p.join(song, 'v1.rpp'));
    File(p.join(song, 'Media', 'unused.wav'))
      ..createSync(recursive: true)
      ..writeAsStringSync('unused');
    final templates = p.join(root.path, 'resources', 'ProjectTemplates');
    Directory(templates).createSync(recursive: true);
    File(fixture('project-template.rpp'))
        .copySync(p.join(templates, 'Band template.rpp'));

    final data = p.join(root.path, 'data');
    Directory(data).createSync();
    final settingsFile = SettingsFile(p.join(data, 'settings.json'));
    container = ProviderContainer(
      overrides: [
        settingsFileProvider.overrideWithValue(settingsFile),
        initialSettingsProvider.overrideWithValue(
          AppSettings(
            identity: LocalIdentity(MemberId.generate(), 'Tester'),
            language: 'en',
          ),
        ),
        localIndexProvider.overrideWithValue(
          LocalIndex.open(p.join(data, 'index.sqlite')),
        ),
        defaultReaperResourcesProvider.overrideWithValue(
          p.join(root.path, 'resources'),
        ),
        reaperRunningProvider.overrideWithValue(() async => reaperRunning),
        logFolderProvider.overrideWithValue(p.join(data, 'logs')),
      ],
    );
    await container
        .read(libraryServiceProvider)
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
    expect(find.text('v1.rpp'), findsOne);

    // New version from a template, with the suggested file name.
    await tapText(tester, 'New version');
    await tester.enterText(field('Label'), 'bridge');
    await tester.pumpAndSettle();
    expect(field('Song - bridge.RPP'), findsOne);
    await tapText(tester, 'From a template');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tapText(tester, 'Band template');
    await tapText(tester, 'Create');
    await waitFor(
      tester,
      // Adopted versions are shown by their label.
      () => find.text('bridge').evaluate().isNotEmpty,
      reason: 'version created',
    );
    // The project holds its id only; the label is in the node file.
    final bridge = metadataOf('Song - bridge.RPP')!;
    expect(
      RppProject.parse(file('Song - bridge.RPP').readAsStringSync())
          .extState(VersionMetadata.section)
          .keys,
      ['VERSIONID'],
    );
    expect(labelOf(bridge.id), 'bridge');
    final record = RppProject.parse(
      file('Song - bridge.RPP').readAsStringSync(),
    ).document.root.line('RECORD_PATH');
    expect(record?.params.first, 'Media');

    // Duplicate the selected version.
    await openMenu(tester);
    await tapText(tester, 'Duplicate…');
    await tapText(tester, 'Copy of “Song - bridge”');
    await tester.enterText(field('Label'), 'solo');
    await tester.pumpAndSettle();
    await tapText(tester, 'Create');
    await waitFor(
      tester,
      () =>
          file('Song - solo.RPP').existsSync() &&
          find.text('solo').evaluate().isNotEmpty,
      reason: 'version duplicated',
    );
    final copy = metadataOf('Song - solo.RPP')!;
    expect(copy.id, isNot(metadataOf('Song - bridge.RPP')!.id));

    // Rename it and change its label.
    await openMenu(tester);
    await tapText(tester, 'Rename…');
    await tester.enterText(field('File name'), 'Song - bridge');
    await tester.pumpAndSettle();
    expect(find.text('A version already has this name'), findsOne);
    await tester.enterText(field('File name'), 'Song - guitar solo');
    await tester.enterText(field('Label'), 'guitar');
    await tester.pumpAndSettle();
    await tapText(tester, 'Save');
    await waitFor(
      tester,
      () =>
          file('Song - guitar solo.RPP').existsSync() &&
          find.text('guitar').evaluate().isNotEmpty,
      reason: 'version renamed',
    );
    expect(file('Song - solo.RPP').existsSync(), isFalse);
    final renamed = metadataOf('Song - guitar solo.RPP')!;
    expect((renamed.id, labelOf(renamed.id)), (copy.id, 'guitar'));

    // A label alone: no REAPER warning, the project left untouched.
    reaperRunning = true;
    final bytes = file('Song - guitar solo.RPP').readAsBytesSync();
    final date = DateTime(2025, 5, 6);
    file('Song - guitar solo.RPP').setLastModifiedSync(date);
    await openMenu(tester);
    await tapText(tester, 'Rename…');
    await tester.enterText(field('Label'), 'lead');
    await tester.pumpAndSettle();
    await tapText(tester, 'Save');
    expect(find.text('REAPER is open'), findsNothing);
    await waitFor(
      tester,
      () => find.text('lead').evaluate().isNotEmpty,
      reason: 'label edited',
    );
    expect(labelOf(renamed.id), 'lead');
    expect(file('Song - guitar solo.RPP').readAsBytesSync(), bytes);
    expect(file('Song - guitar solo.RPP').lastModifiedSync(), date);
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

    // Backup point, listed in the history.
    await tapText(tester, 'Create a backup point');
    await waitFor(
      tester,
      () => find.text('No backup point yet.').evaluate().isEmpty,
      reason: 'backup listed',
    );
    expect(
      Directory(p.join(song, '.history')).listSync().whereType<File>(),
      hasLength(1),
    );

    // Move to the trash.
    await openMenu(tester);
    await tapText(tester, 'Move to the trash');
    expect(find.text('Move “Song - guitar solo” to the trash?'), findsOne);
    await tapText(tester, 'Move to the trash');
    await waitFor(
      tester,
      () =>
          file('.trash/Song - guitar solo.RPP').existsSync() &&
          find.text('lead').evaluate().isEmpty,
      reason: 'version trashed',
    );

    // Empty the trash, then purge the unused media.
    await tapText(tester, 'Trash');
    await waitFor(
      tester,
      () => find.text('Song - guitar solo.RPP').evaluate().isNotEmpty,
      reason: 'trash listed',
    );
    await tapText(tester, 'Empty the trash');
    expect(find.text('Delete 1 file permanently?'), findsOne);
    await tapText(tester, 'Delete permanently');
    await waitFor(
      tester,
      () => find.text('Unused media').evaluate().isNotEmpty,
      reason: 'unused media offered',
    );
    expect(file('.trash/Song - guitar solo.RPP').existsSync(), isFalse);
    expect(find.text('unused.wav · 6 B'), findsOne);
    await tapText(tester, 'Delete permanently');
    await waitFor(
      tester,
      () => !file('Media/unused.wav').existsSync(),
      reason: 'media purged',
    );
    expect(find.text('The trash is empty.'), findsOne);
    expect(file('Song - bridge.RPP').existsSync(), isTrue);
    expect(file('v1.rpp').existsSync(), isTrue);
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
    final service = container.read(libraryServiceProvider);
    final values = await tester.runAsync(
      () => service.prefillKnownValues(mess, Layout.classic()),
    );
    expect(values, const [
      KnownValue('Artist', [KnownValue('Album')]),
    ]);
    final adding = service.addLocal(
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
    final service = container.read(libraryServiceProvider);
    final adding = service.addLocal(
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

    final cancelled = service.scanAll();
    container.read(tasksProvider.notifier).cancel(tasks().last.id);
    await waitFor(
      tester,
      () => !tasks().last.isRunning,
      reason: 'scan cancelled',
    );
    await cancelled;
    expect(tasks().last.state, TaskState.cancelled);
    expect(find.text('Cancelled'), findsOne);

    final scanning = service.scanAll();
    await waitFor(tester, () => !tasks().last.isRunning, reason: 'scan done');
    await scanning;
    expect(tasks().last.state, TaskState.done);
    expect(tasks().last.progress, 1);

    // The report of the startup-like scan waits in the tasks zone (#63).
    expect(find.text('Libraries scanned · 2'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Report').last);
    await tester.pumpAndSettle();
    expect(find.text('Libraries scanned · 2'), findsOne);
    await tapText(tester, 'Close');
    await tapText(tester, 'Tasks · 4');
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

  testWidgets('normalizes media and moves a loose project (#69)', (
    tester,
  ) async {
    final band = p.dirname(p.dirname(p.dirname(song)));
    final source = File(fixture('tracks.rpp')).readAsStringSync();
    final names = {
      for (final ref in RppProject.parse(source).mediaFiles)
        ref.split(r'\').last,
    };
    // Media of the title in place: no issue for it.
    for (final name in names) {
      file('Media/$name').writeAsStringSync(name);
    }
    // A second title whose media are in a member subfolder, and a loose
    // project above the title level using identical media.
    final members = rewriteMediaPaths(
      source,
      (ref) => 'Alice\\audio\\${ref.split(r'\').last}',
    );
    final loose = rewriteMediaPaths(
      source,
      (ref) => 'audio-files\\${ref.split(r'\').last}',
    );
    final other = p.join(band, 'Artist', 'Album', 'Other');
    Directory(p.join(other, 'Alice', 'audio')).createSync(recursive: true);
    File(p.join(other, 'v.rpp')).writeAsStringSync(members);
    Directory(p.join(band, 'Artist', 'audio-files')).createSync();
    File(p.join(band, 'Artist', 'loose.rpp')).writeAsStringSync(loose);
    for (final name in names) {
      File(p.join(other, 'Alice', 'audio', name)).writeAsStringSync(name);
      File(p.join(band, 'Artist', 'audio-files', name)).writeAsStringSync(name);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReaHarvestApp(),
      ),
    );
    await tester.pumpAndSettle();
    List<BackgroundTask> tasks() => container.read(tasksProvider);
    final service = container.read(libraryServiceProvider);
    final scanning = service.scanAll();
    await waitFor(tester, () => !tasks().last.isRunning, reason: 'scan done');
    await scanning;

    // Render targets are only reported here (#84).
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
    expect(find.text("MEDIA OUTSIDE THE TITLE'S MEDIA FOLDER · 1"), findsOne);
    expect(find.text(r'Alice\audio\02-Kick-261108_1909.wav'), findsOne);

    // Normalization of the title, from its section.
    await tapText(tester, 'Fix…');
    expect(
      find.text(
        'whole title Artist/Album/Other: media into Media, record path Media',
      ),
      findsOne,
    );
    await tapText(tester, 'Fix 1 item');
    await waitFor(
      tester,
      () => find.text('Media moved · ${names.length}').evaluate().isNotEmpty,
      reason: 'normalization report',
    );
    expect(find.text('Projects normalized · 1'), findsOne);
    expect(find.textContaining('Files missing or changed'), findsNothing);
    await tapText(tester, 'Close');
    final normalized = RppProject.parse(
      File(p.join(other, 'v.rpp')).readAsStringSync(),
    );
    expect(normalized.recordPath, r'.\Media');
    expect(normalized.mediaFiles, everyElement(startsWith(r'Media\')));
    for (final name in names) {
      expect(File(p.join(other, 'Media', name)).existsSync(), isTrue);
      expect(File(p.join(other, 'Alice', 'audio', name)).existsSync(), isFalse);
    }

    // Guided move of the loose project into that title: its media are
    // identical to the pool ones, which it uses.
    expect(find.text('PROJECTS ABOVE THE TITLE LEVEL · 1'), findsOne);
    await tapText(tester, 'Move…');
    await tester.enterText(field('Album'), 'Album');
    await tester.enterText(field('Title'), 'Other');
    await tester.pumpAndSettle();
    await tapText(tester, 'Move');
    await waitFor(
      tester,
      () => find.text('Project moved · 1').evaluate().isNotEmpty,
      reason: 'move report',
    );
    expect(
      find.text('Duplicate media moved to the trash · ${names.length}'),
      findsOne,
    );
    expect(find.textContaining('Files missing or changed'), findsNothing);
    await tapText(tester, 'Close');
    final moved = RppProject.parse(
      File(p.join(other, 'loose.rpp')).readAsStringSync(),
    );
    expect(moved.recordPath, 'Media');
    expect(moved.mediaFiles, everyElement(startsWith(r'Media\')));
    for (final name in names) {
      expect(File(p.join(other, '.trash', name)).existsSync(), isTrue);
    }
    expect(File(p.join(band, 'Artist', 'loose.rpp')).existsSync(), isFalse);
    await waitFor(
      tester,
      () => find
          .textContaining('PROJECTS ABOVE THE TITLE LEVEL')
          .evaluate()
          .isEmpty,
      reason: 'rescanned',
    );
    expect(
      find.textContaining("MEDIA OUTSIDE THE TITLE'S MEDIA"),
      findsNothing,
    );
  });
}
