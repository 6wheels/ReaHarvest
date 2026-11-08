import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'adoption.dart';
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
/// from the project [template] (SPEC §5.4): [metadata] written in its
/// EXTSTATE, record path `Media` and render folder `Renders`. Throws
/// [ArgumentError] on an invalid name, [StateError] if the file exists.
Future<String> createVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
  VersionMetadata metadata, {
  String? template,
}) async {
  final path = await _newVersionPath(storage, titleDir, fileName);
  var text = template ?? blankProject;
  final record = RppProject.parse(text).document.root.line('RECORD_PATH');
  text = setRootAttribute(text, 'RECORD_PATH', [
    mediaFolderName,
    record?.params.elementAtOrNull(1) ?? '',
  ]);
  text = setRootAttribute(text, 'RENDER_FILE', [rendersFolderName]);
  text = setExtState(text, VersionMetadata.section, metadata.toExtState());
  await _writeText(storage, path, text);
  return path;
}

/// Duplicates the version [source] of the title [titleDir] as [fileName]
/// (SPEC §5.4): same content, new [metadata]. Throws like [createVersion].
Future<String> duplicateVersion(
  RepositoryStorage storage,
  String titleDir,
  String source,
  String fileName,
  VersionMetadata metadata,
) async {
  final path = await _newVersionPath(storage, titleDir, fileName);
  final text = await _readText(storage, _join(titleDir, source));
  await _writeText(
    storage,
    path,
    setExtState(text, VersionMetadata.section, metadata.toExtState()),
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
  final from = _join(titleDir, fileName);
  final to = await _newVersionPath(storage, _parent(from), newName);
  await storage.move(from, to);
  return to;
}

/// Sets the label of the version [fileName] of the title [titleDir]
/// (SPEC §4.2). Throws [StateError] if the version is not adopted.
Future<void> setVersionLabel(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
  String label,
) async {
  final path = _join(titleDir, fileName);
  final metadata = VersionMetadata.fromExtState(
    RppProject.parse(await _readText(storage, path))
        .extState(VersionMetadata.section),
  );
  if (metadata == null) throw StateError('Version not adopted: $path');
  await writeVersionMetadata(
    storage,
    path,
    VersionMetadata(id: metadata.id, owner: metadata.owner, label: label),
  );
}

/// Moves the version [fileName] of the title [titleDir] to the `.trash/`
/// folder next to it (title folder; folder of the project in a free tree,
/// SPEC §3.3), suffixed on a name clash. Returns its path in the trash.
Future<String> deleteVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
) async {
  final from = _join(titleDir, fileName);
  final to = await freePath(
    storage,
    _join(_join(_parent(from), trashFolderName), p.posix.basename(from)),
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
    if (!_isUnder(titleDir, path) || !_isInTrash(path)) {
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
  final pool = _join(titleDir, mediaFolderName);
  if (await storage.stat(pool) == null) return const [];
  final referenced = <String>{};
  final absoluteNames = <String>{};
  for (final e in await storage.list(titleDir, recursive: true)) {
    if (e.isDirectory || !isProjectFile(e.path) || _isInTrash(e.path)) {
      continue;
    }
    final project = RppProject.parse(await _readText(storage, e.path));
    final dir = _parent(e.path);
    final record = project.document.root.line('RECORD_PATH')?.params;
    final dirs = {
      dir,
      for (final r in record ?? const <String>[])
        if (r.isNotEmpty && !_isAbsolute(r)) _normalize(_join(dir, _slash(r))),
    };
    for (final ref in project.mediaFiles) {
      if (_isAbsolute(ref)) {
        absoluteNames.add(_slash(ref).split('/').last.toLowerCase());
        continue;
      }
      for (final d in dirs) {
        referenced.add(_normalize(_join(d, _slash(ref))).toLowerCase());
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
  final pool = _join(titleDir, mediaFolderName);
  for (final path in paths) {
    if (!_isUnder(pool, path)) {
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
  final path = _join(dir, fileName);
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

bool _isUnder(String dir, String path) =>
    dir.isEmpty ? !path.startsWith('../') : p.posix.isWithin(dir, path);

bool _isAbsolute(String ref) {
  final slashed = _slash(ref);
  return slashed.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(slashed);
}

String _slash(String ref) => ref.replaceAll(r'\', '/');

String _normalize(String path) => p.posix.normalize(path);

Future<String> _readText(RepositoryStorage storage, String path) =>
    storage.read(path).transform(utf8.decoder).join();

Future<void> _writeText(RepositoryStorage storage, String path, String text) =>
    storage.write(path, Stream.value(utf8.encode(text)));

String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

String _parent(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
