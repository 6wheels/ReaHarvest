import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'content_hash.dart';
import 'conventions.dart';
import 'library_path.dart';
import 'media_plan.dart';
import 'migration.dart';
import 'mounted_folder_storage.dart';
import 'plugin_names.dart';
import 'project_file.dart';
import 'scaffold.dart';
import 'scanner.dart' show ScanResult;

/// Normalizes the media of the title [titleDir] (SPEC §5.8 step 4, #69):
/// plans it ([planTitle]) and applies the plan ([applyPlan]). Throws
/// [TitleUnreadable], before any change, if one of its projects cannot be
/// read.
Future<Report> normalizeMedia(
  RepositoryStorage storage,
  String titleDir, {
  Map<String, List<String>> usage = const {},
  Set<String> movable = const {},
  ContentHash? hash,
}) async {
  final plan = await planTitle(
    storage,
    titleDir,
    usage: usage,
    movable: movable,
    hash: hash ?? contentHasher(storage),
  );
  // Only an unreadable project fails a plan.
  if (plan.blocked.items[ReportKind.fixFailed] case [final failed, ...]) {
    throw TitleUnreadable(failed.detail ?? failed.path);
  }
  return applyPlan(storage, plan);
}

/// Plan of the normalization of the title [titleDir]: its facts gathered
/// ([gatherTitle], hashing with [hash]), then the operations planned
/// ([planNormalization], whose rules it documents; files of [movable],
/// lowercase paths outside the title, may be moved rather than copied). A
/// title whose media another title uses ([usedElsewhere]) is not read.
Future<MediaPlan> planTitle(
  RepositoryStorage storage,
  String titleDir, {
  required ContentHash hash,
  Map<String, List<String>> usage = const {},
  Set<String> movable = const {},
}) async {
  final elsewhere = usedElsewhere(titleDir, usage);
  if (elsewhere.isNotEmpty) {
    return (
      operations: const <MediaOperation>[],
      blocked: Report({ReportKind.mediaUsedElsewhere: elsewhere}),
    );
  }
  final facts = await gatherTitle(storage, titleDir, hash: hash);
  return planNormalization(facts, usage: usage, movable: movable);
}

/// Projects referencing each media of the library, by file path, from the
/// versions of the titles of [result] and the subprojects of their pools.
/// Projects outside the titles are not indexed, hence not listed.
Map<String, List<String>> mediaUsage(ScanResult result) {
  final usage = <String, List<String>>{};
  void add(String project, List<String> refs) {
    for (final ref in refs) {
      if (resolveReference(parentOf(project), ref) case final file?) {
        usage.putIfAbsent(file, () => []).add(project);
      }
    }
  }

  for (final title in result.titles) {
    for (final v in title.versions) {
      add(joinPath(title.path, v.fileName), v.media);
    }
  }
  result.subprojects.forEach(add);
  return usage;
}

/// Moves the misplaced project [project] into the title folder [titleDir]
/// ("To sort", SPEC §5.2), under a free name, its relative references and
/// record path rewritten to keep pointing at the same files ([gatherMove],
/// [planMove], [applyPlan]), then normalizes the media of the title
/// ([normalizeMedia]). The media of the project are moved into the pool,
/// or copied when another project of the source folder references them
/// too; a project with a missing or external media is moved but its media
/// are left where they are. A media also used by another project of
/// [usage] is copied too.
///
/// Throws [FormatException] if the project cannot be read (left in place).
Future<Report> moveProjectToTitle(
  RepositoryStorage storage,
  String project,
  String titleDir, {
  Map<String, List<String>> usage = const {},
  ContentHash? hash,
}) async {
  final move = planMove(
    await gatherMove(storage, project, titleDir),
    usage: usage,
  );
  final moved = await applyPlan(storage, (
    operations: move.operations,
    blocked: const Report(),
  ));
  return moved +
      await normalizeMedia(
        storage,
        titleDir,
        usage: usage,
        movable: move.movable,
        hash: hash,
      );
}

