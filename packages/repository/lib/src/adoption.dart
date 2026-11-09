import 'dart:convert';
import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'conventions.dart';
import 'scaffold.dart';

/// Writes [metadata] into the EXTSTATE section of the project at [path]
/// ("To adopt", Save As duplicates, SPEC §4.2): targeted patch, atomic
/// write. Throws [FormatException] if the file is not valid UTF-8.
Future<void> writeVersionMetadata(
  RepositoryStorage storage,
  String path,
  VersionMetadata metadata,
) async {
  final text = await _readText(storage, path);
  final patched = setExtState(
    text,
    VersionMetadata.section,
    metadata.toExtState(),
  );
  await storage.write(path, Stream.value(utf8.encode(patched)));
}

/// What [moveProjectToTitle] did with the media of the project.
final class MoveReport {
  const MoveReport({
    required this.project,
    this.moved = const [],
    this.copied = const [],
    this.missing = const [],
    this.external = const [],
  });

  /// New path of the project.
  final String project;

  /// Media moved into the title's `Media/` (new paths).
  final List<String> moved;

  /// Media copied into `Media/` because another project of the source folder
  /// still references them (new paths).
  final List<String> copied;

  /// References to files that do not exist (left as is).
  final List<String> missing;

  /// Absolute references or references outside the library (left as is,
  /// SPEC §4.3).
  final List<String> external;

  /// Structured report (SPEC §5.2), paths relative to the library. Missing
  /// and external media are reported on the project, with the reference as
  /// written in it.
  Report toReport() => Report({
    ReportKind.projectMoved: [ReportItem(project)],
    ReportKind.mediaMoved: [for (final m in moved) ReportItem(m)],
    ReportKind.mediaCopied: [for (final m in copied) ReportItem(m)],
    ReportKind.missingMedia: [for (final m in missing) ReportItem(project, m)],
    ReportKind.externalMedia: [
      for (final m in external) ReportItem(project, m),
    ],
  });
}

/// Moves the misplaced project [project] into the title folder [titleDir]
/// ("To sort", SPEC §5.2). Its media referenced by a relative path are
/// brought into the title's `Media/` (moved, or copied when another project
/// of the source folder references them too; identical files already in the
/// pool are reused, other name collisions get a suffix), its references are
/// rewritten and its record path set to `Media`.
Future<MoveReport> moveProjectToTitle(
  RepositoryStorage storage,
  String project,
  String titleDir,
) async {
  final text = await _readText(storage, project);
  final sourceDir = _parent(project);
  final shared = await _mediaOfOtherProjects(storage, sourceDir, project);
  final pool = _join(titleDir, mediaFolderName);
  final moved = <String>[];
  final copied = <String>[];
  final missing = <String>[];
  final external = <String>[];
  final newRefs = <String, String>{};

  for (final ref in RppProject.parse(text).mediaFiles) {
    final source = resolveReference(sourceDir, ref);
    if (source == null) {
      external.add(ref);
      continue;
    }
    if (_parent(source) == pool) continue;
    if (await storage.stat(source) == null) {
      missing.add(ref);
      continue;
    }
    final (target, exists) = await _poolTarget(storage, pool, source);
    if (!exists) {
      if (shared.contains(source)) {
        await storage.write(target, storage.read(source));
        copied.add(target);
      } else {
        await storage.move(source, target);
        moved.add(target);
      }
    }
    newRefs[ref] =
        '$mediaFolderName${separatorOf(ref)}${p.posix.basename(target)}';
  }

  var patched = rewriteMediaPaths(text, (ref) => newRefs[ref] ?? ref);
  final recordPath = RppProject.parse(patched).document.root
      .line('RECORD_PATH');
  patched = setRootAttribute(patched, 'RECORD_PATH', [
    mediaFolderName,
    recordPath?.params.elementAtOrNull(1) ?? '',
  ]);

  final destination = await freePath(
    storage,
    _join(titleDir, p.posix.basename(project)),
  );
  await storage.move(project, destination);
  await storage.write(destination, Stream.value(utf8.encode(patched)));
  return MoveReport(
    project: destination,
    moved: moved,
    copied: copied,
    missing: missing,
    external: external,
  );
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
  final slashed = ref.replaceAll(r'\', '/');
  if (slashed.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(slashed)) {
    return null;
  }
  final path = p.posix.normalize(_join(dir, slashed));
  if (path == '..' || path.startsWith('../') || path == '.') return null;
  return path;
}

/// Pool path for [source]: its name in [pool], reused when the file there is
/// identical (second value true), suffixed when another file has the name.
Future<(String, bool)> _poolTarget(
  RepositoryStorage storage,
  String pool,
  String source,
) async {
  final name = p.posix.basename(source);
  final stem = p.posix.basenameWithoutExtension(name);
  final ext = p.posix.extension(name);
  for (var i = 1; ; i++) {
    final candidate = _join(pool, i == 1 ? name : '$stem ($i)$ext');
    final existing = await storage.stat(candidate);
    if (existing == null) return (candidate, false);
    if (await _sameContent(storage, source, candidate)) {
      return (candidate, true);
    }
  }
}

/// [path], or the first free `name (n).ext` variant.
Future<String> freePath(RepositoryStorage storage, String path) async {
  final dir = _parent(path);
  final stem = p.posix.basenameWithoutExtension(path);
  final ext = p.posix.extension(path);
  for (var i = 1; ; i++) {
    final candidate = i == 1 ? path : _join(dir, '$stem ($i)$ext');
    if (await storage.stat(candidate) == null) return candidate;
  }
}

Future<bool> _sameContent(RepositoryStorage storage, String a, String b) async {
  final sa = await storage.stat(a);
  final sb = await storage.stat(b);
  if (sa == null || sb == null || sa.size != sb.size) return false;
  final ba = await _bytes(storage, a);
  final bb = await _bytes(storage, b);
  for (var i = 0; i < ba.length; i++) {
    if (ba[i] != bb[i]) return false;
  }
  return true;
}

Future<List<int>> _bytes(RepositoryStorage storage, String path) async => [
  for (final chunk in await storage.read(path).toList()) ...chunk,
];

/// Media referenced by the projects of [dir] other than [except] (below
/// [dir] too, unless [dir] is the library root).
Future<Set<String>> _mediaOfOtherProjects(
  RepositoryStorage storage,
  String dir,
  String except,
) async {
  final media = <String>{};
  for (final e in await storage.list(dir, recursive: dir.isNotEmpty)) {
    final segments = e.path.split('/');
    if (e.isDirectory ||
        e.path == except ||
        !isProjectFile(segments.last) ||
        segments.any(isExcludedFolder)) {
      continue;
    }
    try {
      final text = await _readText(storage, e.path);
      for (final ref in RppProject.parse(text).mediaFiles) {
        if (resolveReference(_parent(e.path), ref) case final path?) {
          media.add(path);
        }
      }
    } on FormatException {
      // Unreadable project: its media cannot be known.
    }
  }
  return media;
}

Future<String> _readText(RepositoryStorage storage, String path) =>
    storage.read(path).transform(utf8.decoder).join();

String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

String _parent(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
