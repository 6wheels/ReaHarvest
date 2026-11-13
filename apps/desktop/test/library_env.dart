import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/state/library_catalog.dart';
import 'package:reaharvest/state/library_scans.dart';
import 'package:reaharvest/state/migration_actions.dart';
import 'package:reaharvest/state/reaper_actions.dart';
import 'package:reaharvest/state/version_actions.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'helpers.dart';

late Directory root;
late ProviderContainer container;
late LocalIndex index;
late List<String> launched;

LibraryCatalog get catalog => container.read(libraryCatalogProvider);
LibraryScans get scans => container.read(libraryScansProvider);
VersionActions get versions => container.read(versionActionsProvider);
MigrationActions get migration => container.read(migrationActionsProvider);
ReaperActions get reaper => container.read(reaperActionsProvider);

String folder(String name) {
  final dir = Directory(p.join(root.path, name))..createSync();
  return dir.path;
}

/// Registers the set up and tear down of a test file over real services: a
/// temporary root, an index file in it (written by background isolates,
/// read-only here, like the app) and a recording REAPER launcher.
void setUpLibraryEnv() {
  setUp(() async {
    launched = [];
    root = Directory.systemTemp.createTempSync('reaharvest_app_');
    final indexPath = p.join(root.path, 'index.sqlite');
    await createIndex(indexPath);
    index = LocalIndex.open(indexPath, readOnly: true);
    container = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings(identity: const LocalIdentity(MemberId('M'), 'Alice')),
        ),
        settingsProvider.overrideWith(MemorySettings.new),
        indexPathProvider.overrideWithValue(indexPath),
        localIndexProvider.overrideWithValue(index),
        defaultReaperResourcesProvider.overrideWithValue(
          p.join(root.path, 'resources'),
        ),
        detectedReaperProvider.overrideWith((ref) async => null),
        reaperLauncherProvider.overrideWithValue(
          (executable, file) async => launched.add(file),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    index.close();
    root.deleteSync(recursive: true);
  });
}

/// Library `Band` holding `Artist/Album/Song/v1.rpp` (not adopted).
Future<String> bandWithSong() async {
  final band = folder('Band');
  final song = p.join(band, 'Artist', 'Album', 'Song');
  Directory(song).createSync(recursive: true);
  File('../../test/fixtures/tracks.rpp').copySync(p.join(song, 'v1.rpp'));
  await catalog.addLocal(
    folder: band,
    displayName: '',
    layout: Layout.classic(),
  );
  return song;
}

Title title() => index.titles().single;
Version version(String name) =>
    title().versions.firstWhere((v) => v.fileName == name);
