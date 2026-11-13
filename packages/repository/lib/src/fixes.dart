import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'content_hash.dart';
import 'free_names.dart';
import 'library_path.dart';
import 'project_file.dart';
import 'conventions.dart';
import 'media.dart';
import 'migration.dart';
import 'node_file.dart';

/// A migration fix of a "To sort" issue (SPEC §5.8 step 4). Plain data,
/// sendable to an isolate.
sealed class MigrationFix {
  const MigrationFix(this.path);

  /// Library path of the folder or project to fix.
  final String path;
}

/// Moves the folder [path] to [target] (its layout position). An existing
/// [target] folder is merged with it ([mergeFolder]).
final class MoveFolder extends MigrationFix {
  const MoveFolder(super.path, this.target);

  final String target;

  @override
  String toString() => 'Move folder $path to $target';
}

/// Moves the project [path] into the title folder [titleDir], then
/// normalizes the media of the title ([moveProjectToTitle]).
final class MoveProject extends MigrationFix {
  const MoveProject(super.path, this.titleDir);

  final String titleDir;

  @override
  String toString() => 'Move project $path to $titleDir';
}

/// Moves the project [path], found in a member or status subfolder of the
/// title [titleDir], up into the title ([liftProject]).
final class LiftProject extends MigrationFix {
  const LiftProject(
    super.path,
    this.titleDir, {
    this.owner,
    this.status,
    this.statusFolder,
  });

  final String titleDir;

  /// Owner, set if the version has none; null when the library declares no
  /// members.
  final MemberId? owner;

  /// Version status to set, deduced from [statusFolder].
  final String? status;

  /// Status subfolder whose name matched no status: kept in the report.
  final String? statusFolder;

  @override
  String toString() => [
    'Lift project $path to $titleDir',
    if (status != null) 'status $status',
  ].join(', ');
}

/// Brings the media of the title [path] into its pool, references
/// rewritten and record paths set to `Media` ([normalizeMedia]).
final class NormalizeMedia extends MigrationFix {
  const NormalizeMedia(super.path);

  @override
  String toString() => 'Normalize media of $path';
}

/// Applies [fixes] through the storage of [migration] (so that no file is
/// lost), one by one, each between a `fixStart` and a `fixEnd` line of its
/// journal (`ok:false` when it throws): a failed fix is reported and the
/// others go on.
/// [usage] tells the projects referencing each media of the library
/// ([mediaUsage]): a title whose media are used by another title is not
/// normalized. Media that may be identical are compared by their [hash]
/// (by default [contentHasher]), taken from the inventory of [migration]
/// when it holds the file unchanged.
Future<Report> applyFixes(
  Migration migration,
  List<MigrationFix> fixes, {
  Map<String, List<String>> usage = const {},
  ContentHash? hash,
}) async {
  final storage = migration.storage;
  final journal = migration.journal;
  final known = migration.inventoryHash(hash ?? contentHasher(storage));
  var report = const Report();
  for (final fix in fixes) {
    final number = await journal.startFix(switch (fix) {
      MoveFolder() => 'moveFolder',
      MoveProject() => 'moveProject',
      LiftProject() => 'liftProject',
      NormalizeMedia() => 'normalizeMedia',
    }, fix.path);
    try {
      report += switch (fix) {
        MoveFolder(:final path, :final target) => switch (await storage.stat(
          target,
        )) {
          null => await _moveFolder(storage, path, target),
          StorageEntry(isDirectory: true) when _mergeable(path, target) =>
            await mergeFolder(migration, path, target),
          _ => Report({
            ReportKind.targetExists: [ReportItem(path, target)],
          }),
        },
        MoveProject(:final path, :final titleDir) => await moveProjectToTitle(
          storage,
          path,
          titleDir,
          usage: usage,
          hash: known,
        ),
        final LiftProject lift => await _lift(storage, lift),
        NormalizeMedia(:final path) => await normalizeMedia(
          storage,
          path,
          usage: usage,
          hash: known,
        ),
      };
    } on Object catch (error) {
      await journal.endFix(number, ok: false);
      report += Report({
        ReportKind.fixFailed: [ReportItem(fix.path, '$error')],
      });
      continue;
    }
    await journal.endFix(number, ok: true);
  }
  return report;
}

