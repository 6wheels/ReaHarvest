import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:isolate';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'conventions.dart';
import 'mounted_folder_storage.dart';

/// Size and modification time of a file, used to skip unchanged files.
typedef FileStamp = ({int size, DateTime modified});

/// Result of a library root scan.
final class ScanResult {
  const ScanResult({
    this.titles = const [],
    this.nodes = const {},
    this.toSort = const [],
    this.corrupted = const [],
    this.stamps = const {},
  });

  /// Titles found, sorted by path.
  final List<Title> titles;

  /// Node files by folder path (`''` for the root).
  final Map<String, NodeFile> nodes;

  /// Paths of `.RPP` files and folders outside the layout ("To sort",
  /// SPEC §5.2).
  final List<String> toSort;

  /// Paths of unreadable or corrupted `.RPP` and node files. A folder whose
  /// node file is corrupted is not scanned further.
  final List<String> corrupted;

  /// Stamps of all scanned files (excluded files and folders left out), by
  /// path; used to skip unchanged files on the next scan.
  final Map<String, FileStamp> stamps;

  /// Versions without metadata ("To adopt", SPEC §4.2).
  Iterable<(Title, Version)> get toAdopt => [
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
/// Files whose stamp did not change since [previous] are not read again.
/// Missing `.node.json` files are written for layout nodes and free tree
/// titles; this is the only write.
Future<ScanResult> scan(
  RepositoryStorage storage,
  Library library, {
  ScanResult? previous,
}) => _Scanner(storage, library, previous ?? const ScanResult()).run();

final class _Scanner {
  _Scanner(this.storage, this.library, this.previous)
    : previousMetadata = {
        for (final t in previous.titles)
          for (final v in t.versions) _join(t.path, v.fileName): v.metadata,
      };

  final RepositoryStorage storage;
  final Library library;
  final ScanResult previous;
  final Map<String, VersionMetadata?> previousMetadata;

  final dirs = <String>{''};
  final files = <String, List<StorageEntry>>{};
  final titles = <Title>[];
  final nodes = <String, NodeFile>{};
  final toSort = <String>[];
  final corrupted = <String>[];
  final stamps = <String, FileStamp>{};

  Future<ScanResult> run() async {
    for (final e in await storage.list('', recursive: true)) {
      final segments = e.path.split('/');
      final parents = segments.sublist(0, segments.length - 1);
      if (parents.any(isExcludedFolder)) continue;
      if (segments.first == collabFolderName) continue;
      if (e.isDirectory) {
        if (!isExcludedFolder(segments.last)) dirs.add(e.path);
      } else if (!isExcludedFile(segments.last)) {
        files.putIfAbsent(_parent(e.path), () => []).add(e);
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
    titles.sort((a, b) => a.path.compareTo(b.path));
    toSort.sort();
    corrupted.sort();
    return ScanResult(
      titles: titles,
      nodes: nodes,
      toSort: toSort,
      corrupted: corrupted,
      stamps: stamps,
    );
  }

  Future<void> _scanFreeTree(List<String> ordered) async {
    for (final dir in ordered) {
      if (_projects(dir).isEmpty) continue;
      final node = await _node(dir, freeTreeLevel);
      if (node == null) continue;
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      final tags = {
        for (var i = 0; i < segments.length - 1; i++)
          'folder${i + 1}': segments[i],
        if (segments.isNotEmpty) 'title': segments.last,
      };
      await _addTitle(dir, node.id, tags);
    }
  }

  Future<void> _scanLayout(List<String> ordered, Layout layout) async {
    final depth = layout.levels.length;
    final skipped = <String>{};
    for (final dir in ordered) {
      if (skipped.any((s) => _isWithin(dir, s))) continue;
      final segments = dir.isEmpty ? <String>[] : dir.split('/');
      final d = segments.length;
      if (d > depth) {
        // Inside a title: only out-of-place versions matter.
        if (reservedTitleFolders.contains(segments[depth].toLowerCase())) {
          continue;
        }
        toSort.addAll(_projects(dir).map((e) => e.path));
        continue;
      }
      if (d < depth) {
        toSort.addAll(_projects(dir).map((e) => e.path));
        if (d == 0) continue;
      }
      final level = layout.levels[d - 1].key;
      final node = await _node(dir, level);
      if (node == null) {
        skipped.add(dir);
        continue;
      }
      if (node.level != level) {
        toSort.add(dir);
        skipped.add(dir);
        continue;
      }
      if (d == depth) await _addTitle(dir, node.id, layout.tagsOf(segments)!);
    }
  }

  Future<void> _addTitle(
    String dir,
    NodeId id,
    Map<String, String> tags,
  ) async {
    final versions = <Version>[];
    for (final e in _projects(dir)) {
      final VersionMetadata? metadata;
      try {
        metadata = await _metadata(e);
      } on Object catch (error) {
        if (!_isCorruption(error)) rethrow;
        corrupted.add(e.path);
        continue;
      }
      versions.add(
        Version(
          fileName: e.path.substring(dir.isEmpty ? 0 : dir.length + 1),
          modified: e.modified,
          size: e.size,
          metadata: metadata,
        ),
      );
    }
    versions.sort((a, b) => a.fileName.compareTo(b.fileName));
    titles.add(
      Title(
        id: id,
        libraryId: library.id,
        path: dir,
        tags: tags,
        versions: versions,
      ),
    );
  }

  Future<VersionMetadata?> _metadata(StorageEntry e) async {
    if (previous.stamps[e.path] == stamps[e.path] &&
        previousMetadata.containsKey(e.path)) {
      return previousMetadata[e.path];
    }
    final text = await storage
        .read(e.path)
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final values = RppProject.parse(text).extState(VersionMetadata.section);
    return VersionMetadata.fromExtState(values);
  }

  /// Node file of [dir], written with [level] if missing; null (and the file
  /// reported as corrupted) if unreadable.
  Future<NodeFile?> _node(String dir, String level) async {
    final path = _join(dir, nodeFileName);
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
      node = NodeFile(NodeId.generate(), level);
      final json = jsonEncode(node.toJson());
      await storage.write(path, Stream.value(utf8.encode('$json\n')));
      final written = await storage.stat(path);
      if (written != null) stamps[path] = _stamp(written);
    }
    nodes[dir] = node;
    return node;
  }

  Iterable<StorageEntry> _projects(String dir) =>
      (files[dir] ?? const []).where((e) => isProjectFile(e.path));

  /// Read failure (I/O error) or invalid content (bad syntax or JSON shape).
  static bool _isCorruption(Object error) =>
      error is IOException || error is FormatException || error is TypeError;

  static FileStamp _stamp(StorageEntry e) =>
      (size: e.size, modified: e.modified);

  static String _join(String dir, String name) =>
      dir.isEmpty ? name : '$dir/$name';

  static String _parent(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static int _depth(String dir) =>
      dir.isEmpty ? 0 : '/'.allMatches(dir).length + 1;

  static bool _isWithin(String dir, String parent) =>
      dir == parent || dir.startsWith('$parent/');
}
