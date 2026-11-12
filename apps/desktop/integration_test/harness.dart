import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/app.dart';
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/state/pickers.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/ui/to_sort_page.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'window.dart';

/// Pickers answering with the paths queued in [answers], in order.
class QueuedPickers extends Pickers {
  QueuedPickers(this.answers);

  final List<String> answers;

  @override
  Future<String?> folder({String? initial}) async => answers.removeAt(0);

  @override
  Future<String?> reaperExecutable() async => answers.removeAt(0);
}

/// Real application on a throwaway folder, with its own settings and index
/// (#59): settings in `data/`, REAPER resource folder in `resources/`
/// (`REAPER.ini` with peaks centralized, `ProjectTemplates/`). REAPER is
/// never started: launches and folder openings are recorded.
class Harness {
  Harness() : root = Directory.systemTemp.createTempSync('reaharvest_it_') {
    Directory(p.join(resources, 'ProjectTemplates'))
        .createSync(recursive: true);
    writeReaperIni(resources, recommended: true);
    Directory(data).createSync();
  }

  final Directory root;

  String get data => p.join(root.path, 'data');
  String get resources => p.join(root.path, 'resources');
  String get settingsPath => p.join(data, 'settings.json');
  String get logs => p.join(data, 'logs');

  /// Executable reported by the REAPER detection; null: not found.
  String? detectedReaper = r'C:\Program Files\REAPER (x64)\reaper.exe';

  /// Whether a REAPER process is running.
  var reaperRunning = false;

  /// Answers of the native file dialogs, in order.
  final picks = <String>[];

  /// Projects opened in REAPER: (executable, project file).
  final launched = <(String, String)>[];

  /// Folders opened in the file manager.
  final openedFolders = <String>[];

  late ProviderContainer container;
  LocalIndex? _index;

  LibraryService get service => container.read(libraryServiceProvider);
  AppSettings get settings => container.read(settingsProvider);
  List<BackgroundTask> get tasks => container.read(tasksProvider);

  /// Writes the settings of a member who already went through the first
  /// run, in English.
  Future<void> writeSettings({String language = 'en'}) =>
      SettingsFile(settingsPath).save(
        AppSettings(
          identity: LocalIdentity(MemberId.generate(), 'Tester'),
          language: language,
        ),
      );

  /// Settings saved on disk.
  Future<AppSettings> savedSettings() => SettingsFile(settingsPath).load();