/// Gathers the facts of the guided move of [project] into [titleDir], by
/// reads only, one project at a time: its references, those of the other
/// projects of its folder (below it too, unless it is the library root;
/// unreadable ones are skipped) and the names taken in the title folder.
/// Throws [FormatException] if [project] cannot be read.
Future<MoveFacts> gatherMove(
  RepositoryStorage storage,
  String project,
  String titleDir,
) async {
  final facts = await _readFacts(storage, project);
  final dir = parentOf(project);
  final shared = <String>{};
  for (final e in await storage.list(dir, recursive: dir.isNotEmpty)) {
    final segments = e.path.split('/');
    if (e.isDirectory ||
        e.path == project ||
        !isProjectFile(segments.last) ||
        segments.any(isExcludedFolder)) {
      continue;
    }
    try {
      for (final ref in (await _readFacts(storage, e.path)).references) {
        if (resolveReference(parentOf(e.path), ref) case final path?) {
          shared.add(path.toLowerCase());
        }
      }
    } on FormatException {
      // Unreadable project: its media cannot be known.
    }
  }
  return MoveFacts(
    project: project,
    titleDir: titleDir,
    facts: facts,
    shared: shared,
    titleNames: {
      if (await storage.stat(titleDir) != null)
        for (final e in await storage.list(titleDir))
          p.posix.basename(e.path).toLowerCase(),
    },
  );
}

/// Gathers the facts of the title [titleDir] for [planNormalization], by
/// reads only: its listing; the references and record path of its
/// projects ([TitleFacts.roleOf]) and of the subprojects their versions
/// reference, each project read once, one at a time, its text not kept
/// (gathering stops at the first unreadable one, recorded); the entries of the files referenced by
/// the projects of the title folder and of its pool, and of their proxy
/// files; the [hash] of the files that may be identical: same name (give
/// or take a ` (n)` suffix) and same size as another file to bring in or
/// of the pool.
Future<TitleFacts> gatherTitle(
  RepositoryStorage storage,
  String titleDir, {
  required ContentHash hash,
}) async {
  final pool = joinPath(titleDir, mediaFolderName).toLowerCase();
  final entries = await storage.list(titleDir, recursive: true);
  final projects = <String, ProjectFacts>{};
  final unreadable = <String, String>{};
  final read = <String>{};
  // Names a plugin state may hold: the media of the title outside its
  // reserved folders and pool.
  final mediaNames = {
    for (final e in entries)
      if (!e.isDirectory &&
          isMediaFile(e.path) &&
          !_inReservedFolder(titleDir, e.path))
        p.posix.basename(e.path),
  };
  Future<void> gather(String path) async {
    read.add(path.toLowerCase());
    try {
      projects[path] = await _readFacts(storage, path, mediaNames);
    } on FormatException catch (error) {
      unreadable[path] = error.message;
    }
  }

  final files = <String, StorageEntry>{};
  final contentKeys = <String, String>{};
  TitleFacts facts() => TitleFacts(
    titleDir: titleDir,
    entries: entries,
    projects: projects,
    unreadable: unreadable,
    files: files,
    contentKeys: contentKeys,
  );

  for (final e in entries) {
    if (!e.isDirectory &&
        isProjectFile(e.path) &&
        TitleFacts.roleOf(titleDir, e.path) != null) {
      await gather(e.path);
      // The title is left intact: nothing more to read.
      if (unreadable.isNotEmpty) return facts();
    }
  }
  for (final MapEntry(key: path, value: project) in projects.entries.toList()) {
    if (TitleFacts.roleOf(titleDir, path) != ProjectRole.title) continue;
    for (final ref in project.references) {
      final file = resolveReference(parentOf(path), ref);
      if (file == null || files.containsKey(file)) continue;
      final found = await storage.stat(file);
      if (found == null) continue;
      files[file] = found;
      if (found.isDirectory || !isProjectFile(file)) continue;
      final proxy = '$file$proxySuffix';
      if (await storage.stat(proxy) case final entry?) files[proxy] = entry;
      if (!read.contains(file.toLowerCase())) {
        await gather(file);
        if (unreadable.isNotEmpty) return facts();
      }
    }
  }
  // Files to bring in and files of the pool, by lowercase path.
  final candidates = <String, StorageEntry>{
    for (final MapEntry(key: path, value: e) in files.entries)
      if (!e.isDirectory && !isWithin(path, pool)) path.toLowerCase(): e,
    for (final e in entries)
      if (!e.isDirectory &&
          (parentOf(e.path).toLowerCase() == pool ||
              (isMediaFile(e.path) && !_inReservedFolder(titleDir, e.path))))
        e.path.toLowerCase(): e,
  };
  final groups = <(String, int), List<StorageEntry>>{};
  for (final e in candidates.values) {
    groups.putIfAbsent((_rootName(e.path), e.size), () => []).add(e);
  }
  for (final group in groups.values) {
    if (group.length < 2) continue;
    for (final e in group) {
      contentKeys[e.path.toLowerCase()] = await hash(e.path);
    }
  }
  return facts();
}

