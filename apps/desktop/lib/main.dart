import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'app.dart';
import 'app_paths.dart';
import 'demo_titles.dart';
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

  final dir = appDataDirectory();
  Directory(dir).createSync(recursive: true);
  final settingsFile = SettingsFile(p.join(dir, 'settings.json'));
  final settings = await settingsFile.load();

  runApp(
    ProviderScope(
      overrides: [
        settingsFileProvider.overrideWithValue(settingsFile),
        initialSettingsProvider.overrideWithValue(settings),
        localIndexProvider.overrideWithValue(
          LocalIndex.open(p.join(dir, 'index.sqlite')),
        ),
        if (_demo) titleViewsProvider.overrideWithValue(demoTitles()),
      ],
      child: const ReaHarvestApp(),
    ),
  );
}
