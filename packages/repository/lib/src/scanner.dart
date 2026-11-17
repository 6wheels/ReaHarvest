import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'library_path.dart';
import 'project_file.dart';
import 'conventions.dart';
import 'migration.dart';
import 'mounted_folder_storage.dart';
import 'fix_proposals.dart';
import 'node_file.dart';
import 'scaffold.dart';

/// Size and modification time of a file, used to skip unchanged files.
typedef FileStamp = ({int size, DateTime modified});

/// Result of a library root scan.
final class ScanResult {
  const ScanResult({
    this.titles = const [],
    this.nodes = const {},
    this.issues = const Report(),
    this.corrupted = const [],
    this.orphanNodes = const [],
    this.stamps = const {},
    this.freeTree = false,
    this.journalPosition,
    this.candidates = const [],
  });

  /// Titles found, sorted by path.
  final List<Title> titles;

  /// Node files by folder path (`''` for the root).
  final Map<String, NodeFile> nodes;

  /// Every issue of the library ("To sort", SPEC §5.2, §5.8 step 3), by
  /// kind, each sorted by path: those of the [candidates], each one once,
  /// and the folders whose node file has another level. Misplaced items
  /// name their expected level and, when known, their target. Titles
  /// below an unknown intermediate folder are not indexed, except titles
  /// placed too high, indexed where they are with the tags of their target.
  final Report issues;

  /// Title candidates of a layout library (SPEC §5.8 step 3), sorted by
  /// root; empty in a free tree.
  final List<ScanCandidate> candidates;

  /// Paths of unreadable or corrupted `.RPP` and node files. A folder whose
  /// node file is corrupted is not scanned further.
  final List<String> corrupted;

  /// Paths of `.node.json` files found in folders that are not nodes (no
  /// project in or below them): reported, never used nor deleted (#54).
  final List<String> orphanNodes;

  /// Stamps of all scanned files (excluded files and folders left out), by
  /// path; used to skip unchanged files on the next scan.
  final Map<String, FileStamp> stamps;

  /// Whether the library is a free tree (SPEC §3.3).
  final bool freeTree;

  /// Position of the migration journals taken into account by this scan:
  /// the next scan reads again the files rewritten after it.
  final JournalPosition? journalPosition;

  /// This result without the stamps of [paths]: the next incremental scan
  /// reads these files again.
  ScanResult withoutStamps(Set<String> paths) => ScanResult(
    titles: titles,
    nodes: nodes,
    issues: issues,
    corrupted: corrupted,
    orphanNodes: orphanNodes,
    stamps: {
      for (final MapEntry(:key, :value) in stamps.entries)
        if (!paths.contains(key)) key: value,
    },
    freeTree: freeTree,
    journalPosition: journalPosition,
    candidates: candidates,
  );

  /// Versions without metadata ("To adopt", SPEC §4.2); always empty in a
  /// free tree, whose versions are identified by their path.
  Iterable<(Title, Version)> get toAdopt => [
    if (!freeTree)
      for (final t in titles)
        for (final v in t.versions)
          if (!v.isAdopted) (t, v),
  ];
}

/// A title candidate (SPEC §5.8 step 3): a `.RPP`, its siblings and its
/// children are versions of one same title, reserved folders aside.
final class ScanCandidate {
  const ScanCandidate({
    required this.root,
    this.title,
    this.versions = const [],
    this.issues = const Report(),
  });

  /// Folder of the candidate: its title folder (at the layout depth, or
  /// placed too high), or the folder holding its projects when they lie
  /// above the title level.
  final String root;

  /// Path of the indexed title the candidate is (its [root]) or is matched
  /// to (one of its version ids known by that title); null if none.
  final String? title;

  /// Its readable projects, their file name relative to [root], sorted.
  final List<Version> versions;

  /// Its problems, one item per problem, by kind, each sorted by path.
  final Report issues;
}

/// Scans [root] in a background isolate (see [scan]).
Future<ScanResult> scanFolder(
  String root,
  Library library, {
  ScanResult? previous,
  JournalPosition? journalPosition,
  bool writeNodes = true,
}) => Isolate.run(
  () => scan(
    MountedFolderStorage(root),
    library,
    previous: previous,
    journalPosition: journalPosition,
    writeNodes: writeNodes,
  ),
);

/// Scans a library root following its layout, or as a free tree (SPEC §3).
///
/// Files whose stamp did not change since [previous] are not read again,
/// except those a migration rewrote after [journalPosition] (the position
/// stored with [previous], [rewrittenSince]); free tree projects are never
/// read (no metadata, SPEC §3.3). A layout folder is a node only if a
/// project lies in it or below it (outside the reserved title and version
/// folders), or, for a title, if its trash or the history of one of its
/// versions still holds one (#54). The versions of a title are the projects
/// of its subfolders, reserved ones aside (SPEC §3.2).
///
/// With [writeNodes] (root of a `local` library, workspace), missing
/// `.node.json` files are written for these nodes and for free tree titles:
/// the only writes; no folder is created (SPEC §3.2). Without it (repository
/// in `cloud` or `collab` mode), nothing is written and a folder without
/// node file is not a node: it gives no title, nor does any folder below it.
Future<ScanResult> scan(
  RepositoryStorage storage,
  Library library, {
  ScanResult? previous,
  JournalPosition? journalPosition,
  bool writeNodes = true,
}) async {
  final (:paths, :position) = await rewrittenSince(storage, journalPosition);
  return _Scanner(
    storage,
    library,
    (previous ?? const ScanResult()).withoutStamps(paths),
    position,
    writeNodes,
  ).run();
}