/// Lowercase name of the file [path] without its ` (n)` suffixes.
String _rootName(String path) {
  final name = p.posix.basename(path).toLowerCase();
  final ext = p.posix.extension(name);
  final stem = name.substring(0, name.length - ext.length);
  return '${stem.replaceFirst(RegExp(r'( \(\d+\))+$'), '')}$ext';
}

/// Whether [path] is in a reserved folder of the title [titleDir], or in
/// backups, history or trash.
bool _inReservedFolder(String titleDir, String path) {
  final segments = relativeTo(titleDir, path).split('/');
  return isReservedTitleFolder(segments.first) ||
      segments.any(isExcludedFolder);
}

/// References and record path of the project [path], and which of
/// [names] it names outside its `FILE` lines. Throws [FormatException] if
/// it cannot be read.
Future<ProjectFacts> _readFacts(
  RepositoryStorage storage,
  String path, [
  Iterable<String> names = const [],
]) async {
  final (:text, encoding: _) = await readProject(storage, path);
  final project = RppProject.parse(text);
  return ProjectFacts(
    project.mediaFiles,
    project.document.root.line('RECORD_PATH')?.params,
    namedOutsideSources(text, names),
  );
}

/// Applies the operations of [plan] in order through [storage] (the
/// guarded storage of a migration, which journals each change before it
/// is made): each project is read, patched and written one at a time.
/// Returns the report: what [plan] leaves intact, then what was done.
///
/// Before any change, every duplicate to trash or to reuse is compared
/// byte by byte with the pool file it stands for: if one differs (a hash
/// taken from a stale inventory), throws [ContentMismatch] and changes
/// nothing.
/// Otherwise stops at the first error, which it throws: the changes made
/// so far stay (their undo is the migration's).
Future<Report> applyPlan(RepositoryStorage storage, MediaPlan plan) async {
  for (final op in plan.operations) {
    if (op
        case TrashDuplicate(:final from, :final sameAs) ||
            ReuseDuplicate(:final from, :final sameAs)) {
      if (!await sameContent(storage, from, sameAs)) {
        throw ContentMismatch(from, sameAs);
      }
    }
  }
  final items = <ReportKind, List<ReportItem>>{};
  void add(ReportKind kind, ReportItem item) =>
      items.putIfAbsent(kind, () => []).add(item);
  for (final op in plan.operations) {
    switch (op) {
      case MoveFile(:final from, :final to, :final role):
        await storage.move(from, to);
        switch (role) {
          case FileRole.media:
            add(ReportKind.mediaMoved, ReportItem(to, from));
          case FileRole.project:
            add(ReportKind.projectMoved, ReportItem(to));
          case FileRole.proxy:
            break;
        }
      case CopyFile(:final from, :final to, :final role):
        await storage.write(to, storage.read(from));
        if (role == FileRole.media) {
          add(ReportKind.mediaCopied, ReportItem(to, from));
        }
      case TrashDuplicate(:final from, :final to, :final poolFile):
        await storage.move(from, to);
        add(ReportKind.mediaTrashed, ReportItem(to, poolFile));
      case ReuseDuplicate():
        break;
      case RewriteProject(:final path, :final reported):
        if (await _rewrite(storage, op) && reported) {
          add(ReportKind.mediaNormalized, ReportItem(path));
        }
    }
  }
  return plan.blocked + Report(items);
}

