import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'conventions.dart';
import 'fixes.dart';
import 'library_path.dart';
import 'node_file.dart';
import 'scaffold.dart';

/// Organization of a title into version folders (SPEC §5.8 step 4, #148),
/// planned before it is applied: reads gather the [FixFacts]
/// (`gatherFix`), the pure function [planFix] computes the operations
/// ([MediaPlan], shown as the preview), then `applyPlan` makes them through
/// the storage.

/// Suffix of the proxy file REAPER keeps next to a subproject.
const proxySuffix = '-PROX';

/// What gathering keeps of a project: its text is not kept.
final class ProjectFacts {
  const ProjectFacts(
    this.references, {
    this.recordPath,
    this.namedFiles = const {},
    this.versionId,
  });

  /// Media references (`FILE` of `SOURCE` chunks), deduplicated, as
  /// written.
  final List<String> references;

  /// Parameters of its `RECORD_PATH` line; null without one.
  final List<String>? recordPath;

  /// Names, among the media of the folder of the fix, that appear in the
  /// project outside its `FILE` lines (`namedOutsideSources`): plugin
  /// states.
  final Set<String> namedFiles;

  /// Its version id; null if not adopted.
  final VersionId? versionId;
}

/// Facts about the folder of a fix and its target, gathered by reads only.
final class FixFacts {
  const FixFacts({
    this.entries = const [],
    this.projects = const {},
    this.unreadable = const {},
    this.files = const {},
    this.target,
    this.targetNames = const {},
    this.targetIds = const {},
    this.unsortedFolder,
    this.unsortedNames = const {},
  });

  /// Every entry of the folder of the fix (its candidate root, or the
  /// folder of the project moved), listed before any change.
  final List<StorageEntry> entries;

  /// Facts of the projects of the fix, then of the subprojects they
  /// reference, by path.
  final Map<String, ProjectFacts> projects;

  /// Projects that cannot be read, by path, with the reason.
  final Map<String, String> unreadable;

  /// Entries of the files referenced by the projects of the fix, and of the
  /// proxy files of the subprojects among them, by path as resolved; a path
  /// missing here does not exist.
  final Map<String, StorageEntry> files;

  /// Entry of the target title folder; null if it does not exist.
  final StorageEntry? target;

  /// Lowercase names of the entries of the target title folder.
  final Set<String> targetNames;

  /// Version ids of the projects of the target title, when it is another
  /// folder than the one of the fix.
  final Set<VersionId> targetIds;

  /// For an [AttachFile]: path of the `Unsorted/` folder of the target
  /// title (in any case), null if it has none.
  final String? unsortedFolder;

  /// For an [AttachFile]: lowercase names of the entries of
  /// [unsortedFolder].
  final Set<String> unsortedNames;
}

/// What a moved or copied file is, for the report: [unsorted] for a file
/// found outside any title, moved into the `Unsorted/` folder of a title.
enum FileRole { media, proxy, project, folder, unsorted }

/// One operation of a [MediaPlan], applied in order.
sealed class MediaOperation {
  const MediaOperation();
}

/// Moves the file or folder [from] to [to].
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

/// Creates the folder [path] (`Media/`, `Renders/` of a version).
final class CreateFolder extends MediaOperation {
  const CreateFolder(this.path);

  final String path;

  @override
  String toString() => 'create $path/';
}

/// Creates the title [dir]: its node file, at the layout [level].
final class CreateTitle extends MediaOperation {
  const CreateTitle(this.dir, this.level);

  final String dir;
  final String level;

  @override
  String toString() => 'create title $dir';
}

/// Sets the label, owner (if any) and status (if any) of the version [id]
/// in the node file of the title [titleDir] (SPEC §4.2, §5.9).
final class SetVersionEntries extends MediaOperation {
  const SetVersionEntries(
    this.titleDir,
    this.id, {
    required this.label,
    this.owner,
    this.status,
  });

  final String titleDir;
  final VersionId id;
  final String label;
  final MemberId? owner;
  final String? status;

  @override
  String toString() =>
      ['version $id in $titleDir: $label', ?owner, ?status].join(', ');
}

/// Rewrites the project at [path]: each media reference of [references]
/// replaced by its value, its record path replaced by [recordPath] if set,
/// and [versionId] written if set (adoption), as targeted patches (SPEC
/// §7.3). Reported as normalized if [reported].
final class RewriteProject extends MediaOperation {
  const RewriteProject(
    this.path,
    this.references, {
    this.recordPath,
    this.versionId,
    this.reported = true,
  });