/// Result of the scan of one title folder ([scanTitle]): what a full scan
/// finds in it.
typedef TitleScan = ({
  /// Null if the folder is no longer a title.
  Title? title,
  NodeFile? node,

  /// Stamps of the files of the title folder.
  Map<String, FileStamp> stamps,

  /// Issues whose path is below the title folder, duplicated version
  /// identifiers aside (they span titles).
  Report issues,
  List<String> corrupted,
  List<String> orphanNodes,

  /// The candidate of the title folder; null with [title].
  ScanCandidate? candidate,
});

/// Scans the folder of [previous] in a background isolate (see
/// [scanTitle]).
Future<TitleScan> scanTitleFolder(
  String root,
  Library library,
  Title previous, {
  ScanResult stored = const ScanResult(),
}) => Isolate.run(
  () =>
      scanTitle(MountedFolderStorage(root), library, previous, stored: stored),
);

/// Scans again the folder of the title [previous] only, after an action on
/// one of its versions (SPEC §8): lists that folder, and reports for it
/// what [scan] reports below it. The title keeps the tags of [previous] (a
/// title placed too high keeps those of its target). Files whose stamp did
/// not change since [stored], the last scan of the library, are not read
/// again; a reference leaving the folder is checked with one `stat`.
///
/// The files a migration rewrote after the journal position of [stored]
/// are read again ([rewrittenSince]); that position is left as it is, for
/// the next full scan.
///
/// Writes nothing: a title whose node file is missing or unreadable is no
/// longer a title, nor is a folder without a project in it or below it (a
/// free tree title: without a project directly in it). Duplicated version
/// identifiers and versions known by another title span titles: they are
/// left to the caller, like the issues of the position of the title.
Future<TitleScan> scanTitle(
  RepositoryStorage storage,
  Library library,
  Title previous, {
  ScanResult stored = const ScanResult(),
}) async {
  final position = stored.journalPosition;
  final paths = position == null
      ? const <String>{}
      : (await rewrittenSince(storage, position)).paths;
  return _Scanner(
    storage,
    library,
    stored.withoutStamps(paths),
    null,
    false,
  ).runTitle(previous);
}

final class _Scanner {
  _Scanner(
    this.storage,
    this.library,
    this.previous,
    this.journalPosition,
    this.writeNodes,
  ) : previousVersions = {
        for (final c in previous.candidates)
          for (final v in c.versions) joinPath(c.root, v.fileName): v,
        for (final t in previous.titles)
          for (final v in t.versions) joinPath(t.path, v.fileName): v,
      };

  final RepositoryStorage storage;
  final Library library;
  final ScanResult previous;
  final JournalPosition? journalPosition;
  final bool writeNodes;
  final Map<String, Version> previousVersions;

  final dirs = <String>{''};
  final files = <String, List<StorageEntry>>{};
  final titles = <Title>[];
  final nodes = <String, NodeFile>{};

  /// Issues outside any candidate.
  final issues = <ReportKind, List<ReportItem>>{};
  final corrupted = <String>[];

  /// Projects of each candidate, by root.
  final groups = <String, List<StorageEntry>>{};

  /// Candidate roots holding projects above the title level only: their
  /// folder is not a title folder.
  final shallow = <String>{};

  /// Issues, versions and matched title of each candidate, by root.
  final candidateIssues = <String, Map<ReportKind, List<ReportItem>>>{};
  final candidateVersions = <String, List<Version>>{};
  final matched = <String, String>{};
  final stamps = <String, FileStamp>{};

  /// Bytes of every file below each folder, excluded ones too, by category
  /// relative to that folder (version sizes).
  final sizes = <String, Map<SizeCategory, int>>{};

  /// Folders holding files, by parent folder.
  late final children = () {
    final children = <String, List<String>>{};
    for (final folder in files.keys) {
      if (folder.isNotEmpty) {
        children.putIfAbsent(parentOf(folder), () => []).add(folder);
      }
    }
    return children;
  }();

  /// Lowercase paths of every file, excluded ones too, to find missing
  /// media (case-insensitive like Windows and macOS).
  final existing = <String>{};

  /// Folders whose trash or history holds a project.
  final traces = <String>{};