/// Thrown by [applyPlan] when a file planned as a duplicate differs from
/// the pool file it stands for. Nothing was changed.
final class ContentMismatch implements Exception {
  const ContentMismatch(this.file, this.poolFile);

  final String file;
  final String poolFile;

  @override
  String toString() =>
      '$file differs from $poolFile although they looked identical: '
      'nothing was changed. Scan the library again, then retry.';
}

/// Whether the files [a] and [b] have the same content: same size, then
/// compared as they are streamed (media can be large).
Future<bool> sameContent(RepositoryStorage storage, String a, String b) async {
  final sa = await storage.stat(a);
  final sb = await storage.stat(b);
  if (sa == null || sb == null || sa.size != sb.size) return false;
  final ia = StreamIterator(storage.read(a));
  final ib = StreamIterator(storage.read(b));
  try {
    var ca = const <int>[];
    var cb = const <int>[];
    var oa = 0;
    var ob = 0;
    while (true) {
      if (oa == ca.length) {
        if (!await ia.moveNext()) return true; // Same size: b ends too.
        (ca, oa) = (ia.current, 0);
      } else if (ob == cb.length) {
        if (!await ib.moveNext()) return false;
        (cb, ob) = (ib.current, 0);
      } else {
        final n = min(ca.length - oa, cb.length - ob);
        for (var i = 0; i < n; i++) {
          if (ca[oa + i] != cb[ob + i]) return false;
        }
        oa += n;
        ob += n;
      }
    }
  } finally {
    await ia.cancel();
    await ib.cancel();
  }
}

/// Makes [op]; returns whether the project changed.
Future<bool> _rewrite(RepositoryStorage storage, RewriteProject op) async {
  final (:text, :encoding) = await readProject(storage, op.path);
  var patched = rewriteMediaPaths(text, (ref) => op.references[ref] ?? ref);
  if (op.recordPath case final record?) {
    patched = setRootAttribute(patched, 'RECORD_PATH', record);
  }
  if (patched == text) return false;
  await writeProject(storage, op.path, patched, encoding);
  return true;
}

/// Normalization plans being computed ([planNormalizationOn]): the
/// [plans], by title, and [cancel], which stops the computation: [plans]
/// fails at once with [PreviewCancelled], and the future [cancel] returns
/// completes once the isolate has closed its files and ended.
typedef PlanPreview = ({
  Future<Map<String, MediaPlan>> plans,
  Future<void> Function() cancel,
});

/// Thrown by the [PlanPreview.plans] of a cancelled preview.
final class PreviewCancelled implements Exception {
  const PreviewCancelled();
}

