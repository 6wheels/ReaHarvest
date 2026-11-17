import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'adoption.dart';
import 'free_names.dart';
import 'library_path.dart';
import 'project_file.dart';
import 'conventions.dart';
import 'scaffold.dart';

/// Project written when a blank version is created without a template:
/// REAPER fills in its defaults on the first save.
const blankProject = '<REAPER_PROJECT 0.1 "7.0" 0\n>\n';

/// Name offered for a new version of the title [title], for its folder and
/// its `.RPP` (SPEC §5.4): `<title> - <label>`, followed by the name of its
/// [owner] when it is not the current member. Empty parts are left out.
String suggestedVersionName(String title, String label, {String? owner}) => [
  title,
  label,
  ?owner,
].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' - ');

/// Whether [name] can name a version folder and its `.RPP` (SPEC §3.2): a
/// valid folder name, not a reserved title folder (`Assets`).
bool isValidVersionName(String name) =>
    isValidFolderName(name) &&
    name.trim().isNotEmpty &&
    !isReservedTitleFolder(name);

/// Creates the version [name] in the title folder [titleDir], blank or from
/// the project [template] (SPEC §5.4): the folder `<name>/` holding
/// `<name>.RPP`, `Media/` and `Renders/`; the id of [metadata] written in
/// the project's EXTSTATE, its label and owner in the title's node file
/// (first), record path `Media` and render folder `Renders`. Returns the
/// path of the project. Throws [ArgumentError] on an invalid name,
/// [StateError] if the folder exists or the title has no node file.
Future<String> createVersion(
  RepositoryStorage storage,
  String titleDir,
  String name,
  VersionMetadata metadata, {
  String? template,
}) async {
  final folder = await _newVersionFolder(storage, titleDir, name);
  await writeVersionEntries(storage, titleDir, metadata);
  var text = template ?? blankProject;
  final record = RppProject.parse(text).document.root.line('RECORD_PATH');
  text = setRootAttribute(text, 'RECORD_PATH', [
    mediaFolderName,
    record?.params.elementAtOrNull(1) ?? '',
  ]);
  text = setRootAttribute(text, 'RENDER_FILE', [rendersFolderName]);
  text = setExtState(text, VersionMetadata.section, metadata.toExtState());
  final path = joinPath(folder, '$name.RPP');
  await writeProject(storage, path, text, ProjectEncoding.utf8);
  await _createVersionFolders(storage, folder);
  return path;
}

/// Duplicates the version [source] of the title [titleDir] as the version
/// [name] (SPEC §5.4): a new version folder with the project, under the new
/// name and with the id of [metadata] (label and owner in the node file),
/// and a copy of `Media/` keeping the dates of its files; `Renders/` is
/// created empty, `.history/` is not copied. Throws like [createVersion].
Future<String> duplicateVersion(
  RepositoryStorage storage,
  String titleDir,
  Version source,
  String name,
  VersionMetadata metadata,
) async {
  final from = joinPath(titleDir, _folderOf(source));
  final folder = await _newVersionFolder(storage, titleDir, name);
  await writeVersionEntries(storage, titleDir, metadata);
  final (:text, :encoding) = await readProject(
    storage,
    joinPath(titleDir, source.fileName),
  );
  final path = joinPath(folder, '$name${p.posix.extension(source.fileName)}');
  await writeProject(
    storage,
    path,
    setExtState(text, VersionMetadata.section, metadata.toExtState()),
    encoding,
  );
  final media = joinPath(from, mediaFolderName);
  if (await storage.stat(media) case final e? when e.isDirectory) {
    for (final e in await storage.list(media, recursive: true)) {
      if (e.isDirectory) continue;
      final copy = joinPath(folder, e.path.substring(from.length + 1));
      await storage.write(copy, storage.read(e.path));
      await storage.setModified(copy, e.modified);
    }
  }
  await _createVersionFolders(storage, folder);
  return path;
}

/// Renames the version [version] of the title [titleDir] to [name]: its
/// folder and its `.RPP` together (SPEC §5.4); its identity is kept by its
/// EXTSTATE. Returns the new path of the project. Throws like
/// [createVersion].
Future<String> renameVersion(
  RepositoryStorage storage,
  String titleDir,
  Version version,
  String name,
) async {
  final current = _folderOf(version);
  var folder = joinPath(titleDir, current);
  if (name != current) {
    final target = await _newVersionFolder(storage, titleDir, name);
    await storage.move(folder, target);
    folder = target;
  }
  final file = p.posix.basename(version.fileName);
  final renamed = '$name${p.posix.extension(file)}';
  if (renamed != file) {
    await storage.move(joinPath(folder, file), joinPath(folder, renamed));
  }
  return joinPath(folder, renamed);
}

