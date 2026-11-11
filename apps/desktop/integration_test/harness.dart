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
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

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
    Directory(p.join(resources, 'ProjectTemplates')).createSync(recursive: true);
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
  /// through the service, and waits for its scan.
  Future<void> addLibrary(
    WidgetTester tester,
    String name,
    Layout? layout, {
    String? folder,
  }) async {
    final before = tasks.length;
    final adding = service.addLocal(
      folder: folder ?? p.join(root.path, name),
      displayName: name,
      layout: layout,
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