  Future<ScanResult> run() async {
    (await storage.list('', recursive: true)).forEach(_add);
    final ordered = dirs.toList()
      ..sort((a, b) => _depth(a).compareTo(_depth(b)));
    final layout = library.layout;
    if (layout == null) {
      await _scanFreeTree(ordered);
    } else {
      await _scanLayout(ordered, layout);
      _group(layout);
      await _readCandidates();
      _findDuplicates();
      _findKnownElsewhere(layout);
    }
    final orphanNodes = _orphanNodes();
    titles.sort((a, b) => a.path.compareTo(b.path));
    _sort();
    final candidates = _candidates();
    return ScanResult(
      titles: titles,
      nodes: nodes,
      issues: Report({
        for (final kind in ReportKind.values)
          if ({
                ...?issues[kind],
                for (final c in candidates) ...?c.issues.items[kind],
              }.toList()
              case final list when list.isNotEmpty)
            kind: list..sort((a, b) => a.path.compareTo(b.path)),
      }),
      corrupted: corrupted,
      orphanNodes: orphanNodes,
      stamps: stamps,
      freeTree: layout == null,
      journalPosition: journalPosition,
      candidates: candidates,
    );
  }

  /// The candidates found, sorted by root.
  List<ScanCandidate> _candidates() {
    final titlePaths = {for (final t in titles) t.path};
    return [
      for (final root in groups.keys.toList()..sort())
        ScanCandidate(
          root: root,
          title: titlePaths.contains(root) ? root : matched[root],
          versions: candidateVersions[root] ?? const [],
          issues: Report(candidateIssues[root] ?? const {}),
        ),
    ];
  }

  /// Scans the folder of [previous] only, as [run] would see it (SPEC §8):
  /// its tags are kept, the references leaving it are checked with one
  /// `stat` each, and nothing is written ([writeNodes] is false).
  Future<TitleScan> runTitle(Title previous) async {
    final dir = previous.path;
    (await storage.list(dir, recursive: true)).forEach(_add);
    final layout = library.layout;
    final title = layout == null
        ? await _freeTreeTitle(previous)
        : await _layoutTitle(previous, layout);
    if (title != null) titles.add(title);
    if (title != null && layout != null) {
      for (final MapEntry(key: folder, value: entries) in files.entries) {
        final projects = entries.where(_isProject);
        if (projects.isNotEmpty && !_inReserved(folder)) {
          groups.putIfAbsent(dir, () => []).addAll(projects);
        }
      }
      await _readCandidates(statOutside: true);
      if (groups[dir] case final projects?) {
        _checkFolders(dir, projects, layout);
      }
    }
    final orphanNodes = _orphanNodes();
    _sort();
    final candidate = _candidates().where((c) => c.root == dir).firstOrNull;
    return (
      title: title,
      node: nodes[dir],
      stamps: stamps,
      issues: candidate?.issues ?? const Report(),
      corrupted: corrupted,
      orphanNodes: orphanNodes,
      candidate: title == null ? null : candidate,
    );
  }

  /// The free tree title [previous] scanned again: still a title while a
  /// project lies directly in its folder; every project below it is one of
  /// its versions (SPEC §3.3).
  Future<Title?> _freeTreeTitle(Title previous) async {
    final dir = previous.path;
    if (_projects(dir).isEmpty) return null;
    final node = await _node(dir, freeTreeLevel);
    if (node == null) return null;
    return _title(dir, node, previous.tags, [
      for (final entries in files.values)
        for (final e in entries.where(_isProject)) _version(dir, e),
    ]);
  }

  /// The layout title [previous] scanned again: null if its folder is no
  /// longer a node of the title level.
  Future<Title?> _layoutTitle(Title previous, Layout layout) async {
    final dir = previous.path;
    final depth = layout.levels.length;
    final tooHigh = _depth(dir) < depth;
    if (!_qualified(depth).contains(dir) || (tooHigh && !_holdsTitle(dir))) {
      return null;
    }
    final node = await _node(dir, layout.leaf.key);
    if (node == null || node.level != layout.leaf.key) return null;
    return _title(dir, node, previous.tags, await _readVersions(dir));
  }

  /// Adds to [existing] the files outside the candidate folder [root] that
  /// its [versions] refer to, one `stat` per reference.
  Future<void> _statOutside(String root, List<Version> versions) async {
    final inside = '$root/'.toLowerCase();
    final checked = <String>{};
    Future<void> check(String path, List<String> refs) async {
      for (final ref in refs) {
        final file = resolveReference(parentOf(path), ref);
        final lower = file?.toLowerCase();
        if (file == null || lower!.startsWith(inside) || !checked.add(lower)) {
          continue;
        }
        if (await storage.stat(file) case final e? when !e.isDirectory) {
          existing.add(lower);
        }
      }
    }

    for (final v in versions) {
      await check(joinPath(root, v.fileName), v.media);
    }
  }

