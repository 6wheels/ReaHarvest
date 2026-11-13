import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'conventions.dart';
import 'library_path.dart';
import 'scaffold.dart';

/// Media normalization (SPEC §5.8 step 4, #69, #95), planned before it is
/// applied: reads gather the [TitleFacts] (`gatherTitle`), the pure
/// function [planNormalization] computes the operations ([MediaPlan], shown
/// as the preview), then `applyPlan` makes them through the storage.

/// Suffix of the proxy file REAPER keeps next to a subproject.
const proxySuffix = '-PROX';

/// What gathering keeps of a project: its text is not kept.
final class ProjectFacts {
  const ProjectFacts(
    this.references, [
    this.recordPath,
    this.namedFiles = const {},
  ]);

  /// Media references (`FILE` of `SOURCE` chunks), deduplicated, as
  /// written.
  final List<String> references;

  /// Parameters of its `RECORD_PATH` line; null without one.
  final List<String>? recordPath;

  /// Names, among the media of the title, that appear in the project
  /// outside its `FILE` lines (`namedOutsideSources`): plugin states.
  final Set<String> namedFiles;
}

/// Role of a project of a title in its normalization.
enum ProjectRole {
  /// In the title folder or its pool: normalized.
  title,

  /// In another subfolder of the title (member or status subfolder, not
  /// lifted yet): its files stay where it expects them.
  notLifted,
}

/// Facts about a title, gathered by reads only.
final class TitleFacts {
  const TitleFacts({
    required this.titleDir,
    this.entries = const [],
    this.projects = const {},
    this.unreadable = const {},
    this.files = const {},
    this.contentKeys = const {},
  });

  final String titleDir;

  /// Every entry of the title, listed before any change.
  final List<StorageEntry> entries;

  /// Facts of the projects of the title ([roleOf]) in listing order, then
  /// of the subprojects their versions reference, by path.
  final Map<String, ProjectFacts> projects;

  /// Projects that cannot be read, by path, with the reason.
  final Map<String, String> unreadable;

  /// Entries of the files referenced by the projects of the title folder
  /// and of its pool, and of the proxy files of the subprojects among them,
  /// by path as resolved; a path missing here does not exist.
  final Map<String, StorageEntry> files;

  /// Hash of the files that may be identical (same name, give or take a
  /// ` (n)` suffix, and same size as another file to bring or of the
  /// pool), by lowercase path.
  final Map<String, String> contentKeys;

  /// Pool of the title.
  String get pool => joinPath(titleDir, mediaFolderName);

  /// Role of the project [path] in the title [titleDir]; null for the
  /// projects outside it, in its reserved folders other than the pool, or
  /// in backups, history and trash.
  static ProjectRole? roleOf(String titleDir, String path) {
    if (titleDir.isNotEmpty && !path.startsWith('$titleDir/')) return null;
    final segments = relativeTo(titleDir, path).split('/');
    if (segments.any(isExcludedFolder)) return null;
    final dir = parentOf(path);
    final pool = joinPath(titleDir, mediaFolderName).toLowerCase();
    if (dir == titleDir || dir.toLowerCase() == pool) return ProjectRole.title;
    if (!isReservedTitleFolder(segments.first)) return ProjectRole.notLifted;
    return null;
  }
}

/// [path], inside [dir], relative to it.
String relativeTo(String dir, String path) =>
    dir.isEmpty ? path : path.substring(dir.length + 1);

/// What a moved or copied file is, for the report.
enum FileRole { media, proxy, project }

/// One operation of a [MediaPlan], applied in order.
sealed class MediaOperation {
  const MediaOperation();
}

/// Moves [from] to [to]; a renamed file has another name at [to].
final class MoveFile extends MediaOperation {
  const MoveFile(this.from, this.to, {this.role = FileRole.media});

  final String from;
  final String to;
  final FileRole role;

  @override
  String toString() => 'move $from -> $to';
}