/// Whether the folder [path] can be merged into the existing [target]:
/// neither is inside the other, and they differ by more than the case
/// (the same folder on Windows).
bool _mergeable(String path, String target) {
  return path.toLowerCase() != target.toLowerCase() &&
      !isWithin(path, target) &&
      !isWithin(target, path);
}

Future<Report> _moveFolder(
  RepositoryStorage storage,
  String path,
  String target,
) async {
  await storage.move(path, target);
  return Report({
    ReportKind.folderMoved: [ReportItem(target)],
  });
}

/// Merges the folder [source] into the existing folder [target] (SPEC §5.8
/// step 4, #81), through the storage of [migration]: each entry is moved to
/// the same place in [target]; subfolders present on both sides are merged
/// recursively (an artist, an album, a title's `Media/`); any other name
/// collision gets a free name (`name (2).ext`) and the references of the
/// moved projects are rewritten to follow it. The projects of two titles
/// thus become versions of one title. Node files are merged: the target's
/// title status wins (the dropped one is reported), version statuses,
/// labels and owners are added (the target's win on a same id). What is left of [source] (its node files, empty folders) is
/// moved into the migration folder. Only moves and targeted rewrites: no
/// file is read except projects and node files.
Future<Report> mergeFolder(
  Migration migration,
  String source,
  String target,
) async {
  final storage = migration.storage;
  final projects = [
    for (final e in await storage.list(source, recursive: true))
      if (!e.isDirectory &&
          isProjectFile(e.path) &&
          !e.path.split('/').any(isExcludedFolder))
        e.path,
  ];
  final merge = _Merge(storage);
  await merge.into(source, target);
  for (final old in projects) {
    await merge.rewriteReferences(source, old);
  }
  final rest = await freePath(storage, '${migration.folder}/merged/$source');
  await storage.move(source, rest);
  return Report({
    ReportKind.folderMerged: [ReportItem(target, source)],
    ReportKind.fileRenamed: merge.renamed,
    ReportKind.titleStatusDropped: merge.dropped,
  });
}

/// State of one [mergeFolder]: moves made, in order, and report items.
final class _Merge {
  _Merge(this.storage);

  final RepositoryStorage storage;
  final moves = <(String, String)>[];
  final renamed = <ReportItem>[];
  final dropped = <ReportItem>[];

  /// Moves the entries of [source] into [target], recursively.
  Future<void> into(String source, String target) async {
    for (final e in await storage.list(source)) {
      final name = p.posix.basename(e.path);
      final to = '$target/$name';
      final existing = await storage.stat(to);
      if (existing == null) {
        await _move(e.path, to);
      } else if (e.isDirectory && existing.isDirectory) {
        await into(e.path, to);
      } else if (name == nodeFileName && !e.isDirectory) {
        await _mergeNodes(source, target);
      } else {
        final free = await freePath(storage, to);
        await _move(e.path, free);
        renamed.add(ReportItem(free, e.path));
      }
    }
  }

  Future<void> _move(String from, String to) async {
    await storage.move(from, to);
    moves.add((from, to));
  }

  /// Merges the node file of [source] into the one of [target]; the source
  /// file stays in place. Unreadable node files are left as they are.
  Future<void> _mergeNodes(String source, String target) async {
    final NodeFile from;
    final NodeFile into;
    try {
      from = (await readNodeFile(storage, source))!;
      into = (await readNodeFile(storage, target))!;
    } on FormatException {
      return;
    }
    if (into.status != null &&
        from.status != null &&
        from.status != into.status) {
      dropped.add(ReportItem(target, from.status));
    }
    final merged = into.mergedWith(from);
    if (jsonEncode(merged.toJson()) != jsonEncode(into.toJson())) {
      await writeNodeFile(storage, target, merged);
    }
  }

  /// Current path of [path], below the merged source, following the moves.
  String _locate(String path) {
    var current = path;
    for (final (from, to) in moves) {
      if (current == from) {
        current = to;
      } else if (current.startsWith('$from/')) {
        current = '$to${current.substring(from.length)}';
      }
    }
    return current;
  }

