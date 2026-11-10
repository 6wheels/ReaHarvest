import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'adoption.dart';
import 'conventions.dart';
import 'scaffold.dart';
import 'scanner.dart' show ScanResult;

/// Suffix of the proxy file REAPER keeps next to a subproject.
const _proxySuffix = '-PROX';

/// Normalizes the media of the title [titleDir] (SPEC §5.8 step 4, #69):
/// every file its projects reference outside `Media/` is brought into the
/// pool, their references are rewritten and their record path set to
/// `Media` (targeted patches).
///
/// - A file of the title is moved, once, whatever the number of projects
///   referencing it; a file outside the title (another title) is copied,
///   its original left for the projects there.
/// - A file identical to one already in the pool is not brought in: the
///   projects use the pool file, and the duplicate of the title is moved
///   into its `.trash/` (never deleted). Another name collision gets a free
///   name (`name (2).ext`).
/// - A subproject (`<SOURCE RPP_PROJECT`) brought in takes its proxy file
///   along, and its own references are rewritten from its new place.
/// - Subprojects already in the pool are normalized too, their references
///   relative to the pool; their record path is left as is.
/// - A project with a missing media, or an absolute one or outside the
///   library, is left intact and reported; the files it references are
///   copied rather than moved, so that it does not lose them. So are the
///   files referenced by the projects still in a subfolder of the title
///   (member or status subfolder, not lifted yet).
/// - The media found in the title outside its reserved folders and used by
///   no project (e.g. in a member subfolder) are merged into the pool too.
///
/// The whole title is left intact if one of its projects cannot be read
/// (its media are unknown): throws [FormatException]. So is it, reported,
/// when a project of another title references one of its files outside
/// `Media/`, which would be moved: [usage] gives the projects referencing
/// each media of the library ([mediaUsage]). Normalizing that other title
/// first copies the file into its own pool.
Future<Report> normalizeMedia(
  RepositoryStorage storage,
  String titleDir, {
  Map<String, List<String>> usage = const {},
}) => _Normalization(storage, titleDir, usage: usage).run();

/// Projects referencing each media of the library, by file path, from the
/// versions of the titles of [result] and the subprojects of their pools.
/// Projects outside the titles are not indexed, hence not listed.
Map<String, List<String>> mediaUsage(ScanResult result) {
  final usage = <String, List<String>>{};
  void add(String project, List<String> refs) {
    for (final ref in refs) {
      if (resolveReference(_parent(project), ref) case final file?) {
        usage.putIfAbsent(file, () => []).add(project);
      }
    }
  }

  for (final title in result.titles) {
    for (final v in title.versions) {
      add(_join(title.path, v.fileName), v.media);
    }
  }
  result.subprojects.forEach(add);
  return usage;
}

/// Moves the misplaced project [project] into the title folder [titleDir]
/// ("To sort", SPEC §5.2), under a free name, its relative references and
/// record path rewritten to keep pointing at the same files, then
/// normalizes the media of the title ([normalizeMedia]). The media of the
/// project are moved into the pool, or copied when another project of the
/// source folder references them too; a project with a missing or external
/// media is moved but its media are left where they are. A media also used
/// by another project of [usage] is copied too.
///
/// Throws [FormatException] if the project cannot be read (left in place).
Future<Report> moveProjectToTitle(
  RepositoryStorage storage,
  String project,
  String titleDir, {
  Map<String, List<String>> usage = const {},
}) async {
  final text = await utf8.decodeStream(storage.read(project));
  final sourceDir = _parent(project);
  final shared = {
    ...await _mediaOfOtherProjects(storage, sourceDir, project),
    for (final file in usage.keys) file.toLowerCase(),
  };
  final movable = {
    for (final ref in RppProject.parse(text).mediaFiles)
      if (resolveReference(sourceDir, ref) case final file?
          when !shared.contains(file.toLowerCase()))
        file.toLowerCase(),
  };
  String relocated(String ref) {
    final file = resolveReference(sourceDir, ref);
    if (file == null || sourceDir == titleDir) return ref;
    final relative = p.posix.relative(
      file,
      from: titleDir.isEmpty ? '.' : titleDir,
    );
    final separator = separatorOf(ref);
    return separator == '/' ? relative : relative.replaceAll('/', separator);
  }

  var patched = rewriteMediaPaths(text, relocated);
  final record = RppProject.parse(patched).document.root.line('RECORD_PATH');
  if (record != null && record.params.any((s) => s.isNotEmpty)) {
    final params = [for (final s in record.params) relocated(s)];
    if (params.join('\n') != record.params.join('\n')) {
      patched = setRootAttribute(patched, 'RECORD_PATH', params);
    }
  }
  final target = await freePath(
    storage,
    _join(titleDir, p.posix.basename(project)),
  );
  await storage.move(project, target);
  if (patched != text) {
    await storage.write(target, Stream.value(utf8.encode(patched)));
  }
  return Report({
        ReportKind.projectMoved: [ReportItem(target)],
      }) +
      await _Normalization(
        storage,
        titleDir,
        movable: movable,
        usage: usage,
      ).run();
}