  final String path;
  final Map<String, String> references;
  final List<String>? recordPath;
  final VersionId? versionId;
  final bool reported;

  @override
  String toString() => [
    'rewrite $path',
    for (final MapEntry(:key, :value) in references.entries) '$key -> $value',
    if (recordPath case final record?) 'RECORD_PATH ${record.join(' ')}',
    if (versionId case final id?) 'VERSIONID $id',
  ].join(', ');
}

/// Operations of a fix, in order, and what is left intact or reported with
/// its reason ([ReportKind.missingMedia], [ReportKind.externalMedia],
/// [ReportKind.referencedByPlugin], [ReportKind.statusFolderUnmatched],
/// [ReportKind.targetExists], [ReportKind.fixFailed]).
typedef MediaPlan = ({List<MediaOperation> operations, Report blocked});

/// Counts of a [MediaPlan], for its preview.
typedef MediaPlanCounts = ({int moved, int copied, int rewritten, int blocked});

/// Kinds of a [MediaPlan] report that leave a path as it is.
const blockingKinds = {
  ReportKind.missingMedia,
  ReportKind.externalMedia,
  ReportKind.referencedByPlugin,
  ReportKind.targetExists,
  ReportKind.fixFailed,
};

/// Counts of [plan]: media moved, media copied, projects rewritten and
/// paths left intact or reported as such ([blockingKinds]).
MediaPlanCounts countPlan(MediaPlan plan) {
  var (moved, copied, rewritten) = (0, 0, 0);
  for (final op in plan.operations) {
    switch (op) {
      case MoveFile(role: FileRole.media):
        moved++;
      case CopyFile(role: FileRole.media):
        copied++;
      case RewriteProject(reported: true):
        rewritten++;
      default:
        break;
    }
  }
  return (
    moved: moved,
    copied: copied,
    rewritten: rewritten,
    blocked: {
      for (final MapEntry(:key, value: list) in plan.blocked.items.entries)
        if (blockingKinds.contains(key))
          for (final item in list) item.path,
    }.length,
  );
}

/// Plans [fix] (SPEC §5.8 step 4, #148) from its [facts]:
///
/// - [OrganizeTitle] of a title folder moves it to its target first, if free
///   and none of its files is used from outside it; the projects of a candidate
///   placed above the title level move one by one into the target, created.
///   [AttachVersions] needs an existing title. A target without node file gets
///   one.
/// - Each version gets the folder named [FixVersion.folder] in the target
///   title, or a free `name (n)` variant: a project alone in a folder of
///   the title (no other project in or below it, none of its files used
///   from outside it) moves with its folder; any other project moves alone
///   into a new folder, its proxy file along. Its file keeps its name. A
///   reserved folder name gets a `name (n)` variant too. A project used as
///   a subproject outside the fix is left intact, unless the fix is forced.
///   A project id already used in the fix or in the target title is
///   replaced by a new one.
/// - Each media outside the `Media/` of its version is moved there when no
///   other project uses it (the versions of the fix still to organize,
///   [usage] for the others), copied otherwise; a project outside a
///   reserved folder (a version) is always copied. A subproject takes its
///   proxy file along; its own references, as those of a subproject
///   already in the `Media/` of a version, are rewritten once every file
///   is placed.
///   References are rewritten, the record path set to `Media`, the version
///   adopted when it has no id, and its label, owner and status set in the
///   node file of the title.
/// - A version with a missing media, or an absolute one or outside the
///   library, is reported and, unless the fix is forced
///   ([MigrationFix.force]: organized anyway, those references left as
///   written), left intact; so is one whose media would take
///   a name already taken in its `Media/`. The files of a version left
///   intact, those already in the `Media/` of a version and the projects of
///   the fix are never moved, only copied; nor is a folder holding a file
///   of a version left intact, nor a title folder while such a version
///   uses a file outside it.
/// - A file of the folder that no project references but one names outside
///   its `FILE` lines (a plugin state) is left where it is and reported
///   ([ReportKind.referencedByPlugin]).
///
/// Nothing is planned if a project of the fix cannot be read: its media
/// are unknown ([ReportKind.fixFailed]).
///
/// An [AttachFile] moves its file into the `Unsorted/` folder of its
/// target title, created if missing, under a free `name (n)` variant of its
/// name; nothing is planned ([ReportKind.fixFailed]) when the file is
/// missing or a folder, when the target is not a title (no node file), when
/// the file already lies in its `Unsorted/` folder, or when the title holds
/// a file named `Unsorted`.
MediaPlan planFix(
  MigrationFix fix,
  FixFacts facts, {
  Map<String, List<String>> usage = const {},
}) => switch (fix) {
  AttachFile() => _planAttach(fix, facts),
  _ => _Planner(fix, facts, usage).plan(),
};