  /// Rewrites the references of the project found at [old], below
  /// [source], to the files of [source] that did not keep their relative
  /// position (renamed on a collision). Unreadable projects are left as
  /// they are.
  Future<void> rewriteReferences(String source, String old) async {
    final now = _locate(old);
    final oldDir = p.posix.dirname(old);
    final newDir = p.posix.dirname(now);
    final (:text, :encoding) = await readProject(storage, now);
    final String patched;
    try {
      patched = rewriteMediaPaths(text, (ref) {
        final file = resolveReference(oldDir, ref);
        if (file == null || !file.startsWith('$source/')) return ref;
        final target = _locate(file);
        if (relativeReference(newDir, target, like: '/') ==
            relativeReference(oldDir, file, like: '/')) {
          return ref;
        }
        return relativeReference(newDir, target, like: ref);
      });
    } on FormatException {
      return;
    }
    if (patched != text) {
      await writeProject(storage, now, patched, encoding);
    }
  }
}

Future<Report> _lift(RepositoryStorage storage, LiftProject fix) async {
  final moved = await liftProject(
    storage,
    fix.path,
    fix.titleDir,
    owner: fix.owner,
    status: fix.status,
  );
  return Report({
    ReportKind.projectMoved: [ReportItem(moved)],
    if (fix.statusFolder case final folder?)
      ReportKind.statusFolderUnmatched: [ReportItem(moved, folder)],
  });
}

/// Moves the project [path], found in a subfolder of the title [titleDir]
/// (member or status subfolder, SPEC §5.8), up into the title, under a
/// free name. Its relative media references and record path are rewritten
/// to keep pointing at the same files, which do not move (their pool merge
/// is another fix). A project without id gets one. The node file of the
/// title gets, for that id and only where it has none, [owner] (if set) and
/// the new file name without its extension as label (SPEC §4.2, §5.8);
/// [status], if set, becomes its version status. The node file is written
/// first: a title without one throws [StateError] before the project is
/// touched. Returns its new path.
Future<String> liftProject(
  RepositoryStorage storage,
  String path,
  String titleDir, {
  MemberId? owner,
  String? status,
}) async {
  final folder = p.posix.dirname(path);
  final sub = folder.substring(titleDir.isEmpty ? 0 : titleDir.length + 1);
  var (:text, :encoding) = await readProject(storage, path);
  text = rewriteMediaPaths(text, (ref) => _prefixed(sub, ref));
  final recordPath = RppProject.parse(text).document.root.line('RECORD_PATH');
  if (recordPath != null && recordPath.params.any((s) => s.isNotEmpty)) {
    text = setRootAttribute(text, 'RECORD_PATH', [
      for (final s in recordPath.params) s.isEmpty ? s : _prefixed(sub, s),
    ]);
  }
  var metadata = VersionMetadata.fromExtState(
    RppProject.parse(text).extState(VersionMetadata.section),
  );
  if (metadata == null) {
    metadata = VersionMetadata(id: VersionId.generate());
    text = setExtState(text, VersionMetadata.section, metadata.toExtState());
  }
  final target = await freePath(
    storage,
    titleDir.isEmpty
        ? p.posix.basename(path)
        : '$titleDir/${p.posix.basename(path)}',
  );
  final entries = VersionMetadata(
    id: metadata.id,
    label: p.posix.basenameWithoutExtension(target),
    owner: owner,
  );
  await updateNodeFile(storage, titleDir, (node) {
    final updated = node.withVersion(entries, onlyMissing: true);
    return status == null
        ? updated
        : updated.withVersionStatus(entries.id, status);
  });
  await storage.move(path, target);
  await writeProject(storage, target, text, encoding);
  return target;
}

/// [ref], relative to a project in the subfolder [sub] of its title, made
/// relative to the title; absolute references are kept.
String _prefixed(String sub, String ref) {
  if (isAbsoluteReference(ref)) return ref;
  final slashed = ref.replaceAll(r'\', '/');
  final joined = p.posix.normalize('$sub/$slashed');
  final separator = separatorOf(ref);
  return separator == '/' ? joined : joined.replaceAll('/', separator);
}