/// Copies [from] to [to], its original left in place.
final class CopyFile extends MediaOperation {
  const CopyFile(this.from, this.to, {this.role = FileRole.media});

  final String from;
  final String to;
  final FileRole role;

  @override
  String toString() => 'copy $from -> $to';
}

/// Moves [from], identical to [poolFile], to [to] in the trash of the
/// title (never deleted). [sameAs] is where the content of [poolFile] is
/// before the plan ([poolFile] itself, or the file an earlier operation
/// brings there): both are compared byte by byte before any change.
final class TrashDuplicate extends MediaOperation {
  const TrashDuplicate(this.from, this.to, this.poolFile, {String? sameAs})
    : sameAs = sameAs ?? poolFile;

  final String from;
  final String to;
  final String poolFile;
  final String sameAs;

  @override
  String toString() => 'trash $from -> $to (same as $poolFile)';
}

/// Uses [poolFile], identical to [from], instead of bringing [from] into
/// the pool: [from] is left where it is (a file of another title, or kept
/// for a project). No change; [from] and [sameAs] (where the content of
/// [poolFile] is before the plan) are compared byte by byte before any
/// change of the plan.
final class ReuseDuplicate extends MediaOperation {
  const ReuseDuplicate(this.from, this.poolFile, {String? sameAs})
    : sameAs = sameAs ?? poolFile;

  final String from;
  final String poolFile;
  final String sameAs;

  @override
  String toString() => 'reuse $poolFile for $from';
}

/// Rewrites the project read at [path]: each media reference of
/// [references] replaced by its value and, if set, its record path
/// replaced by [recordPath] (targeted patches, SPEC §7.3). Reported as
/// normalized if [reported].
final class RewriteProject extends MediaOperation {
  const RewriteProject(
    this.path,
    this.references, {
    this.recordPath,
    this.reported = true,
  });

  final String path;
  final Map<String, String> references;
  final List<String>? recordPath;
  final bool reported;

  @override
  String toString() => [
    'rewrite $path',
    for (final MapEntry(:key, :value) in references.entries) '$key -> $value',
    if (recordPath case final record?) 'RECORD_PATH ${record.join(' ')}',
  ].join(', ');
}

/// Operations of a normalization, in order, and what is left intact with
/// its reason ([ReportKind.missingMedia], [ReportKind.externalMedia],
/// [ReportKind.mediaUsedElsewhere], [ReportKind.referencedByPlugin],
/// [ReportKind.fixFailed]).
typedef MediaPlan = ({List<MediaOperation> operations, Report blocked});

/// Counts of a [MediaPlan], for its preview.
typedef MediaPlanCounts = ({
  int moved,
  int copied,
  int trashed,
  int renamed,
  int rewritten,
  int blocked,
});

/// Counts of [plan]: media moved, copied, duplicates to the trash, media
/// renamed on a collision, projects rewritten and paths left intact.
MediaPlanCounts countPlan(MediaPlan plan) {
  var (moved, copied, trashed, renamed, rewritten) = (0, 0, 0, 0, 0);
  for (final op in plan.operations) {
    switch (op) {
      case MoveFile(role: FileRole.media, :final from, :final to):
        moved++;
        if (p.posix.basename(from) != p.posix.basename(to)) renamed++;
      case CopyFile(role: FileRole.media, :final from, :final to):
        copied++;
        if (p.posix.basename(from) != p.posix.basename(to)) renamed++;
      case TrashDuplicate():
        trashed++;
      case ReuseDuplicate():
        break;
      case RewriteProject():
        rewritten++;
      case MoveFile() || CopyFile():
        break;
    }
  }
  return (
    moved: moved,
    copied: copied,
    trashed: trashed,
    renamed: renamed,
    rewritten: rewritten,
    blocked: {
      for (final list in plan.blocked.items.values)
        for (final item in list) item.path,
    }.length,
  );
}