/// The plan of [fix] ([planFix]).
MediaPlan _planAttach(AttachFile fix, FixFacts facts) {
  MediaPlan failed(String detail) => (
    operations: const [],
    blocked: Report({
      ReportKind.fixFailed: [ReportItem(fix.path, detail)],
    }),
  );
  final source = facts.entries
      .where((e) => e.path.toLowerCase() == fix.path.toLowerCase())
      .firstOrNull;
  if (source == null || source.isDirectory) {
    return failed('No file at ${fix.path}');
  }
  final target = fix.target;
  if (facts.target == null || !facts.targetNames.contains(nodeFileName)) {
    return failed('No title at $target');
  }
  final existing = facts.unsortedFolder;
  if (existing == null &&
      facts.targetNames.contains(unsortedFolderName.toLowerCase())) {
    return failed('A file named $unsortedFolderName is in $target');
  }
  final folder = existing ?? joinPath(target, unsortedFolderName);
  if (isWithin(fix.path, folder)) return failed('Already in $folder');
  final name = p.posix.basename(fix.path);
  final stem = p.posix.basenameWithoutExtension(name);
  final ext = p.posix.extension(name);
  var free = name;
  for (var i = 2; facts.unsortedNames.contains(free.toLowerCase()); i++) {
    free = '$stem ($i)$ext';
  }
  return (
    operations: [
      if (existing == null) CreateFolder(folder),
      MoveFile(fix.path, joinPath(folder, free), role: FileRole.unsorted),
    ],
    blocked: const Report(),
  );
}

/// State of one [planFix].
final class _Planner {
  _Planner(this.fix, this.facts, this.usage);

  final MigrationFix fix;
  final FixFacts facts;
  final Map<String, List<String>> usage;

  final operations = <MediaOperation>[];
  final reported = <ReportKind, List<ReportItem>>{};

  /// Moves planned so far, in order, from their source to their target.
  final moves = <(String, String)>[];

  /// Lowercase paths of the files and folders the plan creates.
  final created = <String>{};

  /// Lowercase names taken in the target title folder.
  late final Set<String> taken;

  /// Lowercase paths of the files that are never moved: the projects of
  /// the fix, the files of the versions left intact and those already in
  /// the media folder of a version.
  final pinned = <String>{};

  /// Versions still to organize referencing each file, by lowercase path.
  final users = <String, Set<String>>{};

  /// Files of the versions left intact, by lowercase path: they must stay
  /// where these versions expect them.
  final intact = <String, String>{};

  String get target => fix.target;

  /// The folder the fix lists: its candidate root, or the folder of the
  /// project moved.
  String get root => fix is MoveProject ? parentOf(fix.path) : fix.path;

  /// Current path of each known path (the entries of the folder and the
  /// referenced files), by lowercase original path.
  late final _now = <String, String>{
    for (final e in facts.entries) e.path.toLowerCase(): e.path,
    for (final path in facts.files.keys) path.toLowerCase(): path,
  };

  /// Lowercase original path of each known path, by lowercase current path.
  late final _origin = {for (final k in _now.keys) k: k};

  /// Current path of [path], following the moves planned so far.
  String locate(String path) {
    if (_now[path.toLowerCase()] case final now?) return now;
    var current = path;
    for (final (from, to) in moves) {
      if (current.toLowerCase() == from.toLowerCase()) {
        current = to;
      } else if (isWithin(current, from)) {
        current = '$to${current.substring(from.length)}';
      }
    }
    return current;
  }