  /// Records the listed entry [e]: every file in [existing] and in the
  /// folder sizes; folders, files and stamps outside the excluded ones;
  /// traces of projects kept in a trash or history.
  void _add(StorageEntry e) {
    final segments = e.path.split('/');
    final parents = segments.sublist(0, segments.length - 1);
    if (!e.isDirectory) existing.add(e.path.toLowerCase());
    if (segments.first == collabFolderName ||
        segments.first == migrationFolderName) {
      return;
    }
    if (!e.isDirectory) _addSize(segments, e.size);
    if (parents.any(isExcludedFolder)) {
      if (!e.isDirectory && isProjectFile(e.path)) _addTrace(parents);
      return;
    }
    if (e.isDirectory) {
      if (!isExcludedFolder(segments.last)) dirs.add(e.path);
    } else if (!isExcludedFile(segments.last)) {
      files.putIfAbsent(parentOf(e.path), () => []).add(e);
      stamps[e.path] = _stamp(e);
    }
  }

  /// Adds the [size] of the file [segments] to each of its folders, in the
  /// category it has from there.
  void _addSize(List<String> segments, int size) {
    for (var i = 0; i < segments.length; i++) {
      final dir = segments.take(i).join('/');
      final category = _categoryOf(segments.sublist(i));
      final bytes = sizes.putIfAbsent(dir, () => {});
      bytes[category] = (bytes[category] ?? 0) + size;
    }
  }

  /// Category of the file [relative] (path segments) in a version folder.
  static SizeCategory _categoryOf(List<String> relative) {
    final name = relative.last.toLowerCase();
    if (relative.length == 1) {
      if (isProjectFile(name)) return SizeCategory.project;
      if (name.endsWith('.rpp-bak') || name.endsWith('.rpp-undo')) {
        return SizeCategory.reaperBackups;
      }
      return SizeCategory.other;
    }
    return switch (relative.first.toLowerCase()) {
      'media' => SizeCategory.media,
      'renders' => SizeCategory.renders,
      historyFolderName => SizeCategory.history,
      'backups' => SizeCategory.reaperBackups,
      _ => SizeCategory.other,
    };
  }

  /// Records the title of a project kept in the folders [parents]: the
  /// folder holding the trash, for a project in it or in a version folder
  /// in it (`<title>/.trash/<version>/`); the folder above the version
  /// holding the history, for a backup (`<title>/<version>/.history/`).
  void _addTrace(List<String> parents) {
    final i = parents.indexWhere(isExcludedFolder);
    final kept = parents.length - i - 1;
    final base = parents.take(i).join('/');
    switch (parents[i].toLowerCase()) {
      case trashFolderName when kept <= 1:
        traces.add(base);
      case historyFolderName when kept == 0 && base.isNotEmpty:
        traces.add(parentOf(base));
    }
  }

  /// Node files of folders that are not nodes, sorted.
  List<String> _orphanNodes() => [
    for (final MapEntry(key: dir, value: entries) in files.entries)
      if (!nodes.containsKey(dir))
        for (final e in entries)
          if (p.posix.basename(e.path) == nodeFileName &&
              !corrupted.contains(e.path))
            e.path,
  ]..sort();

  void _sort() {
    corrupted.sort();
    for (final map in [issues, ...candidateIssues.values]) {
      for (final list in map.values) {
        list.sort((a, b) => a.path.compareTo(b.path));
      }
    }
  }

  /// Titles are the topmost folders holding a project; every project below
  /// a title, at any level, is one of its versions (SPEC §3.3).
  Future<void> _scanFreeTree(List<String> ordered) async {
    // Ordered by depth: a title is found before any folder below it.
    final versions = <String, List<Version>>{};
    for (final dir in ordered) {
      if (_projects(dir).isNotEmpty && _titleOf(dir, versions) == null) {
        versions[dir] = [];
      }
    }
    for (final MapEntry(key: dir, value: entries) in files.entries) {
      if (_titleOf(dir, versions) case final title?) {
        versions[title]!.addAll([
          for (final e in entries.where(_isProject)) _version(title, e),
        ]);
      }
    }
    for (final MapEntry(key: dir, value: titleVersions) in versions.entries) {
      final node = await _node(dir, freeTreeLevel);
      if (node == null) continue;
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      final tags = {
        for (var i = 0; i < segments.length - 1; i++)
          'folder${i + 1}': segments[i],
        if (segments.isNotEmpty) 'title': segments.last,
      };
      titles.add(_title(dir, node, tags, titleVersions));
    }
  }

  /// Folder of [dir] or its closest parent that is a key of [titles].
  static String? _titleOf(String dir, Map<String, Object?> titles) {
    for (var d = dir; ; d = parentOf(d)) {
      if (titles.containsKey(d)) return d;
      if (d.isEmpty) return null;
    }
  }