/// Plans the normalization of the media of the title of [facts] (SPEC §5.8
/// step 4, #69): every file its projects reference outside `Media/` is
/// brought into the pool, their references are rewritten and their record
/// path set to `Media`.
///
/// - A file of the title is moved, once, whatever the number of projects
///   referencing it; a file outside the title (another title) is copied,
///   its original left for the projects there.
/// - A file identical to one already in the pool (same size and hash) is
///   not brought in: the projects use the pool file, and the duplicate of
///   the title is moved into its `.trash/`. Another name collision gets a
///   free name (`name (2).ext`). The pool fills as the plan goes.
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
/// - A file used by no project but named by one outside its `FILE` lines
///   (a plugin state) is left where it is and reported
///   ([ReportKind.referencedByPlugin]).
/// - A record path already resolving to the pool (`.\Media`) is left as
///   written.
///
/// The whole title is left intact if one of its projects cannot be read
/// (its media are unknown), and so is it, reported, when a project of
/// another title references one of its files outside `Media/`, which would
/// be moved: [usage] gives the projects referencing each media of the
/// library (`mediaUsage`). Normalizing that other title first copies the
/// file into its own pool. Files of [movable] (lowercase paths, outside
/// the title) may be moved rather than copied.
MediaPlan planNormalization(
  TitleFacts facts, {
  Map<String, List<String>> usage = const {},
  Set<String> movable = const {},
}) => _Planner(facts, usage, movable).plan();

/// State of one [planNormalization].
final class _Planner {
  _Planner(this.facts, this.usage, this.movable)
    : titleDir = facts.titleDir,
      pool = facts.pool;

  final TitleFacts facts;
  final Map<String, List<String>> usage;
  final Set<String> movable;
  final String titleDir;
  final String pool;

  final operations = <MediaOperation>[];
  final blockedItems = <ReportKind, List<ReportItem>>{};

  /// Facts of the projects of the title folder and of its pool, by path.
  final projects = <String, ProjectFacts>{};

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

  /// Files of the pool as it fills, by lowercase name: size, content key
  /// and path of the content before the plan.
  late final poolFiles = <String, ({int size, String? key, String source})>{
    for (final e in facts.entries)
      if (!e.isDirectory &&
          parentOf(e.path).toLowerCase() == pool.toLowerCase())
        p.posix.basename(e.path).toLowerCase(): (
          size: e.size,
          key: facts.contentKeys[e.path.toLowerCase()],
          source: e.path,
        ),
  };

  /// Lowercase names taken in the trash of the title, as it fills.
  late final trashNames = <String>{
    for (final e in facts.entries)
      if (parentOf(e.path).toLowerCase() == _trash.toLowerCase())
        p.posix.basename(e.path).toLowerCase(),
  };

  /// Files of the title listing, by lowercase path.
  late final listed = {
    for (final e in facts.entries)
      if (!e.isDirectory) e.path.toLowerCase(): e,
  };

  /// Facts of every project gathered, by lowercase path.
  late final factsByKey = {
    for (final MapEntry(:key, :value) in facts.projects.entries)
      key.toLowerCase(): value,
  };

  String get _trash => joinPath(titleDir, trashFolderName);