  void move(String from, String to, FileRole role) {
    operations.add(MoveFile(from, to, role: role));
    moves.add((from, to));
    final key = from.toLowerCase();
    if (role != FileRole.folder) {
      final origin = _origin.remove(key) ?? key;
      _now[origin] = to;
      _origin[to.toLowerCase()] = origin;
      return;
    }
    // A folder: everything known in it follows, rare enough to scan.
    _origin.clear();
    for (final MapEntry(key: origin, value: now) in _now.entries.toList()) {
      final lower = now.toLowerCase();
      final moved = lower == key
          ? to
          : lower.startsWith('$key/')
          ? '$to${now.substring(from.length)}'
          : now;
      _now[origin] = moved;
      _origin[moved.toLowerCase()] = origin;
    }
  }

  /// Whether [path] (current, lowercase compared) exists once the
  /// operations planned so far are made.
  bool exists(String path) {
    final key = path.toLowerCase();
    return created.contains(key) || _origin.containsKey(key);
  }

  void report(ReportKind kind, ReportItem item) =>
      reported.putIfAbsent(kind, () => []).add(item);

  MediaPlan blocked(ReportKind kind, String detail) => (
    operations: const [],
    blocked: Report({
      kind: [ReportItem(fix.path, detail)],
    }),
  );

  MediaPlan plan() {
    if (facts.unreadable.isNotEmpty) {
      return blocked(ReportKind.fixFailed, unreadableMessage(facts.unreadable));
    }
    final sameFolder = root.toLowerCase() == target.toLowerCase();
    final movesFolder =
        fix is OrganizeTitle && (fix as OrganizeTitle).titleFolder;
    if (fix is AttachVersions && (sameFolder || facts.target == null)) {
      return blocked(ReportKind.fixFailed, 'No other title at $target');
    }
    final referenced = <String>{};
    final versions = [
      for (final v in fix.versions)
        if (_resolve(v, referenced) case final files?) (v, files),
    ];
    if (movesFolder && !sameFolder) {
      if (facts.target != null) return blocked(ReportKind.targetExists, target);
      if (isWithin(target, root)) {
        return blocked(ReportKind.fixFailed, 'Target inside $root: $target');
      }
      for (final MapEntry(key: file, value: users) in usedUnderRoot.entries) {
        if (users.any((p) => !_inside(p, root))) {
          return blocked(
            ReportKind.fixFailed,
            'A project outside the title uses $file: moving the title '
            'would break it',
          );
        }
      }
      // A version left intact would lose the files it reaches outside.
      for (final file in intact.values) {
        if (!isWithin(file, root)) {
          return blocked(
            ReportKind.fixFailed,
            'A project left as it is uses $file, outside the title: '
            'moving the title would break it',
          );
        }
      }
      move(root, target, FileRole.folder);
    } else if (!sameFolder &&
        facts.target != null &&
        !facts.targetNames.contains(nodeFileName)) {
      // A folder that is not a title.
      return blocked(ReportKind.targetExists, target);
    }
    final inPlace = fix is OrganizeTitle && (movesFolder || sameFolder);
    final names = inPlace
        ? {
            for (final e in facts.entries)
              if (parentOf(e.path) == root)
                p.posix.basename(e.path).toLowerCase(),
          }
        : facts.targetNames;
    taken = {...names};
    if (!names.contains(nodeFileName)) {
      operations.add(CreateTitle(target, fix.level));
      created.add(joinPath(target, nodeFileName).toLowerCase());
    }
    _reportNamed(referenced);
    for (final (v, files) in versions) {
      for (final file in files.keys) {
        users.putIfAbsent(file, () => {}).add(v.source.toLowerCase());
      }
    }
    for (final (v, files) in versions) {
      final failure = _organize(v, files);
      // Its project moved with the title: its references would break.
      if (failure != null && movesFolder && !sameFolder) {
        return blocked(ReportKind.fixFailed, '${v.source}: $failure');
      }
      for (final file in files.keys) {
        users[file]?.remove(v.source.toLowerCase());
      }
    }
    for (final (file, to, written) in subprojects) {
      _rewriteSubproject(file, to, written);
    }
    return (operations: operations, blocked: Report(reported));
  }

