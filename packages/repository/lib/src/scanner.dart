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
  });

  /// Titles found, sorted by path.
  final List<Title> titles;

  /// Node files by folder path (`''` for the root).
  final Map<String, NodeFile> nodes;

  /// `.RPP` files and folders outside the layout, duplicated version
  /// identifiers, and projects whose media, record path or render target
  /// do not follow the title conventions (SPEC §4.3, the references or
  /// value as detail, one per line), by kind ("To sort", SPEC §5.2, §5.8 step 3), each sorted
  /// by path. Misplaced items name their expected level and, when known,
  /// their target: the title of a project too deep, the proposed position
  /// of a folder recognized through the known values. Unknown intermediate
  /// folders are not scanned further, except titles placed too high,
  /// indexed where they are with the tags of their target.
  final Report issues;

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
/// Writes nothing: a title whose node file is missing or unreadable is no
/// longer a title, nor is a folder without a project in it or below it (a
/// free tree title: without a project directly in it). Duplicated version
/// identifiers span titles: they are left to the caller.
Future<TitleScan> scanTitle(
  RepositoryStorage storage,
  Library library,
  Title previous, {
  ScanResult stored = const ScanResult(),
}) => _Scanner(storage, library, stored, null, false).runTitle(previous);

final class _Scanner {
  _Scanner(
    this.storage,
    this.library,
    this.previous,
    this.journalPosition,
    this.writeNodes,
  ) : previousVersions = {
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
  final issues = <ReportKind, List<ReportItem>>{};
  final corrupted = <String>[];
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
    }
    final orphanNodes = _orphanNodes();
    titles.sort((a, b) => a.path.compareTo(b.path));
    _findDuplicates();
    if (layout != null) titles.forEach(_checkMedia);
    _sort();
    return ScanResult(
      titles: titles,
      nodes: nodes,
      issues: Report(issues),
      corrupted: corrupted,
      orphanNodes: orphanNodes,
      stamps: stamps,
      freeTree: layout == null,
      journalPosition: journalPosition,
    );
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
      await _statOutside(title);
      _checkMedia(title);
    }
    final orphanNodes = _orphanNodes();
    _sort();
    return (
      title: title,
      node: nodes[dir],
      stamps: stamps,
      issues: Report(issues),
      corrupted: corrupted,
      orphanNodes: orphanNodes,
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
  /// longer a node of the title level. A title placed too high reports no
  /// project below it, like [_scanLayout].
  Future<Title?> _layoutTitle(Title previous, Layout layout) async {
    final dir = previous.path;
    final depth = layout.levels.length;
    final tooHigh = _depth(dir) < depth;
    if (!_qualified(depth).contains(dir) || (tooHigh && !_holdsTitle(dir))) {
      return null;
    }
    final node = await _node(dir, layout.leaf.key);
    if (node == null || node.level != layout.leaf.key) return null;
    if (!tooHigh) {
      for (final folder in files.keys) {
        final segments = folder.split('/');
        if (segments.length > depth) _reportTooDeep(folder, segments, layout);
      }
    }
    return _title(dir, node, previous.tags, await _readVersions(dir));
  }

  /// Adds to [existing] the files outside the folder of [title] that its
  /// versions refer to, one `stat` per reference.
  Future<void> _statOutside(Title title) async {
    final inside = '${title.path}/'.toLowerCase();
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

    for (final v in title.versions) {
      await check(joinPath(title.path, v.fileName), v.media);
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
    for (final list in issues.values) {
      list.sort((a, b) => a.path.compareTo(b.path));
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
      if (d > 0 && d <= depth && !qualified.contains(dir)) {
        // Not a node: no project in or below it, or a reserved folder.
        skipped.add(dir);
        continue;
      }
      if (d > depth) {
        _reportTooDeep(dir, segments, layout);
        continue;
      }
      if (d > 0 && d < depth && !_isKnown(segments)) {
        final (kind, item) = _levelIssue(segments, layout);
        _issue(kind, item);
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
      if (d < depth) {
        for (final e in _projects(dir)) {
          _issue(
            ReportKind.projectTooShallow,
            ReportItem.misplaced(e.path, level: layout.leaf),
          );
        }
        if (d == 0) continue;
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

  void _issue(ReportKind kind, ReportItem item) =>
      issues.putIfAbsent(kind, () => []).add(item);

  /// Reports the projects of [dir], a folder inside a version folder, as
  /// too deep, their title as target; nothing in a version folder itself
  /// (its projects are versions) nor in a reserved folder (`Assets/`,
  /// `Media/`…).
  void _reportTooDeep(String dir, List<String> segments, Layout layout) {
    final depth = layout.levels.length;
    if (isReservedTitleFolder(segments[depth]) ||
        segments.length == depth + 1 ||
        isReservedVersionFolder(segments[depth + 1])) {
      return;
    }
    for (final e in _projects(dir)) {
      _issue(
        ReportKind.projectTooDeep,
        ReportItem.misplaced(
          e.path,
          level: layout.leaf,
          target: segments.take(depth).join('/'),
        ),
      );
    }
  }

  /// Reports the versions sharing a version identifier with another one
  /// (manual duplication, SPEC §4.2), the identifier as detail.
  void _findDuplicates() {
    for (final MapEntry(key: id, value: versions) in duplicateVersions(
      titles,
    ).entries) {
      for (final (t, v) in versions) {
        _issue(
          ReportKind.duplicateVersionId,
          ReportItem(joinPath(t.path, v.fileName), id),
        );
      }
    }
  }

  /// Reports the versions of [title] whose media are not all present in the
  /// `Media/` of their version folder (outside it, missing, absolute or
  /// outside the library), whose record path is not `Media` or whose render
  /// target is not in `Renders/` (SPEC §4.3, §5.8 step 3).
  void _checkMedia(Title title) {
    for (final v in title.versions) {
      final path = joinPath(title.path, v.fileName);
      final dir = parentOf(path);
      final pool = '${joinPath(dir, mediaFolderName)}/'.toLowerCase();
      final renders = joinPath(dir, rendersFolderName).toLowerCase();
      _checkReferences(path, v.media, pool);
      final record = resolveReference(dir, v.recordPath ?? '');
      if (record?.toLowerCase() != pool.substring(0, pool.length - 1)) {
        _issue(
          ReportKind.recordPathNotMedia,
          ReportItem(path, v.recordPath ?? ''),
        );
      }
      final render = resolveReference(dir, v.renderFile ?? '')?.toLowerCase();
      if (render == null ||
          (render != renders && !render.startsWith('$renders/'))) {
        _issue(ReportKind.renderFileForm, ReportItem(path, v.renderFile ?? ''));
      }
    }
  }

  /// Reports the media [refs] of the project [path] that are outside the
  /// [pool] (lowercase, with a trailing `/`), missing, absolute or outside
  /// the library.
  void _checkReferences(String path, List<String> refs, String pool) {
    final outside = <String>[];
    final missing = <String>[];
    final external = <String>[];
    for (final ref in refs) {
      final file = resolveReference(parentOf(path), ref)?.toLowerCase();
      if (file == null) {
        external.add(ref);
      } else if (!existing.contains(file)) {
        missing.add(ref);
      } else if (!file.startsWith(pool)) {
        outside.add(ref);
      }
    }
    void report(ReportKind kind, List<String> refs) {
      if (refs.isNotEmpty) _issue(kind, ReportItem(path, refs.join('\n')));
    }

    report(ReportKind.mediaOutsidePool, outside);
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
