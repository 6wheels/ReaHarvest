import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import 'library_catalog.dart';
import 'library_scans.dart';
import 'library_turns.dart';
import 'providers.dart';
import 'reaper.dart';
import 'tasks.dart';

final _log = Logger('library.versions');

/// Actions on the versions of a title: adopt, separate a duplicate, create,
/// edit, status, trash, keep only one, purge, backup and restore (SPEC
/// §4.2, §5.4, §5.9),
/// each a foreground task in the turn of its library ([_turn]). "Then rescans": the folder of
/// the title only ([LibraryScans.rescanTitle], SPEC §8).
class VersionActions {
  VersionActions(this.ref);

  final Ref ref;

  /// Adopts [version] of [title] ("To adopt", SPEC §4.2): writes a new
  /// version id into the project, [label] and [owner] (none when the library
  /// declares no members) into the title's node file, then rescans.
  Future<void> adopt(
    Title title,
    Version version,
    String label, {
    MemberId? owner,
  }) => _turn(
    title,
    (l10n) => l10n.taskAdopt,
    () => _adopt(title, version, label, owner: owner),
  );

  Future<void> _adopt(
    Title title,
    Version version,
    String label, {
    MemberId? owner,
  }) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final name = version.fileName;
    final metadata = VersionMetadata(
      id: VersionId.generate(),
      label: label.trim(),
      owner: owner,
    );
    await Isolate.run(
      () => adoptVersion(MountedFolderStorage(root), dir, name, metadata),
    );
    _log.info(
      'Version ${_at(title, version)} adopted: id ${metadata.id}, '
      'owner ${metadata.owner}, label "${metadata.label}"',
    );
    await ref.rescanTitle(entry, title);
  }

  /// Makes the manual duplicate [version] of [title] a new version (SPEC
  /// §4.2): new id, label of the original copied (another version of the
  /// title with the same id, else [version] itself when the original is in
  /// another title), owned by the local member when the library declares
  /// it. Then rescans.
  Future<void> separateDuplicate(Title title, Version version) => _turn(
    title,
    (l10n) => l10n.taskSeparateDuplicate,
    () => _separateDuplicate(title, version),
  );

  Future<void> _separateDuplicate(Title title, Version version) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final name = version.fileName;
    final owner = ref.read(localOwnerProvider(title.libraryId));
    // The original: another version of the title sharing its id; its label
    // as shown, file name fallback included (SPEC §4.2).
    final original = title.versions
        .where(
          (v) => v.fileName != name && v.metadata?.id == version.metadata?.id,
        )
        .firstOrNull;
    final label = (original ?? version).metadata?.label ?? '';
    final id = await Isolate.run(
      () => separateDuplicateVersion(
        MountedFolderStorage(root),
        dir,
        name,
        label: label,
        owner: owner,
      ),
    );
    _log.info('Version ${_at(title, version)} separated: id $id');
    // Same size and date: read again (SPEC §4.2).
    await ref.rescanTitle(entry, title, reread: {joinPath(dir, name)});
  }

  /// Backs up [version] of [title] into its `.history/` (UI: « Créer un
  /// point de sauvegarde », SPEC §5.4); the version is unchanged.
  Future<void> backup(Title title, Version version) =>
      _turn(title, (l10n) => l10n.taskBackup, () => _backup(title, version));

  Future<void> _backup(Title title, Version version) async {
    final root = ref.libraryEntry(title.libraryId).libraryRoot;
    await Isolate.run(
      () => backupVersion(
        MountedFolderStorage(root),
        title.path,
        version.fileName,
      ),
    );
    _log.info('Version ${_at(title, version)} backed up');
    ref.invalidate(historyProvider);
  }

  /// Restores [backup] into [version] of [title], after backing up its
  /// current state (SPEC §5.4). Then rescans.
  Future<void> restore(Title title, Version version, Backup backup) => _turn(
    title,
    (l10n) => l10n.taskRestore,
    () => _restore(title, version, backup),
  );

  Future<void> _restore(Title title, Version version, Backup backup) async {
    final entry = ref.libraryEntry(title.libraryId);
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
    ref.invalidate(historyProvider);
    await ref.rescanTitle(entry, title);
  }

  /// Creates the version [name] of [title] (its folder and its `.RPP`) with
  /// [label], owned by the local member when the library declares it
  /// ([localOwnerProvider], SPEC §5.4): a copy of [source] when given, else
  /// from the project file [template], else blank (REAPER's default
  /// template for new projects when set). Then rescans. Returns its
  /// [Version.fileName].
  Future<String?> addVersion(
    Title title,
    String name,
    String label, {
    Version? source,
    String? template,
  }) => _turn(
    title,
    (l10n) => l10n.taskAddVersion,
    () => _addVersion(title, name, label, source: source, template: template),
  );

  Future<String> _addVersion(
    Title title,
    String name,
    String label, {
    Version? source,
    String? template,
  }) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final metadata = VersionMetadata(
      id: VersionId.generate(),
      owner: ref.read(localOwnerProvider(title.libraryId)),
      label: label.trim(),
    );
    final String path;
    if (source != null) {
      path = await Isolate.run(
        () => duplicateVersion(
          MountedFolderStorage(root),
          dir,
          source,
          name,
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
          name,
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
    await ref.rescanTitle(entry, title);
    return _inTitle(title, path);
  }

  Future<String?> _defaultTemplate() async {
    final resources = ref.read(reaperResourcesProvider);
    return resources == null ? null : loadDefaultProjectTemplate(resources);
  }

  /// Sets the [label] of [version] of [title] (adopted versions only), in
  /// the title's node file, and renames its folder and its `.RPP` to [name]
  /// (SPEC §5.4); the label is written when changed or on a rename. Then
  /// rescans. Returns its [Version.fileName].
  Future<String?> editVersion(
    Title title,
    Version version, {
    required String name,
    required String label,
  }) => _turn(
    title,
    (l10n) => l10n.taskEditVersion,
    () => _editVersion(title, version, name: name, label: label),
  );

  Future<String> _editVersion(
    Title title,
    Version version, {
    required String name,
    required String label,
  }) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final old = version.fileName;
    final rename = name != version.folder;
    final id = version.metadata?.id;
    // Also written on a rename: a label shown from the folder name fallback
    // would otherwise follow the new name (SPEC §4.2).
    final relabel =
        id != null && (version.metadata!.label != label.trim() || rename);
    final path = await Isolate.run(() async {
      final storage = MountedFolderStorage(root);
      if (relabel) await setVersionLabel(storage, dir, id, label.trim());
      if (!rename) return null;
      return renameVersion(storage, dir, version, name);
    });
    final fileName = path == null ? old : _inTitle(title, path);
    _log.info(
      'Version ${_at(title, version)} edited'
      '${relabel ? ', label "${label.trim()}"' : ''}'
      '${rename ? ', renamed to $fileName' : ''}',
    );
    await ref.rescanTitle(entry, title);
    return fileName;
  }

  /// Sets the [status] of [version] of [title] (null clears it), in the
  /// title's `.node.json` (SPEC §5.9). Then rescans.
  Future<void> setStatusOf(Title title, Version version, String? status) =>
      _turn(
        title,
        (l10n) => l10n.taskSetStatus,
        () => _setStatusOf(title, version, status),
      );

  Future<void> _setStatusOf(
    Title title,
    Version version,
    String? status,
  ) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final key = version.key;
    await Isolate.run(
      () => setVersionStatus(MountedFolderStorage(root), dir, key, status),
    );
    _log.info('Status of version ${_at(title, version)} set to $status');
    await ref.rescanTitle(entry, title);
  }

  /// Adds the free [tag] to [title], in the title's `.node.json` (SPEC
  /// §5.9): applied to the tags read again from the file, so that no
  /// concurrent change is lost. Then rescans.
  Future<void> addTag(Title title, String tag) => _turn(
    title,
    (l10n) => l10n.taskEditTags,
    () => _editTags(title, tag, add: true),
  );

  /// Removes the free [tag] from [title] (ignoring case), like [addTag].
  Future<void> removeTag(Title title, String tag) => _turn(
    title,
    (l10n) => l10n.taskEditTags,
    () => _editTags(title, tag, add: false),
  );

  Future<void> _editTags(Title title, String tag, {required bool add}) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final node = await Isolate.run(() {
      final storage = MountedFolderStorage(root);
      return add
          ? addTitleTag(storage, dir, tag)
          : removeTitleTag(storage, dir, tag);
    });
    _log.info('Tags of title $dir set to ${node.tags}');
    await ref.rescanTitle(entry, title);
  }

  /// Moves [version] of [title] to the trash: its whole folder (SPEC §5.4).
  /// Then rescans.
  Future<void> trashVersion(Title title, Version version) => _turn(
    title,
    (l10n) => l10n.taskTrashVersion,
    () => _trashVersion(title, version),
  );

  Future<void> _trashVersion(Title title, Version version) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    await Isolate.run(
      () => deleteVersion(MountedFolderStorage(root), dir, version),
    );
    _log.info('Version ${_at(title, version)} moved to the trash');
    ref.invalidate(trashProvider(title.id));
    await ref.rescanTitle(entry, title);
  }

  /// Moves every other version folder of [title] than the one of [version]
  /// to the trash (SPEC §5.4). Then rescans.
  Future<void> keepOnly(Title title, Version version) => _turn(
    title,
    (l10n) => l10n.taskKeepOnly,
    () => _keepOnly(title, version),
  );

  Future<void> _keepOnly(Title title, Version version) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    try {
      final trashed = await Isolate.run(
        () => keepOnlyVersion(MountedFolderStorage(root), dir, version),
      );
      _log.info(
        'Only version ${_at(title, version)} kept, moved to the trash: '
        '${trashed.join(', ')}',
      );
    } finally {
      // Also after a failure: the folders already moved are shown in the
      // trash, the others stay.
      ref.invalidate(trashProvider(title.id));
      await ref.rescanTitle(entry, title);
    }
  }

  /// Permanently deletes the trash entries [paths] of [title], version
  /// folders and assets (SPEC §5.4).
  Future<void> purge(Title title, List<String> paths) =>
      _turn(title, (l10n) => l10n.taskPurge, () => _purge(title, paths));

  Future<void> _purge(Title title, List<String> paths) async {
    final root = ref.libraryEntry(title.libraryId).libraryRoot;
    final dir = title.path;
    await Isolate.run(() => purgeTrash(MountedFolderStorage(root), dir, paths));
    _log.info('Trash of $dir in $root purged: ${paths.join(', ')}');
    ref.invalidate(trashProvider(title.id));
  }

  /// Runs [change] of [title] as a foreground task labelled [label], in the
  /// turn of its library ([LibraryTurns]): the interface is blocked by its
  /// popup, the change waits for the scan or the other action of the
  /// library, never runs with another change of the same node file, and
  /// leaves nothing in the tasks zone, its caller tells the outcome. Returns
  /// null when cancelled while it waits; rethrows what [change] throws.
  Future<T?> _turn<T>(
    Title title,
    String Function(AppLocalizations l10n) label,
    Future<T> Function() change,
  ) async {
    Object? error;
    StackTrace? stack;
    final result = await ref
        .read(tasksProvider.notifier)
        .run<T>(
          label,
          (_) async {
            try {
              return await change();
            } on Object catch (e, s) {
              (error, stack) = (e, s);
              rethrow;
            }
          },
          foreground: true,
          quiet: true,
          library: title.libraryId,
        );
    if (error case final e?) Error.throwWithStackTrace(e, stack!);
    return result;
  }

  /// [version] of [title], with its library, for the logs.
  String _at(Title title, Version version) =>
      '${title.path}/${version.fileName} of '
      '${ref.libraryEntry(title.libraryId).displayName}';

  /// The library path [path] relative to the folder of [title].
  static String _inTitle(Title title, String path) =>
      title.path.isEmpty ? path : path.substring(title.path.length + 1);
}

