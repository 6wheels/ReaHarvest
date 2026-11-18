import 'dart:async';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'conventions.dart';
import 'fixes.dart';
import 'library_path.dart';
import 'media_plan.dart';
import 'mounted_folder_storage.dart';
import 'node_file.dart';
import 'plugin_names.dart';
import 'project_file.dart';
import 'scaffold.dart';
import 'scanner.dart' show ScanResult;

/// Projects referencing each media of the library, by file path, from the
/// versions of the titles and of the title candidates of [result]. Projects
/// outside them are not indexed, hence not listed.
Map<String, List<String>> mediaUsage(ScanResult result) {
  final usage = <String, Set<String>>{};
  void add(String project, List<String> refs) {
    for (final ref in refs) {
      if (resolveReference(parentOf(project), ref) case final file?) {
        usage.putIfAbsent(file, () => {}).add(project);
      }
    }
  }

  for (final title in result.titles) {
    for (final v in title.versions) {
      add(joinPath(title.path, v.fileName), v.media);
    }
  }
  for (final candidate in result.candidates) {
    for (final v in candidate.versions) {
      add(joinPath(candidate.root, v.fileName), v.media);
    }
  }
  return {
    for (final MapEntry(:key, :value) in usage.entries) key: [...value],
  };
}

/// Gathers the facts of [fix] for [planFix], by reads only: the listing of
/// its folder (the candidate root, or the folder of the project moved;
/// recursive unless it is the library root or a candidate placed above the
/// title level); the facts of its projects and of the subprojects they
/// reference, each read once, one at a time, its text not kept (gathering
/// stops at the first unreadable or missing one, recorded); the entries of
/// the files they reference and of the proxy files of the subprojects; the
/// target folder and the names it holds.
Future<FixFacts> gatherFix(RepositoryStorage storage, MigrationFix fix) async {
  final root = fix is MoveProject ? parentOf(fix.path) : fix.path;
  final shallow = fix is OrganizeTitle && !fix.titleFolder;
  final entries = await storage.list(
    root,
    recursive: root.isNotEmpty && !shallow,
  );
  // Names a plugin state may hold: the media of the folder.
  final mediaNames = {
    for (final e in entries)
      if (!e.isDirectory && isMediaFile(e.path)) p.posix.basename(e.path),
  };
  final projects = <String, ProjectFacts>{};
  final unreadable = <String, String>{};
  final files = <String, StorageEntry>{};
  final target = await storage.stat(fix.target);
  final targetNames = {
    if (target != null && target.isDirectory)
      for (final e in await storage.list(fix.target))
        p.posix.basename(e.path).toLowerCase(),
  };
  FixFacts facts() => FixFacts(
    entries: entries,
    projects: projects,
    unreadable: unreadable,
    files: files,
    target: target,
    targetNames: targetNames,
  );

  Future<bool> gather(String path) async {
    try {
      projects[path] = await _readFacts(storage, path, mediaNames);
      return true;
    } on FormatException catch (error) {
      unreadable[path] = error.message;
      return false;
    }
  }

  for (final v in fix.versions) {
    if (!await gather(v.source)) return facts();
  }
  for (final v in fix.versions) {
    for (final ref in projects[v.source]!.references) {
      final file = resolveReference(parentOf(v.source), ref);
      if (file == null || files.containsKey(file)) continue;
      final found = await storage.stat(file);
      if (found == null) continue;
      files[file] = found;
      if (found.isDirectory || !isProjectFile(file)) continue;
      final proxy = '$file$proxySuffix';
      if (await storage.stat(proxy) case final entry?) files[proxy] = entry;
      if (!projects.containsKey(file) && !await gather(file)) return facts();
    }
  }
  return facts();
}

/// Facts of the project [path], with which of [names] it names outside its
/// `FILE` lines. Throws [FormatException] if it is missing or cannot be
/// read.
Future<ProjectFacts> _readFacts(
  RepositoryStorage storage,
  String path,
  Iterable<String> names,
) async {
  if (await storage.stat(path) == null) {
    throw FormatException('Project not found: $path');
  }
  final (:text, encoding: _) = await readProject(storage, path);
  final project = RppProject.parse(text);
  return ProjectFacts(
    project.mediaFiles,
    recordPath: project.document.root.line('RECORD_PATH')?.params,
    namedFiles: namedOutsideSources(text, names),
    versionId: VersionMetadata.fromExtState(
      project.extState(VersionMetadata.section),
    )?.id,
  );
}

