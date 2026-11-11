import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'library_path.dart';
import 'conventions.dart';
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
    this.subprojects = const {},
    this.freeTree = false,
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

  /// Media references of the projects found in the pool of a title
  /// (subprojects, `<SOURCE RPP_PROJECT`), by path; used to check them
  /// without reading them again when unchanged.
  final Map<String, List<String>> subprojects;

  /// Whether the library is a free tree (SPEC §3.3).
  final bool freeTree;

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
    subprojects: subprojects,
    freeTree: freeTree,
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
}) => Isolate.run(
  () => scan(MountedFolderStorage(root), library, previous: previous),
);

/// Scans a library root following its layout, or as a free tree (SPEC §3).
///
/// Files whose stamp did not change since [previous] are not read again;
/// free tree projects are never read (no metadata, SPEC §3.3). A layout
/// folder is a node only if a project lies in it or below it (outside the
/// reserved title folders), or, for a title, if its trash or history still
/// holds one (#54). Missing `.node.json` files are written for these nodes
/// and for free tree titles, and layout titles without one are scaffolded
/// ([scaffoldTitle]); these are the only writes.
Future<ScanResult> scan(
  RepositoryStorage storage,
  Library library, {
  ScanResult? previous,
}) => _Scanner(storage, library, previous ?? const ScanResult()).run();

final class _Scanner {
  _Scanner(this.storage, this.library, this.previous)
    : previousVersions = {
        for (final t in previous.titles)
          for (final v in t.versions) joinPath(t.path, v.fileName): v,
      };

  final RepositoryStorage storage;
  final Library library;
  final ScanResult previous;
  final Map<String, Version> previousVersions;

  final dirs = <String>{''};
  final files = <String, List<StorageEntry>>{};
  final titles = <Title>[];
  final nodes = <String, NodeFile>{};
  final issues = <ReportKind, List<ReportItem>>{};
  final corrupted = <String>[];
  final stamps = <String, FileStamp>{};
  final subprojects = <String, List<String>>{};

  /// Lowercase paths of every file, excluded ones too, to find missing
  /// media (case-insensitive like Windows and macOS).
  final existing = <String>{};

  /// Folders whose trash or history holds a project.
  final traces = <String>{};