  MediaPlan plan() {
    for (final item in usedElsewhere(titleDir, usage)) {
      _block(ReportKind.mediaUsedElsewhere, item);
    }
    if (blockedItems.isEmpty && facts.unreadable.isNotEmpty) {
      _block(
        ReportKind.fixFailed,
        ReportItem(titleDir, _unreadable(facts.unreadable)),
      );
    }
    if (blockedItems.isNotEmpty) {
      return (operations: const [], blocked: Report(blockedItems));
    }
    for (final MapEntry(key: path, value: project) in facts.projects.entries) {
      switch (TitleFacts.roleOf(titleDir, path)) {
        case ProjectRole.title:
          projects[path] = project;
        case ProjectRole.notLifted:
          // Not lifted yet: it stays, and its files stay where it expects
          // them (copied if a project of the title uses them).
          kept.add(path.toLowerCase());
          for (final ref in project.references) {
            if (resolveReference(parentOf(path), ref) case final file?) {
              kept.add(file.toLowerCase());
            }
          }
        case null:
          break;
      }
    }
    for (final MapEntry(key: path, value: project) in projects.entries) {
      _resolve(path, project);
    }
    // A blocked project is left intact, its files too; used as a
    // subproject, it is copied.
    for (final project in blocked) {
      kept
        ..add(project.toLowerCase())
        ..addAll(files[project]!.keys);
    }
    for (final MapEntry(key: project, value: refs) in files.entries) {
      if (blocked.contains(project)) continue;
      for (final MapEntry(key: key, value: file) in refs.entries) {
        if (!targets.containsKey(key) && !isWithin(file, pool)) {
          _bring(file, keep: kept.contains(key));
        }
      }
    }
    for (final MapEntry(key: path, value: project) in projects.entries) {
      final key = path.toLowerCase();
      if (blocked.contains(path) || trashed.contains(key)) continue;
      // A subproject moved into the pool is rewritten there.
      final now = moved.contains(key) ? targets[key]! : path;
      _rewrite(
        path,
        now,
        project,
        recordPath: now == path && parentOf(path) == titleDir,
      );
    }
    // Media used by no project, e.g. left in a member subfolder, unless a
    // plugin state names it.
    final named = <String, List<String>>{};
    for (final MapEntry(key: path, value: project) in facts.projects.entries) {
      for (final name in project.namedFiles) {
        named.putIfAbsent(name.toLowerCase(), () => []).add(path);
      }
    }
    for (final e in facts.entries) {
      final key = e.path.toLowerCase();
      final segments = relativeTo(titleDir, e.path).split('/');
      if (e.isDirectory ||
          !isMediaFile(e.path) ||
          isReservedTitleFolder(segments.first) ||
          segments.any(isExcludedFolder) ||
          targets.containsKey(key) ||
          kept.contains(key)) {
        continue;
      }
      if (named[p.posix.basename(e.path).toLowerCase()] case final by?) {
        _block(
          ReportKind.referencedByPlugin,
          ReportItem(e.path, by.join('\n')),
        );
        continue;
      }
      _bring(e.path, keep: false);
    }
    return (operations: operations, blocked: Report(blockedItems));
  }

  /// Records the files referenced by [project]; blocks it if one is
  /// missing, absolute or outside the library.
  void _resolve(String project, ProjectFacts read) {
    final refs = <String, String>{};
    final missing = <String>[];
    final external = <String>[];
    for (final ref in read.references) {
      final file = resolveReference(parentOf(project), ref);
      if (file == null) {
        external.add(ref);
      } else if (facts.files[file] case StorageEntry(isDirectory: false)) {
        refs[file.toLowerCase()] = file;
      } else {
        missing.add(ref);
      }
    }
    files[project] = refs;
    if (missing.isEmpty && external.isEmpty) return;
    blocked.add(project);
    if (missing.isNotEmpty) {
      _block(ReportKind.missingMedia, ReportItem(project, missing.join('\n')));
    }
    if (external.isNotEmpty) {
      _block(
        ReportKind.externalMedia,
        ReportItem(project, external.join('\n')),
      );
    }
  }