/// Lowercase paths of the media referenced by the projects of [dir] other
/// than [except] (below [dir] too, unless [dir] is the library root).
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
      final text = await utf8.decodeStream(storage.read(e.path));
      for (final ref in RppProject.parse(text).mediaFiles) {
        if (resolveReference(_parent(e.path), ref) case final path?) {
          media.add(path.toLowerCase());
        }
      }
    } on FormatException {
      // Unreadable project: its media cannot be known.
    }
  }
  return media;
}

final class _Normalization {
  _Normalization(
    this.storage,
    this.titleDir, {
    this.movable = const {},
    this.usage = const {},
  }) : pool = _join(titleDir, mediaFolderName);

  final RepositoryStorage storage;
  final String titleDir;
  final String pool;

  /// Lowercase paths of files outside the title that may be moved rather
  /// than copied (media of a project moved into the title).
  final Set<String> movable;

  /// Projects referencing each media of the library ([mediaUsage]).
  final Map<String, List<String>> usage;

  /// Text of the projects of the title and of the subprojects of its pool,
  /// by path: rewritten.
  final projects = <String, String>{};

  /// Lowercase paths of the files referenced by the projects still in a
  /// subfolder of the title, or by blocked projects: never moved.
  final kept = <String>{};

  /// Files referenced by each project, keyed by their lowercase path.
  final files = <String, Map<String, String>>{};

  /// Projects left intact.
  final blocked = <String>{};

  /// New path of each file brought into the pool (or found there), by
  /// lowercase source path.
  final targets = <String, String>{};

  /// Lowercase paths of the files moved into the pool, and of those moved
  /// into the trash.
  final moved = <String>{};
  final trashed = <String>{};

  final items = <ReportKind, List<ReportItem>>{};

  Future<Report> run() async {
    // Files that would move from under the projects of another title.
    for (final MapEntry(key: file, value: projects) in usage.entries) {
      final others = projects.where((project) => !_inTitle(project)).toList();
      if (others.isNotEmpty &&
          _inTitle(file) &&
          !_inPool(file) &&
          !_relative(file).split('/').any(isExcludedFolder)) {
        _add(
          ReportKind.mediaUsedElsewhere,
          ReportItem(file, others.join('\n')),
        );
      }
    }
    if (items.isNotEmpty) return Report(items);
    final entries = await storage.list(titleDir, recursive: true);
    for (final e in entries) {
      if (e.isDirectory || !isProjectFile(e.path)) continue;
      final dir = _parent(e.path);
      final segments = _relative(e.path).split('/');
      if (segments.any(isExcludedFolder)) continue;
      final text = await utf8.decodeStream(storage.read(e.path));
      if (dir == titleDir || dir.toLowerCase() == pool.toLowerCase()) {
        projects[e.path] = text;
      } else if (!_isReserved(segments.first)) {
        // Not lifted yet: its files stay where it expects them.
        for (final ref in RppProject.parse(text).mediaFiles) {
          if (resolveReference(dir, ref) case final file?) {
            kept.add(file.toLowerCase());
          }
        }
      }
    }
    for (final MapEntry(key: project, value: text) in projects.entries) {
      await _resolve(project, text);
    }
    for (final project in blocked) {
      kept.addAll(files[project]!.keys);
    }
    for (final MapEntry(key: project, value: refs) in files.entries) {
      if (blocked.contains(project)) continue;
      for (final MapEntry(key: key, value: file) in refs.entries) {
        if (!targets.containsKey(key) && !_inPool(file)) {
          await _bring(file, keep: kept.contains(key));
        }
      }
    }
    for (final MapEntry(key: project, value: text) in projects.entries) {
      final key = project.toLowerCase();
      if (blocked.contains(project) || trashed.contains(key)) continue;
      // A subproject moved into the pool is rewritten there.
      final now = moved.contains(key) ? targets[key]! : project;
      await _rewrite(
        project,
        now,
        text,
        recordPath: now == project && _parent(project) == titleDir,
      );
    }
    // Media used by no project, e.g. left in a member subfolder.
    for (final e in entries) {
      final key = e.path.toLowerCase();
      final segments = _relative(e.path).split('/');
      if (e.isDirectory ||
          !isMediaFile(e.path) ||
          _isReserved(segments.first) ||
          segments.any(isExcludedFolder) ||
          targets.containsKey(key) ||
          kept.contains(key)) {
        continue;
      }
      await _bring(e.path, keep: false);
    }
    return Report(items);
  }