final versionActionsProvider = Provider<VersionActions>(VersionActions.new);

/// Backups of the version of [Version.fileName] in the title of [NodeId],
/// read in the `.history/` of its own folder only, newest first (SPEC
/// §5.4); empty for a version without folder (free tree) or not adopted.
final historyProvider = FutureProvider.autoDispose
    .family<List<Backup>, (NodeId, String)>((ref, key) async {
      final (id, fileName) = key;
      final title = ref
          .watch(titlesProvider)
          .where((t) => t.id == id)
          .firstOrNull;
      final version = title?.versions
          .where((v) => v.fileName == fileName)
          .firstOrNull;
      final folder = version?.folder;
      final versionId = version?.metadata?.id;
      if (title == null || folder == null || versionId == null) {
        return const [];
      }
      final root = ref.watch(
        settingsProvider.select((s) => s.library(title.libraryId)?.libraryRoot),
      );
      if (root == null) return const [];
      final dir = joinPath(title.path, folder);
      final history = await Isolate.run(
        () => readHistory(MountedFolderStorage(root), dir),
      );
      return history[versionId] ?? const [];
    });

/// Entries in the trash of a title: version folders and assets (SPEC
/// §5.4).
final trashProvider = FutureProvider.autoDispose
    .family<List<StorageEntry>, NodeId>((ref, id) async {
      final title = ref
          .watch(titlesProvider)
          .where((t) => t.id == id)
          .firstOrNull;
      if (title == null) return const [];
      final root = ref.watch(
        settingsProvider.select((s) => s.library(title.libraryId)?.libraryRoot),
      );
      if (root == null) return const [];
      final dir = title.path;
      return Isolate.run(() => readTrash(MountedFolderStorage(root), dir));
    });

/// Project templates offered for a new version in library [id]: those of
/// its own templates folder, else of the configured one (SPEC §5.1).
final projectTemplatesProvider = FutureProvider.autoDispose
    .family<List<String>, LibraryId>((ref, id) async {
      final own = ref.watch(
        settingsProvider.select((s) => s.library(id)?.templatesFolder),
      );
      final folder = own ?? ref.watch(templatesFolderProvider);
      return folder == null ? const [] : listProjectTemplates(folder);
    });