  Future<ScanResult> run() async {
    for (final e in await storage.list('', recursive: true)) {
      final segments = e.path.split('/');
      final parents = segments.sublist(0, segments.length - 1);
      if (!e.isDirectory) existing.add(e.path.toLowerCase());
      if (segments.first == collabFolderName ||
          segments.first == migrationFolderName) {
        continue;
      }
      if (parents.any(isExcludedFolder)) {
        final last = parents.lastOrNull?.toLowerCase();
        if (!e.isDirectory &&
            (last == trashFolderName || last == historyFolderName) &&
            isProjectFile(e.path)) {
          traces.add(parentOf(parentOf(e.path)));
        }
        continue;
      }
      if (e.isDirectory) {
        if (!isExcludedFolder(segments.last)) dirs.add(e.path);
      } else if (!isExcludedFile(segments.last)) {
        files.putIfAbsent(parentOf(e.path), () => []).add(e);
        stamps[e.path] = _stamp(e);
      }
    }
    final ordered = dirs.toList()
      ..sort((a, b) => _depth(a).compareTo(_depth(b)));
    final layout = library.layout;
    if (layout == null) {
      await _scanFreeTree(ordered);
    } else {
      await _scanLayout(ordered, layout);
    }
    final orphanNodes = [
      for (final MapEntry(key: dir, value: entries) in files.entries)
        if (!nodes.containsKey(dir))
          for (final e in entries)
            if (p.posix.basename(e.path) == nodeFileName &&
                !corrupted.contains(e.path))
              e.path,
    ]..sort();
    titles.sort((a, b) => a.path.compareTo(b.path));
    _findDuplicates();
    if (layout != null) {
      for (final t in titles) {
        await _readSubprojects(t.path);
      }
      titles.forEach(_checkMedia);
    }
    corrupted.sort();
    for (final list in issues.values) {
      list.sort((a, b) => a.path.compareTo(b.path));
    }
    return ScanResult(
      titles: titles,
      nodes: nodes,
      issues: Report(issues),
      corrupted: corrupted,
      orphanNodes: orphanNodes,
      stamps: stamps,
      subprojects: subprojects,
      freeTree: layout == null,
    );
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
      _addTitle(dir, node, tags, titleVersions);
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
        // Inside a title (member or status subfolder…): its projects belong
        // to the title.
        if (reservedTitleFolders.contains(segments[depth].toLowerCase())) {
          continue;
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
            _addTitle(dir, node, tags, await _readVersions(dir));
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
      final node = await _node(dir, level, scaffold: d == depth);
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
        _addTitle(
          dir,
          node,
          layout.tagsOf(segments)!,
          await _readVersions(dir),
        );
      }
    }
  }

  void _issue(ReportKind kind, ReportItem item) =>
      issues.putIfAbsent(kind, () => []).add(item);

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

  /// Reads the media references of the projects in the pool of the title
  /// [dir] (subprojects), unless unchanged since the previous scan;
  /// unreadable ones are reported as corrupted.
  Future<void> _readSubprojects(String dir) async {
    final pool = joinPath(dir, mediaFolderName).toLowerCase();
    for (final MapEntry(key: folder, value: entries) in files.entries) {
      if (folder.toLowerCase() != pool) continue;
      for (final e in entries.where(_isProject)) {
        if (previous.stamps[e.path] == stamps[e.path]) {
          if (previous.subprojects[e.path] case final refs?) {
            subprojects[e.path] = refs;
            continue;
          }
        }
        try {
          final text = await storage
              .read(e.path)
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();
          subprojects[e.path] = RppProject.parse(text).mediaFiles;
        } on Object catch (error) {
          if (!_isCorruption(error)) rethrow;
          corrupted.add(e.path);
        }
      }
    }
  }

  /// Reports the versions of [title] whose media are not all present in its
  /// pool (outside `Media/`, missing, absolute or outside the library),
  /// whose record path is not `Media` or whose render target is not in
  /// `Renders/` (SPEC §4.3, §5.8 step 3).
  void _checkMedia(Title title) {
    final dir = title.path;
    final pool = '${joinPath(dir, mediaFolderName)}/'.toLowerCase();
    final renders = joinPath(dir, rendersFolderName).toLowerCase();
    for (final MapEntry(key: path, value: refs) in subprojects.entries) {
      if ('${parentOf(path)}/'.toLowerCase() == pool) {
        _checkReferences(path, refs, pool);
      }
    }
    for (final v in title.versions) {
      final path = joinPath(dir, v.fileName);
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

  /// Versions of the projects in the title [dir]; unreadable ones are
  /// reported as corrupted.
  Future<List<Version>> _readVersions(String dir) async {
    final versions = <Version>[];
    for (final e in _projects(dir)) {
      try {
        versions.add(await _readVersion(dir, e));
      } on Object catch (error) {
        if (!_isCorruption(error)) rethrow;
        corrupted.add(e.path);
      }
    }
    return versions;
  }

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
    if (_projects(dir).isNotEmpty) {
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
  /// holds one; reserved title folders (`Media/`…) never are (#54).
  Set<String> _qualified(int depth) {
    final qualified = <String>{};
    void addWithParents(String dir) {
      for (var d = dir; qualified.add(d) && d.isNotEmpty; d = parentOf(d)) {}
    }

    for (final MapEntry(key: dir, value: entries) in files.entries) {
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      if (!entries.any(_isProject) || segments.take(depth).any(_isReserved)) {
        continue;
      }
      addWithParents(dir);
    }
    for (final dir in traces) {
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      if (segments.length == depth && !segments.any(_isReserved)) {
        addWithParents(dir);
      }
    }
    return qualified;
  }

  static bool _isReserved(String name) =>
      reservedTitleFolders.contains(name.toLowerCase());

  /// Version without project data (free tree projects are never read).
  static Version _version(String dir, StorageEntry e) => Version(
    fileName: e.path.substring(dir.isEmpty ? 0 : dir.length + 1),
    modified: e.modified,
    size: e.size,
  );

  void _addTitle(
    String dir,
    NodeFile node,
    Map<String, String> tags,
    List<Version> versions,
  ) {
    versions.sort((a, b) => a.fileName.compareTo(b.fileName));
    titles.add(
      Title(
        id: node.id,
        libraryId: library.id,
        path: dir,
        tags: tags,
        versions: versions,
        status: node.status,
        versionStatuses: node.versionStatuses,
      ),
    );
  }

  /// Version of the project [e] in the title [dir], with its metadata,
  /// tempo, length, counts and plugins; reused from the previous scan if
  /// unchanged.
  Future<Version> _readVersion(String dir, StorageEntry e) async {
    if (previous.stamps[e.path] == stamps[e.path]) {
      if (previousVersions[e.path] case final v?) return v;
    }
    final text = await storage
        .read(e.path)
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final project = RppProject.parse(text);
    final base = _version(dir, e);
    return Version(
      fileName: base.fileName,
      modified: base.modified,
      size: base.size,
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
    );
  }

  /// Node file of [dir], written with [level] if missing (with the title
  /// folders if [scaffold]); null (and the file reported as corrupted) if
  /// unreadable.
  Future<NodeFile?> _node(
    String dir,
    String level, {
    bool scaffold = false,
  }) async {
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
      if (scaffold) {
        node = await scaffoldTitle(storage, dir, level);
      } else {
        node = NodeFile(NodeId.generate(), level);
        await writeNodeFile(storage, dir, node);
      }
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
