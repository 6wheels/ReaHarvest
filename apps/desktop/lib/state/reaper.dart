import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_reaper/reaharvest_reaper.dart';

import 'providers.dart';

/// REAPER executable found on this machine (SPEC §5.1), null if none.
final detectedReaperProvider = FutureProvider<String?>(
  (ref) => detectReaperExecutable(),
);

/// Default REAPER resource folder of this OS.
final defaultReaperResourcesProvider = Provider<String?>(
  (ref) => defaultResourcePath(Platform.operatingSystem, Platform.environment),
);

/// REAPER executable in use: configured, else detected.
final reaperExecutableProvider = FutureProvider<String?>((ref) async {
  final configured = ref.watch(
    settingsProvider.select((s) => s.reaperExecutable),
  );
  return configured ?? await ref.watch(detectedReaperProvider.future);
});

/// REAPER resource folder in use: configured, else the default.
final reaperResourcesProvider = Provider<String?>(
  (ref) =>
      ref.watch(settingsProvider.select((s) => s.reaperResources)) ??
      ref.watch(defaultReaperResourcesProvider),
);

/// Project templates folder in use: configured, else `ProjectTemplates` in
/// the REAPER resource folder.
final templatesFolderProvider = Provider<String?>((ref) {
  final configured = ref.watch(
    settingsProvider.select((s) => s.templatesFolder),
  );
  final resources = ref.watch(reaperResourcesProvider);
  return configured ??
      (resources == null ? null : p.join(resources, 'ProjectTemplates'));
});

/// Peaks preference of `REAPER.ini`; null when it cannot be read.
final peaksPreferenceProvider = FutureProvider<PeaksPreference?>((ref) async {
  final resources = ref.watch(reaperResourcesProvider);
  if (resources == null) return null;
  try {
    return await loadPeaksPreference(resources);
  } on FileSystemException {
    return null;
  }
});

/// Whether REAPER is running (SPEC §5.7), checked before changing a project.
final reaperRunningProvider = Provider<Future<bool> Function()>(
  (ref) => isReaperRunning,
);

/// Opens a project file in REAPER (SPEC §5.7); replaced by a fake in tests.
final reaperLauncherProvider =
    Provider<Future<void> Function(String executable, String projectFile)>(
      (ref) => openInReaper,
    );
