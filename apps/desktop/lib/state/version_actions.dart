import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_catalog.dart';
import 'library_scans.dart';
import 'library_turns.dart';
import 'providers.dart';
import 'reaper.dart';
import 'tasks.dart';

final _log = Logger('library.versions');

/// Actions on the versions of a title: adopt, separate a duplicate, create,
/// edit, status, trash, purge, backup and restore (SPEC §4.2, §5.4, §5.9),
/// each in the turn of its library ([_turn]).
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
  }) => _turn(title, () => _adopt(title, version, label, owner: owner));

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
    await ref.scanLibrary(entry);
  }

  /// Makes the manual duplicate [version] of [title] a new version (SPEC
  /// §4.2): new id, label of the original copied (another version of the
  /// title with the same id, else [version] itself when the original is in
  /// another title), owned by the local member when the library declares
  /// it. Then rescans.
  Future<void> separateDuplicate(Title title, Version version) =>
      _turn(title, () => _separateDuplicate(title, version));

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
    await ref.scanLibrary(entry);
  }

  /// Backs up [version] of [title] into its `.history/` (UI: « Créer un
  /// point de sauvegarde », SPEC §5.4); the version is unchanged.
  Future<void> backup(Title title, Version version) =>
      _turn(title, () => _backup(title, version));

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
    ref.invalidate(historyProvider(title.id));
  }

  /// Restores [backup] into [version] of [title], after backing up its
  /// current state (SPEC §5.4). Then rescans.
  Future<void> restore(Title title, Version version, Backup backup) =>
      _turn(title, () => _restore(title, version, backup));

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
    ref.invalidate(historyProvider(title.id));
    await ref.scanLibrary(entry);
  }

  /// Creates the version [fileName] of [title] with [label], owned by the
  /// local member when the library declares it ([localOwnerProvider], SPEC
  /// §5.4): a copy of [source] when given, else from the project file
  /// [template], else blank (REAPER's default template for new
  /// projects when set). Then rescans. Returns its file name.
  Future<String> addVersion(
    Title title,
    String fileName,
    String label, {
    Version? source,
    String? template,
  }) => _turn(
    title,
    () =>
        _addVersion(title, fileName, label, source: source, template: template),
  );

  Future<String> _addVersion(
    Title title,
    String fileName,
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
    await ref.scanLibrary(entry);
    return p.posix.basename(path);
  }

  Future<String?> _defaultTemplate() async {
    final resources = ref.read(reaperResourcesProvider);
    return resources == null ? null : loadDefaultProjectTemplate(resources);
  }

  /// Sets the [label] of [version] of [title] (adopted versions only), in
  /// the title's node file, and renames its file to [fileName] (SPEC §5.4);
  /// the label is written when changed or on a rename. Then rescans.
  /// Returns its file name.
  Future<String> editVersion(
    Title title,
    Version version, {
    required String fileName,
    required String label,
  }) => _turn(
    title,
    () => _editVersion(title, version, fileName: fileName, label: label),
  );

  Future<String> _editVersion(
    Title title,
    Version version, {
    required String fileName,
    required String label,
  }) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final old = version.fileName;
    final id = version.metadata?.id;
    // Also written on a rename: a label shown from the file name fallback
    // would otherwise follow the new name (SPEC §4.2).
    final relabel =
        id != null &&
        (version.metadata!.label != label.trim() || fileName != old);
    final name = await Isolate.run(() async {
      final storage = MountedFolderStorage(root);
      if (relabel) await setVersionLabel(storage, dir, id, label.trim());
      if (fileName == old) return old;
      return p.posix.basename(await renameVersion(storage, dir, old, fileName));
    });
    _log.info(
      'Version ${_at(title, version)} edited'
      '${relabel ? ', label "${label.trim()}"' : ''}'
      '${name != old ? ', renamed to $name' : ''}',
    );
    await ref.scanLibrary(entry);
    return name;
  }

  /// Sets the [status] of [version] of [title] (null clears it), in the
  /// title's `.node.json` (SPEC §5.9). Then rescans.
  Future<void> setStatusOf(Title title, Version version, String? status) =>
      _turn(title, () => _setStatusOf(title, version, status));

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
    await ref.scanLibrary(entry);
  }

  /// Moves [version] of [title] to the trash (SPEC §5.4). Then rescans.
  Future<void> trashVersion(Title title, Version version) =>
      _turn(title, () => _trashVersion(title, version));

  Future<void> _trashVersion(Title title, Version version) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    final name = version.fileName;
    await Isolate.run(
      () => deleteVersion(MountedFolderStorage(root), dir, name),
    );
    _log.info('Version ${_at(title, version)} moved to the trash');
    ref.invalidate(trashProvider(title.id));
    await ref.scanLibrary(entry);
  }

  /// Permanently deletes the trash files [paths] of [title] (SPEC §5.4).
  /// Then returns the media of its pool used by no project any more, to
  /// offer their purge; empty in a free tree, which has no pool. Throws
  /// [FormatException] if a project cannot be read.
  Future<List<StorageEntry>> purge(Title title, List<String> paths) =>
      _turn(title, () => _purge(title, paths));

  Future<List<StorageEntry>> _purge(Title title, List<String> paths) async {
    final root = ref.libraryEntry(title.libraryId).libraryRoot;
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
  Future<void> purgeUnusedMedia(Title title, List<String> paths) =>
      _turn(title, () => _purgeUnusedMedia(title, paths));

  Future<void> _purgeUnusedMedia(Title title, List<String> paths) async {
    final entry = ref.libraryEntry(title.libraryId);
    final root = entry.libraryRoot;
    final dir = title.path;
    await Isolate.run(() => purgeMedia(MountedFolderStorage(root), dir, paths));
    _log.info('Unused media of $dir in $root purged: ${paths.join(', ')}');
    await ref.scanLibrary(entry);
  }

  /// Runs [change] of [title] in the turn of its library ([LibraryTurns]):
  /// never during a batch on the library, nor with another change of the
  /// same node file. Version actions are not shown in the tasks zone.
  Future<T> _turn<T>(Title title, Future<T> Function() change) =>
      ref.read(libraryTurnsProvider).run(title.libraryId, change);

  /// [version] of [title], with its library, for the logs.
  String _at(Title title, Version version) =>
      '${title.path}/${version.fileName} of '
      '${ref.libraryEntry(title.libraryId).displayName}';

  bool _isFreeTree(Title title) =>
      ref.read(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ?? true;
}

final versionActionsProvider = Provider<VersionActions>(VersionActions.new);

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
      final root = ref.watch(
        settingsProvider.select((s) => s.library(title.libraryId)?.libraryRoot),
      );
      if (root == null) return const {};
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
