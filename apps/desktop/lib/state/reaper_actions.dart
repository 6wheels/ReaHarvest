import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_catalog.dart';
import 'reaper.dart';
import 'report_paths.dart';
import 'tasks.dart';

/// Opening of the versions and backups in REAPER.
class ReaperActions {
  ReaperActions(this.ref);

  final Ref ref;

  /// Opens [backup] of [title] in REAPER, after normalizing its paths
  /// (REAPER lengthens them on every save of a backup, SPEC §5.4), in the
  /// turn of its library. Returns false if REAPER is not found.
  Future<bool> openBackup(Title title, Backup backup) async {
    final executable = await ref.read(reaperExecutableProvider.future);
    if (executable == null) return false;
    final root = ref.libraryEntry(title.libraryId).libraryRoot;
    final path = backup.path;
    await ref
        .read(libraryTurnsProvider)
        .run(title.libraryId, () => _cleanBackupPaths(root, path));
    await ref.read(reaperLauncherProvider)(
      executable,
      p.joinAll([root, ...path.split('/')]),
    );
    return true;
  }

  /// Normalizes the paths of the backup [path] of the library at [root], in
  /// an isolate.
  static Future<void> _cleanBackupPaths(String root, String path) =>
      Isolate.run(() => cleanBackupPaths(MountedFolderStorage(root), path));

  /// Opens [version] of [title] in REAPER. Returns false if REAPER is not
  /// found.
  Future<bool> openVersion(Title title, Version version) async {
    final executable = await ref.read(reaperExecutableProvider.future);
    if (executable == null) return false;
    await ref.read(reaperLauncherProvider)(
      executable,
      versionPath(ref.libraryEntry(title.libraryId), title, version),
    );
    return true;
  }
}

final reaperActionsProvider = Provider<ReaperActions>(ReaperActions.new);
