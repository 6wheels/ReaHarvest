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

/// File name offered for a new version of the title [title] (SPEC §5.4):
/// `<title> - <label>.RPP`, followed by the name of its [owner] when it is
/// not the current member. Empty parts are left out.
String suggestedVersionName(String title, String label, {String? owner}) =>
    '${[title, label, ?owner].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' - ')}.RPP';

/// Creates the version [fileName] in the title folder [titleDir], blank or
/// from the project [template] (SPEC §5.4): the id of [metadata] written in
/// its EXTSTATE, its label and owner in the title's node file (first), record
/// path `Media` and render folder `Renders`. Throws [ArgumentError] on an
/// invalid name, [StateError] if the file exists or the title has no node
/// file.
Future<String> createVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
  VersionMetadata metadata, {
  String? template,
}) async {
  final path = await _newVersionPath(storage, titleDir, fileName);
  await writeVersionEntries(storage, titleDir, metadata);
  var text = template ?? blankProject;
  final record = RppProject.parse(text).document.root.line('RECORD_PATH');
  text = setRootAttribute(text, 'RECORD_PATH', [
    mediaFolderName,
    record?.params.elementAtOrNull(1) ?? '',
  ]);
  text = setRootAttribute(text, 'RENDER_FILE', [rendersFolderName]);
  text = setExtState(text, VersionMetadata.section, metadata.toExtState());
  await writeProject(storage, path, text, ProjectEncoding.utf8);
  return path;
}

/// Duplicates the version [source] of the title [titleDir] as [fileName]
/// (SPEC §5.4): same content, new [metadata] (id in the file, label and
/// owner in the node file). Throws like [createVersion].
Future<String> duplicateVersion(
  RepositoryStorage storage,
  String titleDir,
  String source,
  String fileName,
  VersionMetadata metadata,
) async {
  final path = await _newVersionPath(storage, titleDir, fileName);
  await writeVersionEntries(storage, titleDir, metadata);
  final (:text, :encoding) = await readProject(
    storage,
    joinPath(titleDir, source),
  );
  await writeProject(
    storage,
    path,
    setExtState(text, VersionMetadata.section, metadata.toExtState()),
    encoding,
  );
  return path;
}

/// Renames the version [fileName] of the title [titleDir] to [newName], in
/// the same folder (SPEC §5.4); its identity is kept by its EXTSTATE.
/// Throws like [createVersion].
Future<String> renameVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
  String newName,
) async {
  final from = joinPath(titleDir, fileName);
  final to = await _newVersionPath(storage, parentOf(from), newName);
  await storage.move(from, to);
  return to;
}

/// Moves the version [fileName] of the title [titleDir] to the `.trash/`
/// folder next to it (title folder; folder of the project in a free tree,
/// SPEC §3.3), suffixed on a name clash. Returns its path in the trash.
Future<String> deleteVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
) async {
  final from = joinPath(titleDir, fileName);
  final to = await freePath(
    storage,
    joinPath(joinPath(parentOf(from), trashFolderName), p.posix.basename(from)),
  );
  await storage.move(from, to);
  return to;
}

/// Files in the trash folders of the title [titleDir] (versions and assets).
Future<List<StorageEntry>> readTrash(
  RepositoryStorage storage,
  String titleDir,
) async => [
  for (final e in await storage.list(titleDir, recursive: true))
    if (!e.isDirectory && _isInTrash(e.path)) e,
];

/// Permanently deletes the trash files [paths] of the title [titleDir]
/// (UI: purge, SPEC §5.4). Throws [ArgumentError] for a path outside its
/// trash folders.
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

/// Files of the title's `Media/` referenced by none of its projects:
/// versions and backups, trash excluded (SPEC §5.4). Paths are resolved
/// from the project folder and from its record path; a file whose name
/// matches an absolute reference is kept. Throws [FormatException] if a
/// project cannot be read, so that nothing is purged blindly.
Future<List<StorageEntry>> unreferencedMedia(
  RepositoryStorage storage,
  String titleDir,
) async {
  final pool = joinPath(titleDir, mediaFolderName);
  if (await storage.stat(pool) == null) return const [];
  final referenced = <String>{};
  final absoluteNames = <String>{};
  for (final e in await storage.list(titleDir, recursive: true)) {
    if (e.isDirectory || !isProjectFile(e.path) || _isInTrash(e.path)) {
      continue;
    }
    final project = RppProject.parse((await readProject(storage, e.path)).text);
    final dir = parentOf(e.path);
    final record = project.document.root.line('RECORD_PATH')?.params;
    final dirs = {
      dir,
      for (final r in record ?? const <String>[])
        if (r.isNotEmpty && !isAbsoluteReference(r))
          _normalize(joinPath(dir, _slash(r))),
    };
    for (final ref in project.mediaFiles) {
      if (isAbsoluteReference(ref)) {
        absoluteNames.add(_slash(ref).split('/').last.toLowerCase());
        continue;
      }
      for (final d in dirs) {
        referenced.add(_normalize(joinPath(d, _slash(ref))).toLowerCase());
      }
    }
  }
  return [
    for (final e in await storage.list(pool, recursive: true))
      if (!e.isDirectory &&
          !isExcludedFile(p.posix.basename(e.path)) &&
          !referenced.contains(e.path.toLowerCase()) &&
          !absoluteNames.contains(p.posix.basename(e.path).toLowerCase()))
        e,
  ];
}

/// Permanently deletes the media [paths] of the title's `Media/`, as listed
/// by [unreferencedMedia] (SPEC §5.4). Throws [ArgumentError] for a path
/// outside the pool.
Future<void> purgeMedia(
  RepositoryStorage storage,
  String titleDir,
  Iterable<String> paths,
) async {
  final pool = joinPath(titleDir, mediaFolderName);
  for (final path in paths) {
    if (!isWithin(path, pool, caseSensitive: true)) {
      throw ArgumentError.value(path, 'paths', 'Not in the media pool');
    }
  }
  for (final path in paths) {
    await storage.delete(path);
  }
}

/// Path of a new version [fileName] in [dir], checked.
Future<String> _newVersionPath(
  RepositoryStorage storage,
  String dir,
  String fileName,
) async {
  if (!isProjectFile(fileName) ||
      !isValidFolderName(fileName) ||
      p.posix.basenameWithoutExtension(fileName).trim().isEmpty) {
    throw ArgumentError.value(fileName, 'fileName', 'Invalid version name');
  }
  final path = joinPath(dir, fileName);
  if (await storage.stat(path) != null) {
    throw StateError('Version already exists: $path');
  }
  return path;
}

bool _isInTrash(String path) {
  final segments = path.split('/');
  return segments.length > 1 &&
      segments[segments.length - 2].toLowerCase() == trashFolderName;
}

String _slash(String ref) => ref.replaceAll(r'\', '/');

String _normalize(String path) => p.posix.normalize(path);