  /// Starts the application like `main()`: settings loaded from their file
  /// (created on first run), index opened, then the app pumped.
  Future<void> start(WidgetTester tester) async {
    await _fitWindow(tester);
    final settings = (await tester.runAsync(
      () => SettingsFile(settingsPath).load(),
    ))!;
    _index = LocalIndex.open(p.join(data, 'index.sqlite'));
    container = ProviderContainer(
      overrides: [
        settingsFileProvider.overrideWithValue(SettingsFile(settingsPath)),
        initialSettingsProvider.overrideWithValue(settings),
        localIndexProvider.overrideWithValue(_index!),
        logFolderProvider.overrideWithValue(logs),
        defaultReaperResourcesProvider.overrideWithValue(resources),
        detectedReaperProvider.overrideWith((ref) async => detectedReaper),
        reaperRunningProvider.overrideWithValue(() async => reaperRunning),
        reaperLauncherProvider.overrideWithValue(
          (executable, file) async => launched.add((executable, file)),
        ),
        openFolderProvider.overrideWithValue(
          (folder) async => openedFolders.add(folder),
        ),
        fileRevealerProvider.overrideWithValue((file) async {}),
        pickersProvider.overrideWithValue(QueuedPickers(picks)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReaHarvestApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Same layout on every machine, [windowSize] logical pixels (the window
  /// of a CI runner is small): the native window is resized, so that the
  /// app stays visible in it. When it cannot reach that size (small
  /// screen), the test view is overridden instead, and the window shows a
  /// blank surface.
  static Future<void> _fitWindow(WidgetTester tester) async {
    final view = tester.view;
    final target = windowSize * view.devicePixelRatio;
    bool fits() =>
        (view.physicalSize.width - target.width).abs() <= 1 &&
        (view.physicalSize.height - target.height).abs() <= 1;
    if (!fits() && resizeAppWindow(target)) {
      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!fits() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    if (fits()) return;
    view.physicalSize = windowSize;
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  }

  /// Logical size of the app window in every test.
  static const windowSize = Size(1024, 768);

  /// Quits the application, then starts it again on the same files.
  Future<void> restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    _close();
    await start(tester);
  }

  void _close() {
    container.dispose();
    _index?.close();
    _index = null;
  }

  /// Quits the application and deletes the throwaway folder.
  void dispose() {
    _close();
    root.deleteSync(recursive: true);
  }

  /// Adds the local library [name] at [folder] (in the throwaway folder),
  /// with its [knownValues], through the service, and waits for its scan.
  Future<void> addLibrary(
    WidgetTester tester,
    String name,
    Layout? layout, {
    String? folder,
    List<KnownValue> knownValues = const [],
  }) async {
    final before = tasks.length;
    final adding = service.addLocal(
      folder: folder ?? p.join(root.path, name),
      displayName: name,
      layout: layout,
      knownValues: knownValues,
    );
    await waitFor(
      tester,
      () => tasks.length > before && !tasks.last.isRunning,
      reason: 'library $name scanned',
    );
    await adding;
    await tester.pumpAndSettle();
    // The report of the added library opens at the end of its scan.
    await tapText(tester, 'Close');
  }

  /// Copies the fixture [name] to [relative] (folders split on `/`) in the
  /// throwaway folder, creating its folders. Returns its path.
  String copyFixture(String name, String relative) {
    final target = path(relative);
    Directory(p.dirname(target)).createSync(recursive: true);
    return File(fixture(name)).copySync(target).path;
  }

  /// Copies `render.rpp` to [relative] with its media in a `Media/` folder
  /// next to it: a version with nothing to sort. Returns its path.
  String copyCleanProject(String relative) {
    final project = copyFixture('render.rpp', relative);
    for (final name in ['01-261108_1921.wav', '02-261108_1921.wav']) {
      File(p.join(p.dirname(project), 'Media', name))
        ..createSync(recursive: true)
        ..writeAsStringSync(name);
    }
    return project;
  }

  /// Absolute path of [relative] (folders split on `/`) in the throwaway
  /// folder.
  String path(String relative) =>
      p.joinAll([root.path, ...relative.split('/')]);
}

/// `REAPER.ini` in [resources], peaks centralized when [recommended].
void writeReaperIni(String resources, {required bool recommended}) =>
    File(p.join(resources, 'REAPER.ini')).writeAsStringSync(
      recommended
          ? '[REAPER]\naltpeaks=1\naltpeakspath=C:\\Peaks\n'
          : '[REAPER]\naltpeaks=0\naltpeakspath=\n',
    );

/// Fixture [name], found from the working directory upwards.
String fixture(String name) {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    final candidate = File(p.join(dir.path, 'test', 'fixtures', name));
    if (candidate.existsSync()) return candidate.path;
    if (dir.parent.path == dir.path) throw StateError('No fixture $name');
  }
}

/// Pumps until [found] holds: file operations run in isolates, outside the
/// frames that pumpAndSettle waits for.
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

/// Waits until [text] is shown.
Future<void> waitForText(WidgetTester tester, String text) =>
    waitFor(tester, () => find.text(text).evaluate().isNotEmpty, reason: text);

/// Taps the last widget showing [text].
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// Taps the last widget with [tooltip].
Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip).last);
  await tester.pumpAndSettle();
}

/// Text field labelled [label] in the open dialog.
Finder dialogField(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(TextField, label),
);

/// Scrolls the "To sort" page from its top until [finder] is built and
/// visible: its list only builds the items near the screen.
Future<void> showToSort(WidgetTester tester, Finder finder) async {
  final list = find
      .descendant(
        of: find.byType(ToSortPage),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(list).position;
  position.jumpTo(0);
  await tester.pumpAndSettle();
  while (finder.evaluate().isEmpty) {
    if (position.pixels >= position.maxScrollExtent) fail('Not found');
    position.jumpTo(position.pixels + 200);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

/// Header row of the "To sort" section labelled [label].
Finder toSortSection(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Row)).first;

/// Opens the batch fix preview of the "To sort" section labelled [label].
Future<void> openSectionFix(WidgetTester tester, String label) async {
  await showToSort(tester, find.text(label));
  await tester.tap(
    find.descendant(of: toSortSection(label), matching: find.text('Fix…')),
  );
  await tester.pumpAndSettle();
}

/// Confirms the open fix preview of [count] items, then waits for the end
/// of its batch, whose report opens.
Future<void> confirmFix(WidgetTester tester, Harness h, int count) async {
  final before = h.tasks.length;
  // The tasks zone may show an earlier batch under the same label.
  await tester.tap(
    find.widgetWithText(
      FilledButton,
      count == 1 ? 'Fix 1 item' : 'Fix $count items',
    ),
  );
  await waitFor(
    tester,
    () => h.tasks.length > before && !h.tasks[before].isRunning,
    reason: 'batch done',
  );
}