/// Moves the version [version] of the title [titleDir] to the title's
/// `.trash/`: its whole folder; in a free tree, its `.RPP` alone, into a
/// `.trash/` next to it (SPEC §3.3). Suffixed on a name clash. Returns its
/// path in the trash.
Future<String> deleteVersion(
  RepositoryStorage storage,
  String titleDir,
  Version version,
) async {
  final folder = version.folder;
  final from = joinPath(titleDir, folder ?? version.fileName);
  final to = await freePath(
    storage,
    joinPath(joinPath(parentOf(from), trashFolderName), p.posix.basename(from)),
    folder: folder != null,
  );
  await storage.move(from, to);
  return to;
}

/// Moves every version folder of the title [titleDir] but the one of [keep]
/// to its `.trash/` (UI: « Garder uniquement cette version », SPEC §5.4),
/// suffixed on a name clash. Returns their paths in the trash.
Future<List<String>> keepOnlyVersion(
  RepositoryStorage storage,
  String titleDir,
  Version keep,
) async {
  final kept = joinPath(titleDir, _folderOf(keep));
  final trashed = <String>[];
  for (final e in await storage.list(titleDir)) {
    if (!e.isDirectory ||
        e.path == kept ||
        isReservedTitleFolder(p.posix.basename(e.path)) ||
        !(await storage.list(e.path)).any((f) => isProjectFile(f.path))) {
      continue;
    }
    final to = await freePath(
      storage,
      joinPath(joinPath(titleDir, trashFolderName), p.posix.basename(e.path)),
      folder: true,
    );
    await storage.move(e.path, to);
    trashed.add(to);
  }
  return trashed;
}

/// Entries directly in the trash folders of the title [titleDir]: version
/// folders, projects of a free tree and assets. A folder has the size of
/// the files below it.
Future<List<StorageEntry>> readTrash(
  RepositoryStorage storage,
  String titleDir,
) async {
  final entries = <String, StorageEntry>{};
  final sizes = <String, int>{};
  for (final e in await storage.list(titleDir, recursive: true)) {
    final segments = e.path.split('/');
    final i = segments.indexWhere((s) => s.toLowerCase() == trashFolderName);
    if (i < 0 || i == segments.length - 1) continue;
    final entry = segments.take(i + 2).join('/');
    if (entry == e.path) entries[entry] = e;
    if (!e.isDirectory) sizes[entry] = (sizes[entry] ?? 0) + e.size;
  }
  return [
    for (final e in entries.values)
      StorageEntry(
        path: e.path,
        isDirectory: e.isDirectory,
        size: sizes[e.path] ?? 0,
        modified: e.modified,
      ),
  ];
}

/// Permanently deletes the trash entries [paths] of the title [titleDir],
/// folders with everything below them (UI: purge, SPEC §5.4). Throws
/// [ArgumentError] for a path that is not directly in one of its trash
/// folders.
Future<void> purgeTrash(
  RepositoryStorage storage,
  String titleDir,
  Iterable<String> paths,
) async {
  for (final path in paths) {
    if (!isWithin(path, titleDir, caseSensitive: true) || !_isInTrash(path)) {
      throw ArgumentError.value(path, 'paths', 'Not in the trash');
    }
  }
  for (final path in paths) {
    await storage.delete(path);
  }
}

/// Path of a new version folder [name] in [titleDir], checked.
Future<String> _newVersionFolder(
  RepositoryStorage storage,
  String titleDir,
  String name,
) async {
  if (!isValidVersionName(name)) {
    throw ArgumentError.value(name, 'name', 'Invalid version name');
  }
  final folder = joinPath(titleDir, name);
  if (await storage.stat(folder) != null) {
    throw StateError('Version already exists: $folder');
  }
  return folder;
}

Future<void> _createVersionFolders(
  RepositoryStorage storage,
  String folder,
) async {
  for (final name in versionFolders) {
    await storage.createDirectory(joinPath(folder, name));
  }
}

/// Folder of [version]; throws [ArgumentError] in a free tree, which has
/// no version folders.
String _folderOf(Version version) =>
    version.folder ??
    (throw ArgumentError.value(version.fileName, 'version', 'No folder'));

bool _isInTrash(String path) {
  final segments = path.split('/');
  return segments.length > 1 &&
      segments[segments.length - 2].toLowerCase() == trashFolderName;
}