  /// Files referenced by the version [v], by lowercase path; null, the
  /// version left intact and reported, if one is missing, absolute or
  /// outside the library.
  Map<String, String>? _resolve(FixVersion v, Set<String> referenced) {
    pinned.add(v.source.toLowerCase());
    final project = facts.projects[v.source]!;
    final refs = <String, String>{};
    final missing = <String>[];
    final external = <String>[];
    for (final ref in project.references) {
      final file = resolveReference(parentOf(v.source), ref);
      if (file == null) {
        external.add(ref);
      } else if (facts.files[file] case StorageEntry(isDirectory: false)) {
        refs[file.toLowerCase()] = file;
      } else {
        missing.add(ref);
      }
    }
    referenced.addAll(refs.keys);
    if (missing.isEmpty && external.isEmpty) return refs;
    if (missing.isNotEmpty) {
      report(ReportKind.missingMedia, ReportItem(v.source, missing.join('\n')));
    }
    if (external.isNotEmpty) {
      report(
        ReportKind.externalMedia,
        ReportItem(v.source, external.join('\n')),
      );
    }
    // Forced: organized anyway, the references not found left as written.
    if (fix.force) return refs;
    pinned.addAll(refs.keys);
    intact.addAll(refs);
    return null;
  }

  /// Reports the files of the folder of the fix that a project of the fix
  /// names outside its `FILE` lines (a plugin state) and none references:
  /// they are left where they are.
  void _reportNamed(Set<String> referenced) {
    final named = <String, List<String>>{};
    for (final MapEntry(key: path, value: project) in facts.projects.entries) {
      for (final name in project.namedFiles) {
        named.putIfAbsent(name.toLowerCase(), () => []).add(path);
      }
    }
    for (final e in facts.entries) {
      if (e.isDirectory || referenced.contains(e.path.toLowerCase())) continue;
      if (named[p.posix.basename(e.path).toLowerCase()] case final by?) {
        report(
          ReportKind.referencedByPlugin,
          ReportItem(e.path, by.join('\n')),
        );
      }
    }
  }

  /// Whether the project [source] lies alone in a folder of the title (any
  /// folder for [MoveProject]) that is not a reserved one: no other project
  /// in or below it, no node file, and none of its files used by a project
  /// outside it or by a version left intact.
  bool _alone(String source) {
    final dir = parentOf(source);
    if (dir.isEmpty || isReservedFolder(p.posix.basename(dir))) return false;
    if (intact.values.any((file) => isWithin(file, dir))) return false;
    if (fix is! MoveProject && (dir == root || parentOf(dir) != root)) {
      return false;
    }
    // Its folder cannot move into itself: the project moves alone.
    final into = target.toLowerCase();
    final lower = dir.toLowerCase();
    if (into == lower || into.startsWith('$lower/')) return false;
    final projects = facts.entries.where(
      (e) =>
          !e.isDirectory &&
          isWithin(e.path, dir) &&
          isProjectFile(e.path) &&
          !relativeTo(
            dir,
            e.path,
          ).split('/').any((s) => isExcludedFolder(s) || isReservedFolder(s)),
    );
    if (projects.length != 1) return false;
    final node = joinPath(dir, nodeFileName).toLowerCase();
    if (facts.entries.any((e) => e.path.toLowerCase() == node)) return false;
    return !usedUnderRoot.entries.any(
      (e) => _inside(e.key, dir) && e.value.any((p) => !_inside(p, dir)),
    );
  }

  /// Whether [path] lies in [dir], case-insensitive.
  static bool _inside(String path, String dir) =>
      path.toLowerCase().startsWith('${dir.toLowerCase()}/');

  /// Users of the files under the root of the fix, by path.
  late final usedUnderRoot = {
    for (final e in usage.entries)
      if (_inside(e.key, root)) e.key: e.value,
  };

  /// Projects outside the fix using the project [source], as a subproject.
  List<String> _usersOutside(String source) => [
    for (final p in usedBy[source.toLowerCase()] ?? const <String>[])
      if (!sources.contains(p.toLowerCase())) p,
  ];

  /// Whether [name] can name a version folder: a valid name, not reserved.
  static bool _usable(String name) =>
      isValidFolderName(name) &&
      !isReservedFolder(name) &&
      !isExcludedFolder(name);

  /// [wanted], or its first free `name (n)` variant in the target title,
  /// which it takes.
  String _free(String wanted) {
    for (var i = _usable(wanted) ? 1 : 2; ; i++) {
      final name = i == 1 ? wanted : '$wanted ($i)';
      if (taken.add(name.toLowerCase())) return name;
    }
  }

  /// Lowercase paths of the version folders given so far.
  final claimed = <String>{};

  /// Version ids given so far, those of the target title first: a second
  /// project with the same id (a *Save As* copy) gets a new one.
  late final ids = {...facts.targetIds};

