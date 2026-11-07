import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'providers.dart';
import 'reaper.dart';

/// Why a folder cannot become a library.
enum LibraryProblem {
  /// The folder holds a cloud or collab library (milestone B).
  unsupportedMode,

  /// The folder is, contains or is inside a folder of another library.
  overlap,

  /// The folder holds an unreadable `.library.json`.
  invalidFile,

  /// The library already holds titles: its layout cannot change without a
  /// migration (SPEC §3.1).
  layoutLocked,
}

final class LibraryException implements Exception {
  const LibraryException(this.problem);

  final LibraryProblem problem;

  @override
  String toString() => 'LibraryException($problem)';
}

/// Library operations: creation or attachment, removal, and scanning into
/// the local index (SPEC §5.1, §8).
class LibraryService {
  LibraryService(this.ref);

  final Ref ref;

  /// Library already described in [folder] (`.library.json`), or null.
  /// Throws [LibraryException] if the file is unreadable.
  Future<Library?> existing(String folder) async {
    try {
      return await readLibrary(MountedFolderStorage(folder));
    } on FormatException {
      throw const LibraryException(LibraryProblem.invalidFile);
    } on TypeError {
      throw const LibraryException(LibraryProblem.invalidFile);
    }
  }

  /// Whether the layout of the library at [folder] can no longer change:
  /// the folder already holds projects (SPEC §3.1).
  Future<bool> isLayoutLocked(String folder) => _hasProjects(folder);

  /// Adds the local library at [folder] with [layout] (null: free tree):
  /// attaches the library already described there (keeping its id, and
  /// replacing its layout if it differs and is not locked), or creates it.
  /// Then scans it. Throws [LibraryException].
  Future<void> addLocal({
    required String folder,
    required String displayName,
    required Layout? layout,
  }) async {
    final found = await existing(folder);
    if (found != null && found.mode != LibraryMode.local) {
      throw const LibraryException(LibraryProblem.unsupportedMode);
    }
    final changed = found == null || !sameLayout(found.layout, layout);
    if (found != null && changed && await isLayoutLocked(folder)) {
      throw const LibraryException(LibraryProblem.layoutLocked);
    }
    final library = changed
        ? Library(
            id: found?.id ?? LibraryId.generate(),
            mode: LibraryMode.local,
            layout: layout,
          )
        : found;
    final entry = LibraryEntry(
      id: library.id,
      displayName: displayName.trim().isEmpty
          ? p.basename(folder)
          : displayName.trim(),
      workspaceRoot: folder,
    );
    final settings = ref.read(settingsProvider);
    final AppSettings updated;
    try {
      updated = settings.addLibrary(entry);
    } on ArgumentError {
      throw const LibraryException(LibraryProblem.overlap);
    }
    if (changed) await writeLibrary(MountedFolderStorage(folder), library);
    await ref.read(settingsProvider.notifier).change((_) => updated);
    await scan(entry);
  }