  /// Brings [file] into the pool: moved if it belongs to the title (or is
  /// [movable]) and is not [keep]t for a blocked project, copied otherwise;
  /// not brought if the pool has it already (the duplicate goes to the
  /// title's trash).
  void _bring(String file, {required bool keep}) {
    final key = file.toLowerCase();
    final (target, sameAs) = _poolTarget(file);
    targets[key] = target;
    final move = (isWithin(file, titleDir) || movable.contains(key)) && !keep;
    if (sameAs != null) {
      if (!move) {
        operations.add(ReuseDuplicate(file, target, sameAs: sameAs));
        return;
      }
      final name = _free(trashNames, p.posix.basename(file));
      operations.add(
        TrashDuplicate(file, joinPath(_trash, name), target, sameAs: sameAs),
      );
      trashed.add(key);
      return;
    }
    operations.add(move ? MoveFile(file, target) : CopyFile(file, target));
    if (move) moved.add(key);
    _occupy(target, file);
    if (!isProjectFile(file)) return;
    final proxy = '$file$proxySuffix';
    final proxyTarget = '$target$proxySuffix';
    if (facts.files[proxy] case StorageEntry(isDirectory: false)
        when !poolFiles.containsKey(
          p.posix.basename(proxyTarget).toLowerCase(),
        )) {
      operations.add(
        move
            ? MoveFile(proxy, proxyTarget, role: FileRole.proxy)
            : CopyFile(proxy, proxyTarget, role: FileRole.proxy),
      );
      _occupy(proxyTarget, proxy);
    }
    // References of a subproject copied, or moved from a subfolder (the
    // projects of the title are rewritten afterwards), follow it.
    if (!move || !projects.containsKey(file)) {
      _rewrite(
        file,
        target,
        factsByKey[key]!,
        recordPath: false,
        reported: false,
      );
    }
  }

  /// Pool path for [file]: its name, reused when the pool file is identical
  /// (second value: where its content is before the plan), suffixed when
  /// another file has the name.
  (String, String?) _poolTarget(String file) {
    final name = p.posix.basename(file);
    final stem = p.posix.basenameWithoutExtension(name);
    final ext = p.posix.extension(name);
    final size = _sizeOf(file);
    final key = facts.contentKeys[file.toLowerCase()];
    for (var i = 1; ; i++) {
      final candidate = i == 1 ? name : '$stem ($i)$ext';
      final existing = poolFiles[candidate.toLowerCase()];
      if (existing == null) return (joinPath(pool, candidate), null);
      if (key != null && existing.key == key && existing.size == size) {
        return (joinPath(pool, candidate), existing.source);
      }
    }
  }

  /// Records the pool file [target], a copy of [source].
  void _occupy(String target, String source) =>
      poolFiles[p.posix.basename(target).toLowerCase()] = (
        size: _sizeOf(source)!,
        key: facts.contentKeys[source.toLowerCase()],
        source: source,
      );

  int? _sizeOf(String path) =>
      facts.files[path]?.size ?? listed[path.toLowerCase()]?.size;

  /// [name], or its first `name (n).ext` variant not in [taken] (lowercase
  /// names), which it joins.
  static String _free(Set<String> taken, String name) {
    final stem = p.posix.basenameWithoutExtension(name);
    final ext = p.posix.extension(name);
    for (var i = 1; ; i++) {
      final candidate = i == 1 ? name : '$stem ($i)$ext';
      if (taken.add(candidate.toLowerCase())) return candidate;
    }
  }

  /// Plans the rewrite of the project found at [old], now at [now], to the
  /// current place of the files: the pool for those brought in; the record
  /// path is set to `Media` if [recordPath], unless it is the pool already.
  void _rewrite(
    String old,
    String now,
    ProjectFacts project, {
    required bool recordPath,
    bool reported = true,
  }) {
    final oldDir = parentOf(old);
    final newDir = parentOf(now);
    final references = <String, String>{};
    for (final ref in project.references) {
      final file = resolveReference(oldDir, ref);
      if (file == null) continue;
      final current = targets[file.toLowerCase()] ?? file;
      if (current == file && newDir == oldDir) continue;
      final rewritten = relativeReference(newDir, current, like: ref);
      if (rewritten != ref) references[ref] = rewritten;
    }
    List<String>? record;
    if (recordPath) {
      final params = project.recordPath ?? const <String>[];
      // `.\Media` is the pool too: left as written.
      final current = resolveReference(newDir, params.firstOrNull ?? '');
      if (current?.toLowerCase() != pool.toLowerCase()) {
        record = [mediaFolderName, params.elementAtOrNull(1) ?? ''];
      }
    }
    if (references.isEmpty && record == null) return;
    operations.add(
      RewriteProject(now, references, recordPath: record, reported: reported),
    );
  }