  /// References rewritten in each version organized, by lowercase path of
  /// its project: what its text holds afterwards.
  final rewrittenRefs = <String, Map<String, String>>{};

  /// Subprojects brought into a media folder: their path before the plan,
  /// where they are brought and the references their text holds then. Their
  /// references are rewritten once every file is placed.
  final subprojects = <(String, String, Map<String, String>)>[];

  /// Plans the organization of the version [v], whose files are [files]
  /// (by lowercase path, as found before the plan). Returns why it is left
  /// as it is, if so.
  String? _organize(FixVersion v, Map<String, String> files) {
    final source = v.source;
    final project = facts.projects[source]!;
    if (!isValidFolderName(v.folder)) {
      return _leave(v, files, 'Invalid folder name: ${v.folder}');
    }
    final alone = _alone(source);
    // What moves: the folder of a project alone in it, else the project.
    final current = locate(alone ? parentOf(source) : source);
    final currentDir = alone ? current : parentOf(current);
    final stays =
        parentOf(currentDir).toLowerCase() == target.toLowerCase() &&
        p.posix.basename(currentDir).toLowerCase() == v.folder.toLowerCase() &&
        _usable(v.folder) &&
        !claimed.contains(currentDir.toLowerCase());
    // A project using it as a subproject would lose it.
    if (!stays && !alone && !fix.force) {
      if (_usersOutside(source) case final users when users.isNotEmpty) {
        return _leave(
          v,
          files,
          'Used as a subproject by ${users.join(', ')}: '
          'moving it would break them',
        );
      }
    }
    final versionDir = stays ? currentDir : joinPath(target, _free(v.folder));
    claimed.add(versionDir.toLowerCase());
    final relocated = versionDir != currentDir;
    // What the version folder holds now: its current folder, unless the
    // project moves alone into a new one.
    final holds = !relocated || alone ? currentDir : null;
    final media = joinPath(versionDir, mediaFolderName);
    // Where each file goes, checked before any operation of the version.
    final placed = <String, String>{};
    final names = <String>{};
    for (final MapEntry(key: key, value: file) in files.entries) {
      final now = locate(file);
      final after = holds != null && isWithin(now, holds)
          ? joinPath(versionDir, relativeTo(holds, now))
          : now;
      // Already its own: kept for it.
      if (isWithin(after, media)) {
        pinned.add(key);
        // A subproject: its references follow the files moved.
        if (facts.projects.containsKey(file)) {
          subprojects.add((file, after, const {}));
        }
        continue;
      }
      final name = p.posix.basename(file);
      final clash =
          !names.add(name.toLowerCase()) ||
          (holds != null && exists(joinPath(holds, '$mediaFolderName/$name')));
      if (clash) {
        return _leave(v, files, 'Name taken in its media folder: $name');
      }
      placed[key] = joinPath(media, name);
    }
    if (relocated) {
      if (alone) {
        move(current, versionDir, FileRole.folder);
      } else {
        move(
          current,
          joinPath(versionDir, p.posix.basename(source)),
          FileRole.project,
        );
        final proxy = '$source$proxySuffix';
        if (_now.containsKey(proxy.toLowerCase())) {
          move(
            locate(proxy),
            joinPath(versionDir, p.posix.basename(proxy)),
            FileRole.proxy,
          );
        }
      }
      if (p.posix.basename(versionDir) != v.folder) {
        report(ReportKind.fileRenamed, ReportItem(versionDir, v.folder));
      }
    }
    for (final folder in [media, joinPath(versionDir, rendersFolderName)]) {
      if (!exists(folder)) {
        operations.add(CreateFolder(folder));
        created.add(folder.toLowerCase());
      }
    }
    for (final MapEntry(key: key, value: to) in placed.entries) {
      _bring(files[key]!, to, keep: _shared(key, source));
    }
    final references = <String, String>{};
    for (final ref in project.references) {
      final file = resolveReference(parentOf(source), ref);
      // Not found (a forced fix): left as written.
      if (file == null || !files.containsKey(file.toLowerCase())) continue;
      final now = placed[file.toLowerCase()] ?? locate(file);
      final rewritten = relativeReference(versionDir, now, like: ref);
      if (rewritten != ref) references[ref] = rewritten;
    }
    final params = project.recordPath ?? const <String>[];
    final recordDir = resolveReference(versionDir, params.firstOrNull ?? '');
    // `.\Media` is the media folder too: left as written.
    final record = recordDir?.toLowerCase() == media.toLowerCase()
        ? null
        : [mediaFolderName, params.elementAtOrNull(1) ?? ''];
    final adopted = project.versionId;
    final id = adopted != null && ids.add(adopted)
        ? adopted
        : VersionId.generate();
    ids.add(id);
    operations.add(
      SetVersionEntries(
        target,
        id,
        label: v.label,
        owner: v.owner,
        status: v.status,
      ),
    );
    final path = locate(source);
    if (references.isNotEmpty || record != null || id != adopted) {
      operations.add(
        RewriteProject(
          path,
          references,
          recordPath: record,
          versionId: id != adopted ? id : null,
        ),
      );
    }
    rewrittenRefs[source.toLowerCase()] = references;
    if (v.statusFolder case final folder? when v.status == null) {
      report(ReportKind.statusFolderUnmatched, ReportItem(path, folder));
    }
    return null;
  }

