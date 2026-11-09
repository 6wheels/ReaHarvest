import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'app.dart';
import 'app_paths.dart';
import 'demo_titles.dart';
import 'state/libraries.dart';
import 'state/navigation.dart';
import 'state/providers.dart';

const _demo = bool.fromEnvironment('REAHARVEST_DEMO');

/// Entry point: the only place where concrete adapters are created and
/// injected (SPEC §7.2).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
  });

  final appData = appDataDirectory();
  final settingsPath = dataFilePath('settings.json', appData: appData);
  final indexPath = dataFilePath('index.sqlite', appData: appData);
  Directory(appData).createSync(recursive: true);
  final settingsFile = SettingsFile(settingsPath);
  final settings = await settingsFile.load();

  final container = ProviderContainer(
    overrides: [
      settingsFileProvider.overrideWithValue(settingsFile),
      initialSettingsProvider.overrideWithValue(settings),
      localIndexProvider.overrideWithValue(LocalIndex.open(indexPath)),
      if (_demo) ...[
        titlesProvider.overrideWithValue(demoTitles()),
        indexedLibrariesProvider.overrideWithValue({
          demoLibrary.id: demoLibrary,
        }),
        toSortProvider.overrideWithValue(const []),
      ],
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReaHarvestApp(),
    ),
  );
  // Indexed titles are shown at once; the scan then refreshes them.
  if (!_demo) unawaited(container.read(libraryServiceProvider).scanAll());
}