/// Applies the operations of [plan] in order through [storage] (the
/// guarded storage of a migration, which journals each change before it
/// is made): each project is read, patched and written one at a time.
/// Returns the report: what [plan] leaves intact or reports, then what was
/// done. Stops at the first error, which it throws: the changes made so
/// far stay (their undo is the migration's).
Future<Report> applyPlan(RepositoryStorage storage, MediaPlan plan) async {
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
            add(ReportKind.projectMoved, ReportItem(to, from));
          case FileRole.folder:
            add(ReportKind.folderMoved, ReportItem(to, from));
          case FileRole.proxy:
            break;
        }
      case CopyFile(:final from, :final to, :final role):
        await copyKeepingProjectDate(storage, from, to);
        if (role == FileRole.media) {
          add(ReportKind.mediaCopied, ReportItem(to, from));
        }
      case CreateFolder(:final path):
        await storage.createDirectory(path);
      case CreateTitle(:final dir, :final level):
        await scaffoldTitle(storage, dir, level);
      case SetVersionEntries(:final titleDir, :final id, :final status):
        await updateNodeFile(storage, titleDir, (node) {
          final updated = node.withVersion(
            VersionMetadata(id: id, label: op.label, owner: op.owner),
          );
          return status == null
              ? updated
              : updated.withVersionStatus(id, status);
        });
      case RewriteProject(:final path, :final reported):
        if (await _rewrite(storage, op) && reported) {
          add(ReportKind.mediaNormalized, ReportItem(path));
        }
    }
  }
  return plan.blocked + Report(items);
}

/// Makes [op]; returns whether the project changed.
Future<bool> _rewrite(RepositoryStorage storage, RewriteProject op) async {
  final (:text, :encoding) = await readProject(storage, op.path);
  var patched = rewriteMediaPaths(text, (ref) => op.references[ref] ?? ref);
  if (op.recordPath case final record?) {
    patched = setRootAttribute(patched, 'RECORD_PATH', record);
  }
  if (op.versionId case final id?) {
    patched = setExtState(
      patched,
      VersionMetadata.section,
      VersionMetadata(id: id).toExtState(),
    );
  }
  if (patched == text) return false;
  await writeProject(storage, op.path, patched, encoding);
  return true;
}

/// Plans of fixes being computed ([planFixesOn]): the [plans], by path of
/// fix, and [cancel], which stops the computation: [plans] fails at once
/// with [PreviewCancelled], and the future [cancel] returns completes once
/// the isolate has closed its files and ended.
typedef PlanPreview = ({
  Future<Map<String, MediaPlan>> plans,
  Future<void> Function() cancel,
});

/// Thrown by the [PlanPreview.plans] of a cancelled preview.
final class PreviewCancelled implements Exception {
  const PreviewCancelled();
}

/// Plans of the [fixes] of the library folder [root] (dry run, SPEC §5.8
/// step 4), by path of fix ([gatherFix], [planFix]), computed in one
/// isolate (nothing is written). A fix that cannot be gathered gets a plan
/// with no operation and its error as [ReportKind.fixFailed].
///
/// The isolate is not killed on [PlanPreview.cancel] (on Windows, the
/// files it reads would stay open): it stops reading at the next chunk,
/// closing its files.
PlanPreview planFixesOn(
  String root,
  List<MigrationFix> fixes, {
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
    (port.sendPort, root, fixes, usage),
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

/// Entry point of the isolate of [planFixesOn].
Future<void> _preview(
  (SendPort, String, List<MigrationFix>, Map<String, List<String>>) args,
) async {
  final (port, root, fixes, usage) = args;
  final storage = _CancellableStorage(MountedFolderStorage(root));
  final control = ReceivePort();
  control.listen((_) => storage.cancelled = true);
  port.send(control.sendPort);
  try {
    port.send({
      for (final fix in fixes)
        fix.path: await _planOrError(storage, fix, usage),
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
  MigrationFix fix,
  Map<String, List<String>> usage,
) async {
  try {
    return planFix(fix, await gatherFix(storage, fix), usage: usage);
  } on PreviewCancelled {
    rethrow;
  } on Object catch (error) {
    return (
      operations: const <MediaOperation>[],
      blocked: Report({
        ReportKind.fixFailed: [ReportItem(fix.path, '$error')],
      }),
    );
  }
}
