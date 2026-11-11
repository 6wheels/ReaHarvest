import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../logs.dart';

// Ports and resources: overridden with the concrete implementations in
// `main()` only (SPEC §7.2), and with fakes in tests.

final settingsFileProvider = Provider<SettingsFile>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Settings loaded before the first frame, to start without flicker.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

final localIndexProvider = Provider<LocalIndex>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Application settings; every change is saved.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  /// Last save, the next one waits for it.
  Future<void> _saving = Future.value();

  /// Applies [edit] at once and saves the result after the previous saves:
  /// two saves never run together (a slider changes the settings on every
  /// step).
  Future<void> change(AppSettings Function(AppSettings) edit) {
    final settings = state = edit(state);
    Future<void> save(Object? _) => persist(settings);
    return _saving = _saving.then(save, onError: save);
  }

  @protected
  Future<void> persist(AppSettings settings) =>
      ref.read(settingsFileProvider).save(settings);
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Incremented after every index change, to refresh what reads the index.
class IndexRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final indexRevisionProvider = NotifierProvider<IndexRevision, int>(
  IndexRevision.new,
);

/// All indexed titles, served from the index (SPEC §8: startup view). A free
/// tree whose root holds a project is a single title without tags (SPEC
/// §3.3): it is named after its library.
final titlesProvider = Provider<List<Title>>((ref) {
  ref.watch(indexRevisionProvider);
  final names = {
    for (final l in ref.watch(settingsProvider.select((s) => s.libraries)))
      l.id: l.displayName,
  };
  return [
    for (final t in ref.watch(localIndexProvider).titles())
      if (t.tags.isEmpty && names[t.libraryId] != null)
        Title(
          id: t.id,
          libraryId: t.libraryId,
          path: t.path,
          tags: {'title': names[t.libraryId]!},
          versions: t.versions,
          status: t.status,
          versionStatuses: t.versionStatuses,
        )
      else
        t,
  ];
});

/// Indexed libraries (mode and layout), by id.
final indexedLibrariesProvider = Provider<Map<LibraryId, Library>>((ref) {
  ref.watch(indexRevisionProvider);
  return {for (final l in ref.watch(localIndexProvider).libraries()) l.id: l};
});

/// Folder of the daily log files (SPEC §8).
final logFolderProvider = Provider<String>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Opens a folder in the system file manager; replaced by a fake in tests.
final openFolderProvider = Provider<Future<void> Function(String folder)>(
  (ref) => openFolder,
);