  /// Finds the nodes and the titles of the layout: the folders of the title
  /// level below known values, and the titles placed too high. The issues
  /// of the projects are found per candidate ([_group]).
  Future<void> _scanLayout(List<String> ordered, Layout layout) async {
    final depth = layout.levels.length;
    final qualified = _qualified(depth);
    final skipped = <String>{};
    for (final dir in ordered) {
      if (skipped.any(
        (s) => dir == s || isWithin(dir, s, caseSensitive: true),
      )) {
        continue;
      }
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      final d = segments.length;
      if (d == 0 || d > depth) continue;
      if (!qualified.contains(dir)) {
        // Not a node: no project in or below it, or a reserved folder.
        skipped.add(dir);
        continue;
      }
      if (d < depth && !_isKnown(segments)) {
        final (kind, item) = _levelIssue(segments, layout);
        skipped.add(dir);
        // A title placed too high stays visible where it is, tagged as at
        // its target (missing levels unassigned), until it is moved.
        if (kind == ReportKind.titleTooHigh) {
          final node = await _node(dir, layout.leaf.key);
          if (node != null && node.level == layout.leaf.key) {
            final tags = layout.tagsOf(item.target!.split('/'))!;
            titles.add(_title(dir, node, tags, await _readVersions(dir)));
          }
        }
        continue;
      }
      final level = layout.levels[d - 1].key;
      final node = await _node(dir, level);
      if (node == null) {
        skipped.add(dir);
        continue;
      }
      if (node.level != level) {
        _issue(
          ReportKind.outsideLayout,
          ReportItem.misplaced(dir, level: layout.levels[d - 1]),
        );
        skipped.add(dir);
        continue;
      }
      if (d == depth) {
        titles.add(
          _title(dir, node, layout.tagsOf(segments)!, await _readVersions(dir)),
        );
      }
    }
  }

  void _issue(ReportKind kind, ReportItem item, {String? candidate}) {
    final map = candidate == null
        ? issues
        : candidateIssues.putIfAbsent(candidate, () => {});
    final list = map.putIfAbsent(kind, () => []);
    if (!list.contains(item)) list.add(item);
  }

  /// Groups the projects into title candidates (SPEC §5.8 step 3), with the
  /// issues of their position and of their folders.
  void _group(Layout layout) {
    for (final MapEntry(key: dir, value: entries) in files.entries) {
      final projects = entries.where(_isProject).toList();
      if (projects.isEmpty || _inReserved(dir)) continue;
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      final (:root, :found) = _place(segments, layout, projects);
      groups.putIfAbsent(root, () => []).addAll(projects);
      for (final (kind, item) in found) {
        _issue(kind, item, candidate: root);
      }
    }
    for (final MapEntry(key: root, value: projects) in groups.entries) {
      if (!shallow.contains(root)) _checkFolders(root, projects, layout);
    }
  }

  /// Root of the candidate of the [projects] of the folder [segments], and
  /// the issues of its position: the first unknown intermediate folder
  /// above it (named after a known value of another level, a title placed
  /// too high, or an unknown value), or projects above the title level.
  /// Every project at or below the title level belongs to that title.
  ({String root, List<(ReportKind, ReportItem)> found}) _place(
    List<String> segments,
    Layout layout,
    List<StorageEntry> projects,
  ) {
    final depth = layout.levels.length;
    var titleDepth = depth;
    final found = <(ReportKind, ReportItem)>[];
    for (var i = 1; i < depth && i <= segments.length; i++) {
      final above = segments.sublist(0, i);
      if (_isKnown(above)) continue;
      final (kind, item) = _levelIssue(above, layout);
      found.add((kind, item));
      titleDepth = switch (kind) {
        // The title lies as far below that folder as below its known place.
        ReportKind.misplacedLevel =>
          depth + i - layout.levels.indexOf(item.level!) - 1,
        ReportKind.titleTooHigh => i,
        _ => depth,
      };
      break;
    }
    if (segments.length < titleDepth) {
      final root = segments.join('/');
      shallow.add(root);
      for (final e in projects) {
        found.add((
          ReportKind.projectTooShallow,
          ReportItem.misplaced(e.path, level: layout.leaf),
        ));
      }
      return (root: root, found: found);
    }
    return (root: segments.take(titleDepth).join('/'), found: found);
  }

  /// Reports the folders of the candidate title folder [root] holding its
  /// [projects]: projects directly in it, member and status subfolders
  /// (`<title>/<member>/…`, `<title>/<status>/…`,
  /// `<title>/<member>/<status>/…`), version folders holding several
  /// projects, and projects below a version folder (SPEC §3.2, §5.8 step
  /// 3). A subfolder is a member folder when named after a declared member,
  /// a status folder when named after a status; any other one is a version
  /// folder.
  void _checkFolders(String root, List<StorageEntry> projects, Layout layout) {
    final versionFolders = <String, List<String>>{};
    for (final e in projects) {
      final folder = parentOf(e.path);
      final rest = folder == root
          ? <String>[]
          : folder.substring(root.isEmpty ? 0 : root.length + 1).split('/');
      var base = root;
      var grouped = false;
      final member = rest.isEmpty ? null : _member(rest.first);
      if (member != null) {
        base = joinPath(base, rest.removeAt(0));
        _issue(
          ReportKind.memberFolder,
          ReportItem(base, member.id),
          candidate: root,
        );
        grouped = true;
      }
      final status = rest.isEmpty ? null : _status(rest.first);
      if (status != null) {
        base = joinPath(base, rest.removeAt(0));
        _issue(
          ReportKind.statusFolder,
          ReportItem(base, status),
          candidate: root,
        );
        grouped = true;
      }
      switch (rest.length) {
        case 0 when !grouped:
          _issue(
            ReportKind.projectInTitleFolder,
            ReportItem(e.path),
            candidate: root,
          );
        case 0:
          break;
        case 1:
          versionFolders
              .putIfAbsent(folder, () => [])
              .add(p.posix.basename(e.path));
        default:
          _issue(
            ReportKind.projectTooDeep,
            ReportItem.misplaced(e.path, level: layout.leaf, target: root),
            candidate: root,
          );
      }
    }
    for (final MapEntry(key: folder, value: names) in versionFolders.entries) {
      if (names.length > 1) {
        _issue(
          ReportKind.severalProjectsInVersion,
          ReportItem(folder, (names..sort()).join('\n')),
          candidate: root,
        );
      }
    }
  }