  /// Forgets [id]: settings and index only, files are left untouched.
  Future<void> remove(LibraryId id) async {
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.removeLibrary(id));
    ref.read(localIndexProvider).removeLibrary(id);
    ref.read(indexRevisionProvider.notifier).bump();
  }

  /// Adopts [version] of [title] ("To adopt", SPEC §4.2): writes a new
  /// version id, the local member as owner and [label] into the project,
  /// then rescans.
  Future<void> adopt(Title title, Version version, String label) =>
      _writeMetadata(
        title,
        version,
        VersionMetadata(
          id: VersionId.generate(),
          owner: ref.read(settingsProvider).identity.memberId,
          label: label.trim(),
        ),
      );

  /// Makes the manual duplicate [version] of [title] a new version (SPEC
  /// §4.2): new id, owned by the local member, label kept. Then rescans.
  Future<void> separateDuplicate(Title title, Version version) =>
      _writeMetadata(
        title,
        version,
        VersionMetadata(
          id: VersionId.generate(),
          owner: ref.read(settingsProvider).identity.memberId,
          label: version.metadata?.label ?? '',
        ),
      );

  Future<void> _writeMetadata(
    Title title,
    Version version,
    VersionMetadata metadata,
  ) async {
    final entry = _entry(title.libraryId);
    final root = entry.libraryRoot;
    final path = title.path.isEmpty
        ? version.fileName
        : '${title.path}/${version.fileName}';
    await Isolate.run(
      () => writeVersionMetadata(MountedFolderStorage(root), path, metadata),
    );
    await scan(entry);
  }

  /// Moves the misplaced project [path] of [library] into the title at
  /// [folders] (one folder name per layout level), with its media ("To
  /// sort", SPEC §5.2). Then rescans.
  Future<MoveReport> moveToTitle(
    LibraryId library,
    String path,
    List<String> folders,
  ) async {
    final entry = _entry(library);
    final root = entry.libraryRoot;
    final report = await Isolate.run(
      () => moveProjectToTitle(
        MountedFolderStorage(root),
        path,
        folders.join('/'),
      ),
    );
    await scan(entry);
    return report;
  }

  /// Backs up [version] of [title] into its `.history/` (UI: « Créer un
  /// point de sauvegarde », SPEC §5.4); the version is unchanged.
  Future<void> backup(Title title, Version version) async {
    final root = _entry(title.libraryId).libraryRoot;
    await Isolate.run(
      () => backupVersion(
        MountedFolderStorage(root),
        title.path,
        version.fileName,
      ),
    );
    ref.invalidate(historyProvider(title.id));
  }

  /// Restores [backup] into [version] of [title], after backing up its
  /// current state (SPEC §5.4). Then rescans.
  Future<void> restore(Title title, Version version, Backup backup) async {
    final entry = _entry(title.libraryId);
    final root = entry.libraryRoot;
    final path = backup.path;
    await Isolate.run(
      () => restoreBackup(
        MountedFolderStorage(root),
        title.path,
        version.fileName,
        path,
      ),
    );
    ref.invalidate(historyProvider(title.id));
    await scan(entry);
  }

  /// Opens [backup] of [title] in REAPER, after normalizing its paths
  /// (REAPER lengthens them on every save of a backup, SPEC §5.4). Returns
  /// false if REAPER is not found.
  Future<bool> openBackup(Title title, Backup backup) async {
    final executable = await ref.read(reaperExecutableProvider.future);
    if (executable == null) return false;
    final root = _entry(title.libraryId).libraryRoot;
    final path = backup.path;
    await Isolate.run(() => cleanBackupPaths(MountedFolderStorage(root), path));
    await openInReaper(executable, p.joinAll([root, ...path.split('/')]));
    return true;
  }

  /// Opens [version] of [title] in REAPER. Returns false if REAPER is not
  /// found.
  Future<bool> openVersion(Title title, Version version) async {
    final executable = await ref.read(reaperExecutableProvider.future);
    if (executable == null) return false;
    final root = _entry(title.libraryId).libraryRoot;
    await openInReaper(
      executable,
      p.joinAll([
        root,
        ...title.path.split('/'),
        ...version.fileName.split('/'),
      ]),
    );
    return true;
  }

  LibraryEntry _entry(LibraryId id) =>
      ref.read(settingsProvider).libraries.firstWhere((l) => l.id == id);

  /// Scans every configured library, one after the other.
  Future<void> scanAll() async {
    for (final entry in ref.read(settingsProvider).libraries) {
      await scan(entry);
    }
  }

  /// Scans [entry] in an isolate, incrementally from the stored scan, and
  /// updates the index. Unavailable libraries are skipped.
  Future<void> scan(LibraryEntry entry) async {
    try {
      final root = entry.libraryRoot;
      final storage = MountedFolderStorage(root);
      final library = await readLibrary(storage);
      if (library == null) return;
      final index = ref.read(localIndexProvider);
      final result = await scanFolder(
        root,
        library,
        previous: index.scanResult(library.id),
      );
      index.update(library, result);
      ref.read(indexRevisionProvider.notifier).bump();
    } on Object catch (error) {
      // The library stays configured; it is scanned again on next start.
      debugPrint('Scan of ${entry.displayName} failed: $error');
    }
  }
}

/// Whether [folder] holds a REAPER project (backups, history and trash left
/// out), listed in an isolate.
Future<bool> _hasProjects(String folder) => Isolate.run(() async {
  for (final e in await MountedFolderStorage(
    folder,
  ).list('', recursive: true)) {
    final segments = e.path.split('/');
    if (!e.isDirectory &&
        isProjectFile(segments.last) &&
        !segments.any(isExcludedFolder)) {
      return true;
    }
  }
  return false;
});

/// Same layout levels and render mapping.
bool sameLayout(Layout? a, Layout? b) =>
    jsonEncode(a?.toJson()) == jsonEncode(b?.toJson());

final libraryServiceProvider = Provider<LibraryService>(LibraryService.new);

/// Backups of the versions of a title, by version, newest first (SPEC
/// §5.4); empty for free tree titles, which have no history.
final historyProvider = FutureProvider.autoDispose
    .family<Map<VersionId, List<Backup>>, NodeId>((ref, id) async {
      final title = ref
          .watch(titlesProvider)
          .where((t) => t.id == id)
          .firstOrNull;
      if (title == null ||
          ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree !=
              false) {
        return const {};
      }
      final root = ref
          .watch(settingsProvider.select((s) => s.libraries))
          .firstWhere((l) => l.id == title.libraryId)
          .libraryRoot;
      final dir = title.path;
      return Isolate.run(() => readHistory(MountedFolderStorage(root), dir));
    });
