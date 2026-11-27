import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app_paths.dart';
import 'app_window.dart';
import 'demo_titles.dart';
import 'logs.dart';
import 'perf_marks.dart';
import 'state/migration_actions.dart';
import 'state/navigation.dart';
import 'state/desktop_window_shell.dart';
import 'state/providers.dart';
import 'state/window_behavior.dart';
import 'ui/error_dialog.dart';
import 'ui/quit_dialog.dart';
import 'ui/settings_recovery.dart';

const _demo = bool.fromEnvironment('REAHARVEST_DEMO');

/// Data folder injected at build time (demo, tests); wins over portable mode.
const _dataDir = String.fromEnvironment('REAHARVEST_DATA_DIR');

/// Entry point: the only place where concrete adapters are created and
/// injected (SPEC §7.2).
Future<void> main() async {
  // Each step of startup, timed from here, logged once the window is shown.
  final startup = StepTimes('Startup');
  WidgetsFlutterBinding.ensureInitialized();
  startup.mark('binding');

  final window = appWindow;
  startup.mark('window init');
  // Not shown here: the runner shows the window with its first frame.
  window
    ?..minimumSize = const Size(900, 600).toNative()
    ..titleBarStyle = TitleBarStyle.hidden
    ..isWindowControlButtonsVisible = true;
  startup.mark('window options');

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/fonts/JetBrainsMono-OFL.txt'));
  });

  final appData = _dataDir.isEmpty ? appDataDirectory() : _dataDir;
  String path(String name) =>
      dataFilePath(name, appData: appData, injected: _dataDir.isNotEmpty);
  final settingsPath = path('settings.json');
  final indexPath = path('index.sqlite');
  Directory(appData).createSync(recursive: true);
  // Logs next to the settings (portable mode included, SPEC §8).
  final logFolder = p.join(p.dirname(settingsPath), 'logs');
  startLogging(logFolder);
  startup.mark('logging');
  Logger('app').info('Started; settings: $settingsPath, index: $indexPath');
  if (window == null) Logger('app').warning('The window was not found');
  // Unexpected errors are logged and shown in a popup (SPEC §5.2).
  var running = false;
  void unexpected(Object error, StackTrace? stack) {
    Logger('app').severe('Unexpected error', error, stack);
    // Before runApp, no first frame comes to show the window: shown here,
    // so that it can be closed.
    if (!running) window?.show();
    showErrorDialog(error, stack);
  }

  FlutterError.onError = (d) => unexpected(d.exception, d.stack);
  PlatformDispatcher.instance.onError = (error, stack) {
    unexpected(error, stack);
    return true;
  };
  final settingsFile = SettingsFile(settingsPath);
  final settings = await loadSettingsOrRecover(settingsFile, show: runApp);
  startup.mark('settings');
  // Written in background isolates only; read here, read-only (SPEC §7.1).
  await createIndex(indexPath);
  startup.mark('index');

  late final ProviderContainer container;
  final shell = DesktopWindowShell(
    window,
    () => container.read(windowBehaviorProvider),
    startup,
  );
  container = ProviderContainer(
    overrides: [
      windowShellProvider.overrideWithValue(shell),
      quitConfirmerProvider.overrideWithValue(confirmQuit),
      logFolderProvider.overrideWithValue(logFolder),
      settingsFileProvider.overrideWithValue(settingsFile),
      initialSettingsProvider.overrideWithValue(settings),
      indexPathProvider.overrideWithValue(indexPath),
      localIndexProvider.overrideWithValue(
        LocalIndex.open(indexPath, readOnly: true),
      ),
      if (_demo) ...[
        titlesProvider.overrideWithValue(demoTitles()),
        indexedLibrariesProvider.overrideWithValue({
          demoLibrary.id: demoLibrary,
        }),
        issuesProvider.overrideWithValue(const []),
        toSortProvider.overrideWithValue(const []),
      ],
    ],
  );
  await shell.start();
  container.read(windowBehaviorProvider).start();
  startup.mark('shell');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReaHarvestApp(),
    ),
  );
  running = true;
  startup.mark('runApp');
  final firstFrame = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    startup.mark('first frame');
    firstFrame.complete();
  });
  unawaited(
    Future.wait([firstFrame.future, shell.shown])
        .then((_) => Logger('app').info(startup.line)),
  );
  if (perfMode) startPerfMarks(container, appData); // coverage:ignore-line
  // Indexed titles are shown at once; the scan then refreshes them, then
  // the fixes left to undo are offered.
  if (!_demo) unawaited(container.read(migrationActionsProvider).startup());
}
