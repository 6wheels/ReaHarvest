import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

/// Library paths are `/`-separated, relative to the library root (`''` for
/// the root). Media references are the paths written inside project files,
/// with the separator of the system that wrote them.

/// [name] in the folder [dir].
String joinPath(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

/// Folder containing [path]; `''` for the root.
String parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// Whether [path] is strictly inside the folder [dir] (any depth). The root
/// (`''`) contains everything except paths leading outside the library.
bool isWithin(String path, String dir, {bool caseSensitive = false}) {
  if (dir.isEmpty) return !path.startsWith('../');
  if (caseSensitive) return path.startsWith('$dir/');
  return path.toLowerCase().startsWith('${dir.toLowerCase()}/');
}

/// Whether [ref] is absolute: rooted (`/`, `\`) or with a drive letter.
bool isAbsoluteReference(String ref) {
  final slashed = ref.replaceAll(r'\', '/');
  return slashed.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(slashed);
}

/// Path separator of [ref]; the platform one if it has none (REAPER writes
/// `\` on Windows).
String separatorOf(String ref) {
  if (ref.contains(r'\')) return r'\';
  if (ref.contains('/')) return '/';
  return Platform.isWindows ? r'\' : '/';
}

/// Library path of the media [ref] of a project in [dir]; null if absolute
/// or outside the library.
String? resolveReference(String dir, String ref) {
  if (isAbsoluteReference(ref)) return null;
  final slashed = ref.replaceAll(r'\', '/');
  final path = p.posix.normalize(joinPath(dir, slashed));
  if (path == '..' || path.startsWith('../') || path == '.') return null;
  return path;
}

/// Path of the library file [file] relative to the folder [fromDir], written
/// with the separator of the reference [like] (the one it replaces).
String relativeReference(String fromDir, String file, {required String like}) {
  final relative = p.posix.relative(
    file,
    from: fromDir.isEmpty ? '.' : fromDir,
  );
  final separator = separatorOf(like);
  return separator == '/' ? relative : relative.replaceAll('/', separator);
}