  /// Records the files referenced by [project]; blocks it if one is
  /// missing, absolute or outside the library.
  Future<void> _resolve(String project, String text) async {
    final refs = <String, String>{};
    final missing = <String>[];
    final external = <String>[];
    for (final ref in RppProject.parse(text).mediaFiles) {
      final file = resolveReference(_parent(project), ref);
      if (file == null) {
        external.add(ref);
      } else if (await storage.stat(file) case StorageEntry(
        isDirectory: false,
      )) {
        refs[file.toLowerCase()] = file;
      } else {
        missing.add(ref);
      }
    }
    files[project] = refs;
    if (missing.isEmpty && external.isEmpty) return;
    blocked.add(project);
    if (missing.isNotEmpty) {
      _add(ReportKind.missingMedia, ReportItem(project, missing.join('\n')));
    }
    if (external.isNotEmpty) {
      _add(ReportKind.externalMedia, ReportItem(project, external.join('\n')));
    }
  }

  /// Brings [file] into the pool: moved if it belongs to the title (or is
  /// [movable]) and is not [keep]t for a blocked project, copied otherwise;
  /// not brought if the pool has it already (the duplicate goes to the
  /// title's trash).
  Future<void> _bring(String file, {required bool keep}) async {
    final (target, exists) = await poolTarget(storage, pool, file);
    targets[file.toLowerCase()] = target;
    final move =
        (_inTitle(file) || movable.contains(file.toLowerCase())) && !keep;
    if (exists) {
      if (!move) return;
      final trashed = await freePath(
        storage,
        _join(_join(titleDir, trashFolderName), p.posix.basename(file)),
      );
      await storage.move(file, trashed);
      this.trashed.add(file.toLowerCase());
      _add(ReportKind.mediaTrashed, ReportItem(trashed, target));
      return;
    }
    if (move) {
      await storage.move(file, target);
      moved.add(file.toLowerCase());
      _add(ReportKind.mediaMoved, ReportItem(target, file));
    } else {
      await storage.write(target, storage.read(file));
      _add(ReportKind.mediaCopied, ReportItem(target, file));
    }
    if (!isProjectFile(file)) return;
    final proxy = '$file$_proxySuffix';
    if (await storage.stat(proxy) != null &&
        await storage.stat('$target$_proxySuffix') == null) {
      if (move) {
        await storage.move(proxy, '$target$_proxySuffix');
      } else {
        await storage.write('$target$_proxySuffix', storage.read(proxy));
      }
    }
    // References of a subproject copied, or moved from a subfolder (the
    // projects of the title are rewritten afterwards), follow it.
    if (!move || !projects.containsKey(file)) {
      final text = await utf8.decodeStream(storage.read(target));
      await _rewrite(file, target, text, recordPath: false, report: false);
    }
  }

  /// Rewrites the references of the project found at [old], now at [now],
  /// to the current place of the files: the pool for those brought in; the
  /// record path is set to `Media` if [recordPath].
  Future<void> _rewrite(
    String old,
    String now,
    String text, {
    required bool recordPath,
    bool report = true,
  }) async {
    final oldDir = _parent(old);
    final newDir = _parent(now);
    var patched = rewriteMediaPaths(text, (ref) {
      final file = resolveReference(oldDir, ref);
      if (file == null) return ref;
      final current = targets[file.toLowerCase()] ?? file;
      if (current == file && newDir == oldDir) return ref;
      final relative = p.posix.relative(
        current,
        from: newDir.isEmpty ? '.' : newDir,
      );
      final separator = separatorOf(ref);
      return separator == '/' ? relative : relative.replaceAll('/', separator);
    });
    if (recordPath) {
      final record = RppProject.parse(patched).document.root
          .line('RECORD_PATH');
      // `.\Media` is the pool too: left as written.
      final current = resolveReference(
        newDir,
        record?.params.firstOrNull ?? '',
      );
      if (current?.toLowerCase() != pool.toLowerCase()) {
        patched = setRootAttribute(patched, 'RECORD_PATH', [
          mediaFolderName,
          record?.params.elementAtOrNull(1) ?? '',
        ]);
      }
    }
    if (patched == text) return;
    await storage.write(now, Stream.value(utf8.encode(patched)));
    if (report) _add(ReportKind.mediaNormalized, ReportItem(now));
  }

  /// [path] relative to the title folder.
  String _relative(String path) =>
      titleDir.isEmpty ? path : path.substring(titleDir.length + 1);

  static bool _isReserved(String name) =>
      reservedTitleFolders.contains(name.toLowerCase());

  bool _inPool(String file) =>
      file.toLowerCase().startsWith('${pool.toLowerCase()}/');

  bool _inTitle(String file) =>
      titleDir.isEmpty ||
      file.toLowerCase().startsWith('${titleDir.toLowerCase()}/');

  void _add(ReportKind kind, ReportItem item) =>
      items.putIfAbsent(kind, () => []).add(item);
}

String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

String _parent(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
