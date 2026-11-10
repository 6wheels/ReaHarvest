import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart' show xxh3Hasher;
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import 'navigation.dart';
import 'providers.dart';
import 'reaper.dart';
import 'tasks.dart';

final _log = Logger('library');

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
  Future<bool> isLayoutLocked(String folder) => hasProjects(folder);

  /// Whether [folder] holds a REAPER project (backups, history and trash
  /// left out).
  Future<bool> hasProjects(String folder) => _hasProjects(folder);

  /// Known values to offer for [layout] in [folder] (SPEC §3.1).
  Future<List<KnownValue>> prefillKnownValues(String folder, Layout layout) =>
      prefillKnownValuesIn(folder, layout);

  /// Adds the local library at [folder] with [layout] (null: free tree):
  /// attaches the library already described there (keeping its id, and
  /// replacing its layout if it differs and is not locked), or creates it,
  /// with [knownValues] when given (SPEC §3.1). Then scans it. Throws
  /// [LibraryException].
  Future<void> addLocal({
    required String folder,
    required String displayName,
    required Layout? layout,
    List<KnownValue> knownValues = const [],
  }) async {
    final found = await existing(folder);
    if (found != null && found.mode != LibraryMode.local) {
      throw const LibraryException(LibraryProblem.unsupportedMode);
    }
    final changed = found == null || !sameLayout(found.layout, layout);
    if (found != null && changed && await isLayoutLocked(folder)) {
      throw const LibraryException(LibraryProblem.layoutLocked);
    }
    final kept = changed
        ? Library(
            id: found?.id ?? LibraryId.generate(),
            mode: LibraryMode.local,
            layout: layout,
          )
        : found;
    final library = knownValues.isEmpty
        ? kept
        : kept.withKnownValues(knownValues);
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
    if (changed || knownValues.isNotEmpty) {
      await writeLibrary(MountedFolderStorage(folder), library);
    }
    await ref.read(settingsProvider.notifier).change((_) => updated);
    _log.info(
      '${found == null ? 'Created' : 'Attached'} library '
      '${entry.displayName} at $folder'
      '${changed && found != null ? ', layout replaced' : ''}'
      '${knownValues.isEmpty ? '' : ', ${knownValues.paths.length} known values'}',
    );
    await ref
        .read(tasksProvider.notifier)
        .run(
          (l10n) => l10n.taskScan(entry.displayName),
          (_) => _scan(entry),
          openReport: true,
        );
  }

  /// Known values of the library [entry], and those still used by a folder
  /// (paths joined with `/`), which cannot be removed (SPEC §3.1).
  Future<({List<KnownValue> values, Set<String> used})> knownValuesOf(
    LibraryEntry entry,
  ) async {
    final root = entry.libraryRoot;
    final library = await readLibrary(MountedFolderStorage(root));
    final values = library?.knownValues ?? const <KnownValue>[];
    final used = <String>{};
    for (final path in values.paths) {
      if (await Directory(p.joinAll([root, ...path])).exists()) {
        used.add(path.join('/'));
      }
    }
    return (values: values, used: used);
  }

  /// Replaces the known values of the library [entry] (SPEC §3.1). Then
  /// rescans it, as a task whose report is shown at the end.
  Future<void> setKnownValues(
    LibraryEntry entry,
    List<KnownValue> values,
  ) async {
    final storage = MountedFolderStorage(entry.libraryRoot);
    final library = await readLibrary(storage);
    if (library == null) return;
    await writeLibrary(storage, library.withKnownValues(values));
    _log.info(
      'Known values of ${entry.displayName} set: '
      '${values.paths.map((v) => v.join('/')).join(', ')}',
    );
    await ref
        .read(tasksProvider.notifier)
        .run(
          (l10n) => l10n.taskScan(entry.displayName),
          (_) => _scan(entry),
          openReport: true,
        );
  }

  /// Declared members of the library [entry] (SPEC §6.5).
  Future<List<Member>> membersOf(LibraryEntry entry) async =>
      (await readLibrary(MountedFolderStorage(entry.libraryRoot)))?.members ??
      const [];

  /// Replaces the declared members of the library [entry] (SPEC §6.5).
  /// Then rescans it, to index them.
  Future<void> setMembers(LibraryEntry entry, List<Member> members) async {
    final storage = MountedFolderStorage(entry.libraryRoot);
    final library = await readLibrary(storage);
    if (library == null) return;
    await writeLibrary(storage, library.withMembers(members));
    _log.info(
      'Members of ${entry.displayName} set: '
      '${members.map((m) => m.name).join(', ')}',
    );
    await scan(entry);
  }

  /// Adds the intermediate folders of the existing [paths] of the library
  /// [entry] (folders or titles, moved or created there) to its known
  /// values, when it declares some (SPEC §3.1): a value created by a move
  /// is no longer reported as unknown.
  Future<void> _rememberPaths(LibraryEntry entry, List<String> paths) async {
    final storage = MountedFolderStorage(entry.libraryRoot);
    final library = await readLibrary(storage);
    final layout = library?.layout;
    if (library == null || layout == null || library.knownValues.isEmpty) {
      return;
    }
    var known = library.knownValues;
    final added = <String>[];
    for (final path in paths) {
      final values = path.split('/').take(layout.levels.length - 1).toList();
      if (!known.knows(values) && await storage.stat(path) != null) {
        known = known.withPath(values);
        added.add(values.join('/'));
      }
    }
    if (added.isEmpty) return;
    await writeLibrary(storage, library.withKnownValues(known));
    _log.info(
      'Known values of ${entry.displayName} added: ${added.join(', ')}',
    );
  }

  /// Forgets [id]: settings and index only, files are left untouched.
  Future<void> remove(LibraryId id) async {
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.removeLibrary(id));
    // Reload the filter and views, cleared of the library.
    ref.invalidate(navigationProvider);
    ref.read(localIndexProvider).removeLibrary(id);
    ref.read(indexRevisionProvider.notifier).bump();
    _log.info('Removed library $id (files left untouched)');
  }

  /// Adopts [version] of [title] ("To adopt", SPEC §4.2): writes a new
  /// version id, [owner] (by default the local member) and [label] into the
  /// project, then rescans.
  Future<void> adopt(
    Title title,
    Version version,
    String label, {
    MemberId? owner,
  }) => _writeMetadata(
    title,
    version,
    VersionMetadata(
      id: VersionId.generate(),
      owner: owner ?? ref.read(settingsProvider).identity.memberId,
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
    _log.info(
      'Version $path of ${entry.displayName} adopted: id ${metadata.id}, '
      'owner ${metadata.owner}, label "${metadata.label}"',
    );
    await scan(entry);
  }

  /// Moves the misplaced project [path] of [library] into the title at
  /// [folders] (one folder name per layout level), with its media ("To
  /// sort", SPEC §5.2), as a task whose report is shown at the end. Then
  /// rescans. Returns the report, or null if the move failed.
  Future<Report?> moveToTitle(
    LibraryId library,
    String path,
    List<String> folders,
  ) {
    return _fix(_entry(library), [
      MoveProject(path, folders.join('/')),
    ], (l10n) => l10n.taskMove(p.posix.basename(path)));
  }

  /// Applies the migration [fixes] to [library] (SPEC §5.8 step 4), as a
  /// task whose report is shown at the end. Then rescans.
  Future<Report?> fix(LibraryId library, List<MigrationFix> fixes) =>
      _fix(_entry(library), fixes, (l10n) => l10n.taskFix(fixes.length));

  /// Runs [fixes] on [entry] so that no file is lost (SPEC §5.8 step 5),
  /// telling each step: first a new inventory (or the interrupted one
  /// resumed), reusing the hashes of the previous one; then the
  /// fixes one by one, each in an isolate; then the inventory check, whose
  /// gaps are reported as errors. A folder "moved" to its own place is only
  /// declared. Cancellable at every step, between two files or two fixes:
  /// the fixes done are kept, and reported. In any case, the values of the folders moved or declared join the
  /// known values, then the library is rescanned.
  Future<Report?> _fix(
    LibraryEntry entry,
    List<MigrationFix> fixes,
    String Function(AppLocalizations l10n) label,
  ) {
    final root = entry.libraryRoot;
    bool inPlace(MigrationFix fix) =>
        fix is MoveFolder && fix.target == fix.path;
    final moves = [
      for (final f in fixes)
        if (!inPlace(f)) f,
    ];
    return ref.read(tasksProvider.notifier).run(label, (task) async {
      final declared = [for (final f in fixes.where(inPlace)) f.path];
      var report = Report({ReportKind.valueDeclared: _items(root, declared)});
      for (final path in declared) {
        _log.info('${entry.displayName}: folder $path kept in place');
      }
      final applied = [...fixes.where(inPlace)];
      try {
        if (moves.isNotEmpty) {
          final storage = MountedFolderStorage(root);
          final hash = xxh3Hasher(storage);
          // A fresh inventory for each task, unless one was interrupted:
          // files changed or added since the previous one are covered.
          final previous = await Migration.latest(storage);
          final migration = previous != null && !previous.inventoryComplete
              ? previous
              : Migration.start(storage, previous: previous);
          task.step((l10n) => l10n.taskStepInventory);
          await migration.takeInventory(
            hash,
            checkCancelled: task.checkCancelled,
            onProgress: task.progress,
          );
          for (final (i, fix) in moves.indexed) {
            task.checkCancelled();
            task.step((l10n) => l10n.taskStepFix(i + 1, moves.length));
            task.progress(i / moves.length);
            final done = await _applyFixes(root, [fix]);
            applied.add(fix);
            _log.log(
              done.hasErrors ? Level.WARNING : Level.INFO,
              '${entry.displayName}: $fix\n$done',
            );
            report += done;
          }
          task.checkCancelled();
          task.step((l10n) => l10n.taskStepCheck);
          final latest = (await Migration.latest(storage))!;
          final check = await latest.check(
            hash,
            checkCancelled: task.checkCancelled,
            onProgress: task.progress,
          );
          _log.log(
            check.hasErrors ? Level.WARNING : Level.INFO,
            '${entry.displayName}: inventory checked'
            '${check.isEmpty ? ', no file lost' : '\n$check'}',
          );
          report += _rooted(root, check);
        }
      } on TaskCancelled {
        _log.warning(
          '${entry.displayName}: cancelled after '
          '${applied.length - declared.length} of ${moves.length} fixes',
        );
        // What was done before stopping is kept: the report tells it.
        throw TaskCancelled(report);
      } finally {
        // Also after a cancellation: the library shows what was moved.
        task.step((l10n) => l10n.taskStepScan);
        await _rememberPaths(entry, [
          for (final f in applied)
            switch (f) {
              MoveFolder(:final target) => target,
              MoveProject(:final titleDir) ||
              LiftProject(:final titleDir) => titleDir,
            },
        ]);
        await scan(entry);
      }
      return report;
    }, openReport: true);
  }

  /// Deletes the `.node.json` file [path] of [library], found in a folder
  /// without project (#54). Then rescans. Throws [ArgumentError] for any
  /// other file.
  Future<void> deleteOrphanNode(LibraryId library, String path) async {
    if (p.posix.basename(path) != nodeFileName) {
      throw ArgumentError.value(path, 'path', 'Not a node file');
    }
    final entry = _entry(library);
    final root = entry.libraryRoot;
    final known = ref.read(localIndexProvider).scanResult(library);
    if (!(known?.orphanNodes.contains(path) ?? false)) {
      throw ArgumentError.value(path, 'path', 'Not an orphan node file');
    }
    await MountedFolderStorage(root).delete(path);
    _log.info('Orphan node file $path of ${entry.displayName} deleted');
    await scan(entry);
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
    _log.info('Version ${_at(title, version)} backed up');
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
    _log.info('Version ${_at(title, version)} restored from $path');
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

  /// Creates the version [fileName] of [title] with [label], owned by the
  /// local member (SPEC §5.4): a copy of [source] when given, else from the
  /// project file [template], else blank (REAPER's default template for new
  /// projects when set). Then rescans. Returns its file name.
  Future<String> addVersion(
    Title title,
    String fileName,
    String label, {
    Version? source,
    String? template,
  }) async {
    final entry = _entry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final metadata = VersionMetadata(
      id: VersionId.generate(),
      owner: ref.read(settingsProvider).identity.memberId,
      label: label.trim(),
    );
    final String path;
    if (source != null) {
      final from = source.fileName;
      path = await Isolate.run(
        () => duplicateVersion(
          MountedFolderStorage(root),
          dir,
          from,
          fileName,
          metadata,
        ),
      );
    } else {
      final file = template ?? await _defaultTemplate();
      final text = file == null ? null : await File(file).readAsString();
      path = await Isolate.run(
        () => createVersion(
          MountedFolderStorage(root),
          dir,
          fileName,
          metadata,
          template: text,
        ),
      );
    }
    _log.info(
      'Version $path of ${entry.displayName} created'
      '${source != null ? ' from ${source.fileName}' : ''}'
      '${template != null ? ' from template $template' : ''}'
      ', label "${metadata.label}"',
    );
    await scan(entry);
    return p.posix.basename(path);
  }

  Future<String?> _defaultTemplate() async {
    final resources = ref.read(reaperResourcesProvider);
    return resources == null ? null : loadDefaultProjectTemplate(resources);
  }

  /// Sets the [label] of [version] of [title] (adopted versions only) and
  /// renames its file to [fileName] (SPEC §5.4); unchanged values are left
  /// as is. Then rescans. Returns its file name.
  Future<String> editVersion(
    Title title,
    Version version, {
    required String fileName,
    required String label,
  }) async {
    final entry = _entry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final old = version.fileName;
    final m = version.metadata;
    final relabel = m != null && m.label != label.trim();
    final name = await Isolate.run(() async {
      final storage = MountedFolderStorage(root);
      if (relabel) await setVersionLabel(storage, dir, old, label.trim());
      if (fileName == old) return old;
      return p.posix.basename(await renameVersion(storage, dir, old, fileName));
    });
    _log.info(
      'Version ${_at(title, version)} edited'
      '${relabel ? ', label "${label.trim()}"' : ''}'
      '${name != old ? ', renamed to $name' : ''}',
    );
    await scan(entry);
    return name;
  }

  /// Sets the [status] of [version] of [title] (null clears it), in the
  /// title's `.node.json` (SPEC §5.9). Then rescans.
  Future<void> setStatusOf(Title title, Version version, String? status) async {
    final entry = _entry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final key = version.key;
    await Isolate.run(
      () => setVersionStatus(MountedFolderStorage(root), dir, key, status),
    );
    _log.info('Status of version ${_at(title, version)} set to $status');
    await scan(entry);
  }

  /// Moves [version] of [title] to the trash (SPEC §5.4). Then rescans.
  Future<void> trashVersion(Title title, Version version) async {
    final entry = _entry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final name = version.fileName;
    await Isolate.run(
      () => deleteVersion(MountedFolderStorage(root), dir, name),
    );
    _log.info('Version ${_at(title, version)} moved to the trash');
    ref.invalidate(trashProvider(title.id));
    await scan(entry);
  }

  /// Permanently deletes the trash files [paths] of [title] (SPEC §5.4).
  /// Then returns the media of its pool used by no project any more, to
  /// offer their purge; empty in a free tree, which has no pool. Throws
  /// [FormatException] if a project cannot be read.
  Future<List<StorageEntry>> purge(Title title, List<String> paths) async {
    final root = _entry(title.libraryId).libraryRoot;
    final dir = title.path;
    final freeTree = _isFreeTree(title);
    await Isolate.run(() => purgeTrash(MountedFolderStorage(root), dir, paths));
    _log.info('Trash of $dir in $root purged: ${paths.join(', ')}');
    ref.invalidate(trashProvider(title.id));
    if (freeTree) return const [];
    return Isolate.run(
      () => unreferencedMedia(MountedFolderStorage(root), dir),
    );
  }

  /// Permanently deletes the media [paths] of the pool of [title], as
  /// returned by [purge]. Then rescans.
  Future<void> purgeUnusedMedia(Title title, List<String> paths) async {
    final entry = _entry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    await Isolate.run(() => purgeMedia(MountedFolderStorage(root), dir, paths));
    _log.info('Unused media of $dir in $root purged: ${paths.join(', ')}');
    await scan(entry);
  }

  /// [version] of [title], with its library, for the logs.
  String _at(Title title, Version version) =>
      '${title.path}/${version.fileName} of '
      '${_entry(title.libraryId).displayName}';

  bool _isFreeTree(Title title) =>
      ref.read(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ?? true;

  LibraryEntry _entry(LibraryId id) =>
      ref.read(settingsProvider).libraries.firstWhere((l) => l.id == id);

  /// Scans every configured library, one after the other, as a background
  /// task cancellable between two libraries (SPEC §5.2). A failed library
  /// does not stop the others; it is reported. A [full] scan reads every
  /// file again, changed or not.
  Future<void> scanAll({bool full = false}) async {
    final entries = ref.read(settingsProvider).libraries;
    if (entries.isEmpty) return;
    await ref.read(tasksProvider.notifier).run(
      (l10n) => full ? l10n.taskFullScan : l10n.taskScanAll,
      (task) async {
        var report = const Report();
        for (final (i, entry) in entries.indexed) {
          task.checkCancelled();
          try {
            report += await _scan(entry, full: full);
          } on Object catch (error) {
            report += Report({
              ReportKind.scanFailed: [ReportItem(entry.libraryRoot, '$error')],
            });
          }
          task.progress((i + 1) / entries.length);
        }
        return report;
      },
    );
  }

  /// Scans [entry]; failures are only logged, the library stays configured
  /// and is scanned again on next start.
  Future<void> scan(LibraryEntry entry) async {
    try {
      await _scan(entry);
    } on Object catch (error) {
      _log.warning('Scan of ${entry.displayName} failed', error);
    }
  }

  /// Scans [entry] in an isolate, incrementally from the stored scan unless
  /// [full], and updates the index. Unavailable libraries are skipped. Reports the
  /// problems found (SPEC §5.2).
  Future<Report> _scan(LibraryEntry entry, {bool full = false}) async {
    final root = entry.libraryRoot;
    final storage = MountedFolderStorage(root);
    final library = await readLibrary(storage);
    if (library == null) {
      _log.warning('Library ${entry.displayName} unavailable at $root');
      return Report({
        ReportKind.libraryUnavailable: [ReportItem(root)],
      });
    }
    final index = ref.read(localIndexProvider);
    final result = await scanFolder(
      root,
      library,
      previous: full ? null : index.scanResult(library.id),
    );
    index.update(library, result);
    ref.read(indexRevisionProvider.notifier).bump();
    _log.info(
      'Scanned ${entry.displayName}: ${result.titles.length} titles, '
      '${result.issues.items.values.fold(0, (n, i) => n + i.length)} '
      'to sort, ${result.corrupted.length} corrupted',
    );
    return Report({
          ReportKind.libraryScanned: [ReportItem(root)],
          ReportKind.corrupted: _items(root, result.corrupted),
          ReportKind.orphanNode: _items(root, result.orphanNodes),
        }) +
        _rooted(root, result.issues);
  }
}

/// Applies [fixes] to the library at [root] through its migration, in an
/// isolate (top-level: the closure must not capture the service).
Future<Report> _applyFixes(String root, List<MigrationFix> fixes) =>
    Isolate.run(() async {
      final storage = MountedFolderStorage(root);
      final migration = (await Migration.latest(storage))!;
      return _rooted(root, await applyFixes(migration, fixes));
    });

/// Absolute path of the project file of [version] of [title], in the
/// library [entry].
String versionPath(LibraryEntry entry, Title title, Version version) =>
    p.joinAll([
      entry.libraryRoot,
      ...title.path.split('/'),
      ...version.fileName.split('/'),
    ]);

/// Absolute path of [path], relative to the library at [root].
String _absolute(String root, String path) =>
    p.joinAll([root, ...path.split('/')]);

/// Items for [paths] of the library at [root], as absolute paths.
List<ReportItem> _items(String root, List<String> paths) => [
  for (final path in paths) ReportItem(_absolute(root, path)),
];

/// [report] of the library at [root], with absolute paths.
Report _rooted(String root, Report report) => Report({
  for (final MapEntry(key: kind, value: items) in report.items.entries)
    kind: [for (final item in items) item.withPath(_absolute(root, item.path))],
});

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

/// Files in the trash of a title, versions and assets (SPEC §5.4).
final trashProvider = FutureProvider.autoDispose
    .family<List<StorageEntry>, NodeId>((ref, id) async {
      final title = ref
          .watch(titlesProvider)
          .where((t) => t.id == id)
          .firstOrNull;
      if (title == null) return const [];
      final root = ref
          .watch(settingsProvider.select((s) => s.libraries))
          .firstWhere((l) => l.id == title.libraryId)
          .libraryRoot;
      final dir = title.path;
      return Isolate.run(() => readTrash(MountedFolderStorage(root), dir));
    });

/// Project templates offered for a new version in library [id]: those of
/// its own templates folder, else of the configured one (SPEC §5.1).
final projectTemplatesProvider = FutureProvider.autoDispose
    .family<List<String>, LibraryId>((ref, id) async {
      final own = ref
          .watch(settingsProvider.select((s) => s.libraries))
          .where((l) => l.id == id)
          .firstOrNull
          ?.templatesFolder;
      final folder = own ?? ref.watch(templatesFolderProvider);
      return folder == null ? const [] : listProjectTemplates(folder);
    });