  /// Declared member named [folder] (ignoring case), if any.
  Member? _member(String folder) => library.members
      .where((m) => m.name.toLowerCase() == folder.toLowerCase())
      .firstOrNull;

  /// Status named by [folder] ([proposeStatus]), if any.
  static String? _status(String folder) =>
      proposeStatus({for (final s in Title.defaultStatuses) s: s}, folder);

  /// Whether the folder [dir] is or lies in a reserved folder.
  static bool _inReserved(String dir) =>
      dir.isNotEmpty && dir.split('/').any(isReservedFolder);

  /// Reads the projects of every candidate (the versions of its title
  /// reused, their file names relative to the same folder), then checks their media; with [statOutside], the references
  /// leaving a candidate are checked with one `stat` each.
  Future<void> _readCandidates({bool statOutside = false}) async {
    final read = {
      for (final t in titles)
        for (final v in t.versions) joinPath(t.path, v.fileName): v,
    };
    for (final MapEntry(key: root, value: projects) in groups.entries) {
      final versions = <Version>[];
      for (final e in projects) {
        // A title is the candidate of its own folder.
        if (read[e.path] case final v?) {
          versions.add(v);
          continue;
        }
        if (corrupted.contains(e.path)) continue;
        try {
          versions.add(await _readVersion(root, parentOf(e.path), e));
        } on Object catch (error) {
          if (!_isCorruption(error)) rethrow;
          corrupted.add(e.path);
        }
      }
      versions.sort((a, b) => a.fileName.compareTo(b.fileName));
      candidateVersions[root] = versions;
      if (statOutside) await _statOutside(root, versions);
      _checkMedia(root, versions);
    }
  }

  /// Reports the projects sharing a version identifier with another one
  /// (manual duplication, SPEC §4.2), the identifier as detail.
  void _findDuplicates() {
    final byId = <VersionId, List<(String, String)>>{};
    for (final MapEntry(key: root, value: versions)
        in candidateVersions.entries) {
      for (final v in versions) {
        if (v.metadata?.id case final id?) {
          byId.putIfAbsent(id, () => []).add((
            root,
            joinPath(root, v.fileName),
          ));
        }
      }
    }
    for (final MapEntry(key: id, value: paths) in byId.entries) {
      if (paths.length < 2) continue;
      for (final (root, path) in paths) {
        _issue(
          ReportKind.duplicateVersionId,
          ReportItem(path, id),
          candidate: root,
        );
      }
    }
  }

  /// Matches the candidates to the titles that know one of their version
  /// identifiers (a project added, moved or changed by hand, SPEC §5.8
  /// step 3): an entry of the node file of another title (statuses, labels
  /// and owners of the versions that no longer exist are kept, SPEC §4.2)
  /// whose candidate has no project with that identifier now. Each such
  /// project is reported, that title as target.
  void _findKnownElsewhere(Layout layout) {
    final present = {
      for (final MapEntry(key: root, value: versions)
          in candidateVersions.entries)
        root: {for (final v in versions) ?v.metadata?.id},
    };
    final knownBy = <String, String>{};
    for (final t in titles..sort((a, b) => a.path.compareTo(b.path))) {
      final node = nodes[t.path];
      if (node == null) continue;
      for (final id in {
        ...node.versionStatuses.keys,
        ...node.versionLabels.keys,
        ...node.versionOwners.keys,
      }) {
        if (present[t.path]?.contains(id) ?? false) continue;
        knownBy.putIfAbsent(id, () => t.path);
      }
    }
    for (final MapEntry(key: root, value: versions)
        in candidateVersions.entries) {
      for (final v in versions) {
        final title = knownBy[v.metadata?.id];
        if (title == null || title == root) continue;
        _issue(
          ReportKind.knownVersionElsewhere,
          ReportItem.misplaced(
            joinPath(root, v.fileName),
            level: layout.leaf,
            target: title,
          ),
          candidate: root,
        );
        matched.putIfAbsent(root, () => title);
      }
    }
  }