  void _block(ReportKind kind, ReportItem item) =>
      blockedItems.putIfAbsent(kind, () => []).add(item);
}

/// A project of the title [titleDir] cannot be read: its media are
/// unknown, so nothing can be changed in the title.
final class TitleUnreadable implements Exception {
  const TitleUnreadable(this.message);

  /// The projects that cannot be read, with the reason.
  final String message;

  @override
  String toString() => message;
}

/// Message of a title whose [projects] (by path, with the reason) cannot
/// be read.
String _unreadable(Map<String, String> projects) => [
  'Project unreadable, nothing can be changed in this title:',
  for (final MapEntry(:key, :value) in projects.entries) '$key ($value)',
].join(' ');

/// Files of the title [titleDir] outside its pool that projects of other
/// titles reference, by [usage] (`mediaUsage`), each with those projects:
/// normalizing the title would move them from under these projects.
List<ReportItem> usedElsewhere(
  String titleDir,
  Map<String, List<String>> usage,
) {
  final pool = joinPath(titleDir, mediaFolderName);
  final items = <ReportItem>[];
  for (final MapEntry(key: file, value: projects) in usage.entries) {
    final others = projects
        .where((project) => !isWithin(project, titleDir))
        .toList();
    if (others.isNotEmpty &&
        isWithin(file, titleDir) &&
        !isWithin(file, pool) &&
        !relativeTo(titleDir, file).split('/').any(isExcludedFolder)) {
      items.add(ReportItem(file, others.join('\n')));
    }
  }
  return items;
}

/// Facts of a guided move ("To sort", SPEC §5.2), gathered by reads only.
final class MoveFacts {
  const MoveFacts({
    required this.project,
    required this.titleDir,
    required this.facts,
    this.shared = const {},
    this.titleNames = const {},
  });

  /// The project to move, and its facts.
  final String project;
  final ProjectFacts facts;

  /// The title folder it goes to.
  final String titleDir;

  /// Lowercase paths of the files the other projects of its folder
  /// reference.
  final Set<String> shared;

  /// Lowercase names of the entries of the title folder.
  final Set<String> titleNames;
}

/// Plans the guided move of the project of [facts] into its title folder
/// (rule 13 of #69): under a free name, its relative references and its
/// record path rewritten to keep pointing at the same files. Returns the
/// operations and the files the normalization of the title that follows
/// may move ([planNormalization]): its media used by no other project of
/// its folder ([MoveFacts.shared]) nor of [usage].
({List<MediaOperation> operations, Set<String> movable}) planMove(
  MoveFacts facts, {
  Map<String, List<String>> usage = const {},
}) {
  final MoveFacts(:project, :titleDir) = facts;
  final sourceDir = parentOf(project);
  final shared = {
    ...facts.shared,
    for (final file in usage.keys) file.toLowerCase(),
  };
  final movable = {
    for (final ref in facts.facts.references)
      if (resolveReference(sourceDir, ref) case final file?
          when !shared.contains(file.toLowerCase()))
        file.toLowerCase(),
  };
  String relocated(String ref) {
    final file = resolveReference(sourceDir, ref);
    if (file == null || sourceDir == titleDir) return ref;
    return relativeReference(titleDir, file, like: ref);
  }

  final references = {
    for (final ref in facts.facts.references)
      if (relocated(ref) case final now when now != ref) ref: now,
  };
  List<String>? record;
  if (facts.facts.recordPath case final params?
      when params.any((s) => s.isNotEmpty)) {
    // An empty parameter (no secondary record path) stays empty.
    final now = [for (final s in params) s.isEmpty ? s : relocated(s)];
    if (now.join('\n') != params.join('\n')) record = now;
  }
  final target = joinPath(
    titleDir,
    _Planner._free({...facts.titleNames}, p.posix.basename(project)),
  );
  return (
    operations: [
      MoveFile(project, target, role: FileRole.project),
      if (references.isNotEmpty || record != null)
        RewriteProject(target, references, recordPath: record, reported: false),
    ],
    movable: movable,
  );
}