  /// Leaves the version [v], whose files are [files], as it is, reported
  /// with the [failure] it returns.
  String _leave(FixVersion v, Map<String, String> files, String failure) {
    report(ReportKind.fixFailed, ReportItem(v.source, failure));
    pinned.addAll(files.keys);
    return failure;
  }

  /// Lowercase paths of the projects of the fix.
  late final sources = {for (final v in fix.versions) v.source.toLowerCase()};

  /// Projects using each file outside the fix, by lowercase path.
  late final usedBy = <String, List<String>>{
    for (final MapEntry(key: file, value: projects) in usage.entries)
      file.toLowerCase(): projects,
  };

  /// Whether the file [key] (lowercase path) is used by another project
  /// than [source], or is a project outside a reserved folder (a version of
  /// a title): it is copied, not moved.
  bool _shared(String key, String source) {
    if (pinned.contains(key)) return true;
    if (isProjectFile(key) && !parentOf(key).split('/').any(isReservedFolder)) {
      return true;
    }
    final others = users[key] ?? const {};
    if (others.any((s) => s != source.toLowerCase())) return true;
    return (usedBy[key] ?? const []).any(
      (p) => !sources.contains(p.toLowerCase()),
    );
  }

  /// Brings [file] to [to]: copied if [keep], moved otherwise; a subproject
  /// takes its proxy file along, and its references follow it once every
  /// file is placed.
  void _bring(String file, String to, {required bool keep}) {
    final now = locate(file);
    void bring(String from, String target, FileRole role) {
      if (keep) {
        operations.add(CopyFile(from, target, role: role));
        created.add(target.toLowerCase());
      } else {
        move(from, target, role);
      }
    }

    bring(now, to, FileRole.media);
    if (!isProjectFile(file)) return;
    final proxy = '$file$proxySuffix';
    if (facts.files[proxy] case StorageEntry(isDirectory: false)) {
      bring(locate(proxy), '$to$proxySuffix', FileRole.proxy);
    }
    if (facts.projects.containsKey(file)) {
      // Its text as it is now: rewritten already if it is a version of the
      // fix organized before.
      subprojects.add((file, to, {...?rewrittenRefs[file.toLowerCase()]}));
    }
  }

  /// Rewrites the references of the subproject [file] brought to [to],
  /// whose text holds them as [written] (original reference to the one
  /// written, if rewritten), towards where their files end.
  void _rewriteSubproject(String file, String to, Map<String, String> written) {
    final references = <String, String>{};
    for (final ref in facts.projects[file]!.references) {
      final target = resolveReference(parentOf(file), ref);
      if (target == null) continue;
      final now = written[ref] ?? ref;
      final rewritten = relativeReference(
        parentOf(to),
        locate(target),
        like: now,
      );
      if (rewritten != now) references[now] = rewritten;
    }
    if (references.isNotEmpty) {
      operations.add(RewriteProject(to, references, reported: false));
    }
  }
}

/// [path], inside [dir], relative to it.
String relativeTo(String dir, String path) =>
    dir.isEmpty ? path : path.substring(dir.length + 1);

/// Message of a fix whose [projects] (by path, with the reason) cannot be
/// read.
String unreadableMessage(Map<String, String> projects) => [
  'Project unreadable, nothing can be changed:',
  for (final MapEntry(:key, :value) in projects.entries) '$key ($value)',
].join(' ');