  /// Reports the [versions] of the candidate [root] whose media are not
  /// all present in the `Media/` of their folder (outside it, missing,
  /// absolute or outside the library), whose record path is not `Media` or
  /// whose render target is not in `Renders/` (SPEC §4.3, §5.8 step 3).
  void _checkMedia(String root, List<Version> versions) {
    for (final v in versions) {
      final path = joinPath(root, v.fileName);
      final dir = parentOf(path);
      final media = '${joinPath(dir, mediaFolderName)}/'.toLowerCase();
      final renders = joinPath(dir, rendersFolderName).toLowerCase();
      _checkReferences(root, path, v.media, media);
      final record = resolveReference(dir, v.recordPath ?? '');
      if (record?.toLowerCase() != media.substring(0, media.length - 1)) {
        _issue(
          ReportKind.recordPathNotMedia,
          ReportItem(path, v.recordPath ?? ''),
          candidate: root,
        );
      }
      final render = resolveReference(dir, v.renderFile ?? '')?.toLowerCase();
      if (render == null ||
          (render != renders && !render.startsWith('$renders/'))) {
        _issue(
          ReportKind.renderFileForm,
          ReportItem(path, v.renderFile ?? ''),
          candidate: root,
        );
      }
    }
  }

  /// Reports the media [refs] of the project [path] of the candidate
  /// [root] that are outside its [media] folder (lowercase, with a
  /// trailing `/`), missing, absolute or outside the library.
  void _checkReferences(
    String root,
    String path,
    List<String> refs,
    String media,
  ) {
    final outside = <String>[];
    final missing = <String>[];
    final external = <String>[];
    for (final ref in refs) {
      final file = resolveReference(parentOf(path), ref)?.toLowerCase();
      if (file == null) {
        external.add(ref);
      } else if (!existing.contains(file)) {
        missing.add(ref);
      } else if (!file.startsWith(media)) {
        outside.add(ref);
      }
    }
    void report(ReportKind kind, List<String> refs) {
      if (refs.isNotEmpty) {
        _issue(kind, ReportItem(path, refs.join('\n')), candidate: root);
      }
    }

    report(ReportKind.mediaOutsideVersion, outside);
    report(ReportKind.missingMedia, missing);
    report(ReportKind.externalMedia, external);
  }

  /// Versions of the title [dir]: the projects of its subfolders, reserved
  /// ones aside (SPEC §3.2); unreadable ones are reported as corrupted.
  Future<List<Version>> _readVersions(String dir) async {
    final versions = <Version>[];
    for (final folder in _versionFolders(dir)) {
      for (final e in _projects(folder)) {
        try {
          versions.add(await _readVersion(dir, folder, e));
        } on Object catch (error) {
          if (!_isCorruption(error)) rethrow;
          corrupted.add(e.path);
        }
      }
    }
    return versions;
  }

  /// Subfolders of [dir] holding a project, reserved folders aside (a
  /// `Media/` of the former layout is not a version).
  Iterable<String> _versionFolders(String dir) => [
    for (final folder in children[dir] ?? const <String>[])
      if (!isReservedFolder(p.posix.basename(folder)) &&
          _projects(folder).isNotEmpty)
        folder,
  ];

  /// Whether [dir] holds a title: projects in it (former layout) or in
  /// version folders.
  bool _holdsTitle(String dir) =>
      _projects(dir).isNotEmpty || _versionFolders(dir).isNotEmpty;

  /// Whether the intermediate folders [segments] are known values (SPEC
  /// §3.1); always true while the library declares none.
  bool _isKnown(List<String> segments) =>
      library.knownValues.isEmpty || library.knownValues.knows(segments);

  /// Issue of the unknown intermediate folder [segments] (SPEC §5.8), with
  /// the level it is expected at and its proposed target: named after a
  /// single known value elsewhere (moved there), holding projects (a title
  /// placed too high, moved under `_Unassigned` levels), or unknown (value
  /// to declare or folder to move).
  (ReportKind, ReportItem) _levelIssue(List<String> segments, Layout layout) {
    final dir = segments.join('/');
    final d = segments.length;
    final known = library.knownValues.pathsOf(segments.last);
    if (known.length == 1) {
      return (
        ReportKind.misplacedLevel,
        ReportItem.misplaced(
          dir,
          level: layout.levels[known.single.length - 1],
          target: known.single.join('/'),
        ),
      );
    }
    if (_holdsTitle(dir)) {
      return (
        ReportKind.titleTooHigh,
        ReportItem.misplaced(
          dir,
          level: layout.leaf,
          target: [
            ...segments.take(d - 1),
            for (var i = d; i < layout.levels.length; i++) Layout.unassigned,
            segments.last,
          ].join('/'),
        ),
      );
    }
    return (
      ReportKind.unknownValue,
      ReportItem.misplaced(dir, level: layout.levels[d - 1]),
    );
  }

  /// Layout folders, up to [depth], that can be nodes: those holding a
  /// project in them or below them, and titles whose trash or history
  /// holds one; reserved folders (`Assets/`, `Media/`…) never are, nor is
  /// anything below them (#54).
  Set<String> _qualified(int depth) {
    final qualified = <String>{};
    void addWithParents(String dir) {
      for (var d = dir; qualified.add(d) && d.isNotEmpty; d = parentOf(d)) {}
    }

    for (final MapEntry(key: dir, value: entries) in files.entries) {
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      if (!entries.any(_isProject) || _isReserved(segments, depth)) continue;
      addWithParents(dir);
    }
    for (final dir in traces) {
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      if (segments.length == depth && !_isReserved(segments, depth)) {
        addWithParents(dir);
      }
    }
    return qualified;
  }

