import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_catalog.dart';
import 'reaper.dart';

/// Opening of the versions and backups in REAPER.
class ReaperActions {
  ReaperActions(this.ref);

  final Ref ref;

  LibraryEntry _entry(LibraryId id) =>
      ref.read(libraryCatalogProvider).entry(id);

  /// Opens [backup] of [title] in REAPER, after normalizing its paths
  /// (REAPER lengthens them on every save of a backup, SPEC §5.4). Returns
  /// false if REAPER is not found.
  Future<bool> openBackup(Title title, Backup backup) async {
    final executable = await ref.read(reaperExecutableProvider.future);
    if (executable == null) return false;
    final root = _entry(title.libraryId).libraryRoot;
    final path = backup.path;
    await Isolate.run(() => cleanBackupPaths(MountedFolderStorage(root), path));
    await ref.read(reaperLauncherProvider)(
      executable,
      p.joinAll([root, ...path.split('/')]),
    );
    return true;
  }

  /// Opens [version] of [title] in REAPER. Returns false if REAPER is not
  /// found.
  Future<bool> openVersion(Title title, Version version) async {
    final executable = await ref.read(reaperExecutableProvider.future);
    if (executable == null) return false;
    await ref.read(reaperLauncherProvider)(
      executable,
      versionPath(_entry(title.libraryId), title, version),
    );
    return true;
  }
}

/// Absolute path of the project file of [version] of [title], in the
/// library [entry].
String versionPath(LibraryEntry entry, Title title, Version version) =>
    p.joinAll([
      entry.libraryRoot,
      ...title.path.split('/'),
      ...version.fileName.split('/'),
    ]);

final reaperActionsProvider = Provider<ReaperActions>(ReaperActions.new);
