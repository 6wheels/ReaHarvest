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
import 'project_file.dart';
import 'scaffold.dart';
import 'scanner.dart' show ScanResult;

/// Normalizes the media of the title [titleDir] (SPEC §5.8 step 4, #69):
/// gathers its facts ([gatherTitle], hashing with [hash], by default
/// [contentHasher]), plans the operations ([planNormalization], whose rules
/// it documents) and applies them ([applyPlan]). Files of [movable]
/// (lowercase paths outside the title) may be moved rather than copied.
///
/// A title whose media another title uses ([usedElsewhere]) is reported
/// before anything is read. Throws [TitleUnreadable], before any change,
/// if one of its projects cannot be read.
Future<Report> normalizeMedia(
  RepositoryStorage storage,
  String titleDir, {
  Map<String, List<String>> usage = const {},
  Set<String> movable = const {},
  ContentHash? hash,
}) async {
  final elsewhere = usedElsewhere(titleDir, usage);
  if (elsewhere.isNotEmpty) {
    return Report({ReportKind.mediaUsedElsewhere: elsewhere});
  }
  final facts = await gatherTitle(
    storage,
    titleDir,
    hash: hash ?? contentHasher(storage),
  );
  if (facts.unreadable.isNotEmpty) {
    throw TitleUnreadable(titleDir, facts.unreadable);
  }
  return applyPlan(
    storage,
    planNormalization(facts, usage: usage, movable: movable),
  );
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
  Future<void> gather(String path) async {
    read.add(path.toLowerCase());
    try {
      projects[path] = await _readFacts(storage, path);
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

/// References and record path of the project [path]. Throws
/// [FormatException] if it cannot be read.
Future<ProjectFacts> _readFacts(RepositoryStorage storage, String path) async {
  final (:text, encoding: _) = await readProject(storage, path);
  final project = RppProject.parse(text);
  return ProjectFacts(
    project.mediaFiles,
    project.document.root.line('RECORD_PATH')?.params,
  );
}

/// Applies the operations of [plan] in order through [storage] (the
/// guarded storage of a migration, which journals each change before it
/// is made): each project is read, patched and written one at a time.
/// Returns the report: what [plan] leaves intact, then what was done.
///
/// Before any change, every duplicate to trash is compared byte by byte
/// with the pool file it stands for: if one differs (a hash taken from a
/// stale inventory), throws [ContentMismatch] and changes nothing.
/// Otherwise stops at the first error, which it throws: the changes made
/// so far stay (their undo is the migration's).
Future<Report> applyPlan(RepositoryStorage storage, MediaPlan plan) async {
  for (final op in plan.operations.whereType<TrashDuplicate>()) {
    if (!await sameContent(storage, op.from, op.sameAs)) {
      throw ContentMismatch(op.from, op.sameAs);
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

/// Normalization plans of the [titles] of the library folder [root] (dry
/// run of the fix, SPEC §5.8 step 4), by title, computed in one isolate
/// (nothing is written). Hashes come from the latest inventory for the
/// files unchanged since. A title whose media another title uses is not
/// read. A title that cannot be gathered gets a plan with no operation and
/// its error as [ReportKind.fixFailed].
Future<Map<String, MediaPlan>> planNormalizationOn(
  String root,
  List<String> titles, {
  required Map<String, List<String>> usage,
}) => Isolate.run(() async {
  final storage = MountedFolderStorage(root);
  final hash = contentHasher(storage);
  final known = (await Migration.latest(storage))?.inventoryHash(hash) ?? hash;
  return {
    for (final title in titles)
      title: await _planOrError(storage, title, known, usage),
  };
});

Future<MediaPlan> _planOrError(
  RepositoryStorage storage,
  String title,
  ContentHash hash,
  Map<String, List<String>> usage,
) async {
  final elsewhere = usedElsewhere(title, usage);
  if (elsewhere.isNotEmpty) {
    return (
      operations: const <MediaOperation>[],
      blocked: Report({ReportKind.mediaUsedElsewhere: elsewhere}),
    );
  }
  try {
    final facts = await gatherTitle(storage, title, hash: hash);
    return planNormalization(facts, usage: usage);
  } on Object catch (error) {
    return (
      operations: const <MediaOperation>[],
      blocked: Report({
        ReportKind.fixFailed: [ReportItem(title, '$error')],
      }),
    );
  }
}