  /// Whether the folder [segments] is or lies in a reserved folder: a layout
  /// level named like one, a reserved folder at the place of a version
  /// folder (at [depth]) or of a version (one level below).
  static bool _isReserved(List<String> segments, int depth) =>
      segments.take(depth).any(isReservedFolder) ||
      (segments.length > depth && isReservedFolder(segments[depth])) ||
      (segments.length > depth + 1 &&
          isReservedVersionFolder(segments[depth + 1]));

  /// Version without project data (free tree projects are never read).
  static Version _version(String dir, StorageEntry e) => Version(
    fileName: e.path.substring(dir.isEmpty ? 0 : dir.length + 1),
    modified: e.modified,
    size: e.size,
    sizes: {SizeCategory.project: e.size},
  );

  /// The title [dir]; the label and owner of its adopted versions are read
  /// from [node] at every scan, the label falling back to the version folder
  /// name (the file name without its extension in a free tree, SPEC §4.2).
  Title _title(
    String dir,
    NodeFile node,
    Map<String, String> tags,
    List<Version> versions,
  ) {
    versions.sort((a, b) => a.fileName.compareTo(b.fileName));
    return Title(
      id: node.id,
      libraryId: library.id,
      path: dir,
      tags: tags,
      versions: [
        for (final v in versions)
          if (v.metadata case final m?)
            v.withMetadata(
              VersionMetadata(
                id: m.id,
                label:
                    node.versionLabels[m.id] ??
                    v.folder ??
                    p.posix.basenameWithoutExtension(v.fileName),
                owner: node.versionOwners[m.id] as MemberId?,
              ),
            )
          else
            v,
      ],
      versionStatuses: node.versionStatuses,
    );
  }

  /// Version of the project [e] in the version folder [folder] of the title
  /// [dir], with its size, metadata, tempo, sample rate, length, counts and
  /// plugins; its project data reused from the previous scan if unchanged.
  Future<Version> _readVersion(
    String dir,
    String folder,
    StorageEntry e,
  ) async {
    final name = p.posix.basename(folder);
    final bytes = sizes[folder] ?? const <SizeCategory, int>{};
    if (previous.stamps[e.path] == stamps[e.path]) {
      if (previousVersions[e.path] case final v?) {
        return v.withSizes(name, bytes);
      }
    }
    final (:text, encoding: _) = await readProject(storage, e.path);
    final project = RppProject.parse(text);
    final base = _version(dir, e);
    return Version(
      fileName: base.fileName,
      modified: base.modified,
      size: 0,
      sampleRate: project.sampleRate,
      metadata: VersionMetadata.fromExtState(
        project.extState(VersionMetadata.section),
      ),
      tempo: project.tempo,
      length: project.length,
      trackCount: project.tracks.length,
      itemCount: project.itemCount,
      plugins: [
        for (final p in project.allPlugins)
          PluginRef(kind: p.kind, name: p.name, identifier: p.identifier),
      ],
      media: project.mediaFiles,
      recordPath: project.recordPath,
      renderFile: project.renderFile,
    ).withSizes(name, bytes);
  }

  /// Node file of [dir], written with [level] if missing and [writeNodes];
  /// null if missing without [writeNodes], or unreadable (the file then
  /// reported as corrupted).
  Future<NodeFile?> _node(String dir, String level) async {
    final path = joinPath(dir, nodeFileName);
    final entry = files[dir]?.where((e) => e.path == path).firstOrNull;
    NodeFile? node;
    if (entry != null) {
      node = previous.stamps[path] == stamps[path] ? previous.nodes[dir] : null;
      if (node == null) {
        try {
          final text = await utf8.decodeStream(storage.read(path));
          node = NodeFile.fromJson((jsonDecode(text) as Map).cast());
        } on Object catch (error) {
          if (!_isCorruption(error)) rethrow;
          corrupted.add(path);
          return null;
        }
      }
    } else {
      if (!writeNodes) return null;
      node = NodeFile(NodeId.generate(), level);
      await writeNodeFile(storage, dir, node);
      final written = await storage.stat(path);
      if (written != null) stamps[path] = _stamp(written);
    }
    nodes[dir] = node;
    return node;
  }

  Iterable<StorageEntry> _projects(String dir) =>
      (files[dir] ?? const []).where(_isProject);

  static bool _isProject(StorageEntry e) => isProjectFile(e.path);

  /// Read failure (I/O error) or invalid content (bad syntax or JSON shape).
  static bool _isCorruption(Object error) =>
      error is IOException || error is FormatException || error is TypeError;

  static FileStamp _stamp(StorageEntry e) =>
      (size: e.size, modified: e.modified);

  static int _depth(String dir) =>
      dir.isEmpty ? 0 : '/'.allMatches(dir).length + 1;
}