/// Normalization plans of the [titles] of the library folder [root] (dry
/// run of the fix, SPEC §5.8 step 4), by title ([planTitle]), computed in
/// one isolate (nothing is written). Hashes come from the latest inventory
/// for the files unchanged since. A title that cannot be gathered gets a
/// plan with no operation and its error as [ReportKind.fixFailed].
///
/// The isolate is not killed on [PlanPreview.cancel] (on Windows, the
/// files it reads would stay open): it stops reading at the next chunk,
/// closing its files.
PlanPreview planNormalizationOn(
  String root,
  List<String> titles, {
  required Map<String, List<String>> usage,
}) {
  final port = ReceivePort();
  final plans = Completer<Map<String, MediaPlan>>();
  final ended = Completer<void>();
  SendPort? control;
  var cancelled = false;
  void end() {
    port.close();
    if (!ended.isCompleted) ended.complete();
  }

  port.listen((message) {
    switch (message) {
      case final SendPort port:
        control = port;
        if (cancelled) port.send(null);
      case final Map<String, MediaPlan> result:
        if (!plans.isCompleted) plans.complete(result);
      case null:
        // The isolate ended.
        if (!plans.isCompleted) {
          // coverage:ignore-start
          // Cannot happen: the isolate sends its plans or an error first.
          plans.completeError(StateError('Preview ended without plans'));
          // coverage:ignore-end
        }
        end();
      default:
        // An uncaught error of the isolate: [error, stack].
        if (!plans.isCompleted) plans.completeError(StateError('$message'));
    }
  });
  Isolate.spawn(
    _preview,
    (port.sendPort, root, titles, usage),
    onError: port.sendPort,
    onExit: port.sendPort,
  ).catchError((Object error) {
    // coverage:ignore-start
    // The isolate could not start (out of resources).
    if (!plans.isCompleted) plans.completeError(error);
    end();
    return Isolate.current;
    // coverage:ignore-end
  });
  return (
    plans: plans.future,
    cancel: () {
      if (!cancelled) {
        cancelled = true;
        control?.send(null);
        if (!plans.isCompleted) plans.completeError(const PreviewCancelled());
      }
      return ended.future;
    },
  );
}

/// Entry point of the isolate of [planNormalizationOn].
Future<void> _preview(
  (SendPort, String, List<String>, Map<String, List<String>>) args,
) async {
  final (port, root, titles, usage) = args;
  final storage = _CancellableStorage(MountedFolderStorage(root));
  final control = ReceivePort();
  control.listen((_) => storage.cancelled = true);
  port.send(control.sendPort);
  try {
    final hash = contentHasher(storage);
    final known =
        (await Migration.latest(storage))?.inventoryHash(hash) ?? hash;
    port.send({
      for (final title in titles)
        title: await _planOrError(storage, title, known, usage),
    });
  } on PreviewCancelled {
    // Nothing more to send.
  } finally {
    control.close();
  }
}

/// Read-only access to [_inner] that throws [PreviewCancelled] once
/// [cancelled], also between two chunks of a file being read (its file is
/// then closed).
final class _CancellableStorage implements RepositoryStorage {
  _CancellableStorage(this._inner);

  final RepositoryStorage _inner;
  var cancelled = false;

  void _check() {
    if (cancelled) throw const PreviewCancelled();
  }

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) {
    _check();
    return _inner.list(dir, recursive: recursive);
  }

  @override
  Future<StorageEntry?> stat(String path) {
    _check();
    return _inner.stat(path);
  }

  @override
  Stream<List<int>> read(String path) async* {
    _check();
    await for (final chunk in _inner.read(path)) {
      _check();
      yield chunk;
    }
  }

  // coverage:ignore-start
  // Never called: the preview only reads.
  @override
  Future<void> write(String path, Stream<List<int>> content) =>
      throw UnsupportedError('Preview: no write');

  @override
  Future<void> append(String path, List<int> bytes) =>
      throw UnsupportedError('Preview: no write');

  @override
  Future<void> move(String from, String to) =>
      throw UnsupportedError('Preview: no write');

  @override
  Future<void> createDirectory(String path) =>
      throw UnsupportedError('Preview: no write');

  @override
  Future<void> delete(String path) =>
      throw UnsupportedError('Preview: no write');

  @override
  Future<void> setModified(String path, DateTime modified) =>
      throw UnsupportedError('Preview: no write');
  // coverage:ignore-end
}

Future<MediaPlan> _planOrError(
  RepositoryStorage storage,
  String title,
  ContentHash hash,
  Map<String, List<String>> usage,
) async {
  try {
    return await planTitle(storage, title, usage: usage, hash: hash);
  } on PreviewCancelled {
    rethrow;
  } on Object catch (error) {
    return (
      operations: const <MediaOperation>[],
      blocked: Report({
        ReportKind.fixFailed: [ReportItem(title, '$error')],
      }),
    );
  }
}
