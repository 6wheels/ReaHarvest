import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'adoption.dart';
import 'conventions.dart';
import 'scaffold.dart';

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
/// - A project with a missing media, or an absolute one or outside the
///   library, is left intact and reported; the files it references are
///   copied rather than moved, so that it does not lose them.
///
/// The whole title is left intact if one of its projects cannot be read
/// (its media are unknown): throws [FormatException].
Future<Report> normalizeMedia(RepositoryStorage storage, String titleDir) =>
    _Normalization(storage, titleDir).run();

final class _Normalization {
  _Normalization(this.storage, this.titleDir)
    : pool = _join(titleDir, mediaFolderName);

  final RepositoryStorage storage;
  final String titleDir;
  final String pool;

  /// Text of the projects of the title, by path.
  final projects = <String, String>{};

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
    for (final e in await storage.list(titleDir)) {
      if (!e.isDirectory && isProjectFile(e.path)) {
        projects[e.path] = await utf8.decodeStream(storage.read(e.path));
      }
    }
    for (final MapEntry(key: project, value: text) in projects.entries) {
      await _resolve(project, text);
    }
    final kept = {for (final project in blocked) ...files[project]!.keys};
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
      await _rewrite(project, now, text, recordPath: now == project);
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
      final file = resolveReference(titleDir, ref);
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

  /// Brings [file] into the pool: moved if it belongs to the title and is
  /// not [keep]t for a blocked project, copied otherwise; not brought if
  /// the pool has it already (the title's duplicate goes to the trash).
  Future<void> _bring(String file, {required bool keep}) async {
    final (target, exists) = await poolTarget(storage, pool, file);
    targets[file.toLowerCase()] = target;
    final move = _inTitle(file) && !keep;
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
      if (record?.params.firstOrNull != mediaFolderName) {
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
