import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'conventions.dart';
import 'fixes.dart';
import 'library_path.dart';
import 'node_file.dart';
import 'scanner.dart' show ScanCandidate;

/// Status of the library deduced from the status subfolder [folder]: the
/// status whose key or label (in [statusLabels], key to label) equals it,
/// or starts with it (e.g. `mix`); null if none.
String? proposeStatus(Map<String, String> statusLabels, String folder) {
  final name = folder.toLowerCase();
  for (final MapEntry(key: status, value: text) in statusLabels.entries) {
    final label = text.toLowerCase();
    if (name == status || name == label) return status;
    if (name.length >= 3 &&
        (status.startsWith(name) || label.startsWith(name))) {
      return status;
    }
  }
  return null;
}

/// Fix proposed for the title [candidate] of a layout [library] (SPEC §5.8
/// step 4, #148): its versions attached to the title it is matched to (one
/// of its versions known by that title), or
/// organized at its layout position (the target of its position issue,
/// else where it is; a candidate placed above the title level gets a new
/// title named after its first project, missing levels unassigned; the
/// moves of the folder and of its ancestors composed). Each version is
/// pre-filled from the [nodes] (node files by folder path, as scanned) of
/// the title it is matched to, then of the candidate root: label, else its file
/// name; folder named after its label; owner from its member subfolder,
/// else from the node files, when the library declares members; status
/// from its status subfolder through [statusLabels] ([proposeStatus]), else
/// from the node files. Without [moveAncestors], the moves of the misplaced
/// ancestors of the candidate are left out of its target: only its own
/// move is made ([proposedMoves]).
MigrationFix proposeFix(
  ScanCandidate candidate,
  Library library, {
  Map<String, NodeFile> nodes = const {},
  Map<String, String> statusLabels = const {},
  bool moveAncestors = true,
}) {
  final layout = library.layout!;
  final root = candidate.root;
  final level = layout.leaf.key;
  final issues = candidate.issues.items;
  final matched = candidate.title != root
      ? candidate.title
      : issues[ReportKind.knownVersionElsewhere]?.firstOrNull?.target;
  final known = [?nodes[matched], ?nodes[root]];
  final versions = [
    for (final v in candidate.versions)
      _version(candidate, v, library, known, statusLabels),
  ];
  if (matched != null) {
    return AttachVersions(root, matched, versions, level: level);
  }
  if (issues.containsKey(ReportKind.projectTooShallow)) {
    final segments = root.isEmpty ? <String>[] : root.split('/');
    final name = p.posix.basenameWithoutExtension(
      candidate.versions.first.fileName,
    );
    final target = [
      ...segments,
      for (var i = segments.length; i < layout.levels.length - 1; i++)
        Layout.unassigned,
      name,
    ].join('/');
    return OrganizeTitle(
      root,
      target,
      versions,
      level: level,
      titleFolder: false,
    );
  }
  var target = root;
  for (final item in proposedMoves(candidate)) {
    if (!moveAncestors && item.path != root) continue;
    if (target == item.path || isWithin(target, item.path)) {
      target = '${item.target}${target.substring(item.path.length)}';
    }
  }
  return OrganizeTitle(root, target, versions, level: level);
}

/// Moves of the folder of [candidate] and of its misplaced ancestors that
/// make its target (SPEC §5.8 step 4), the deepest first (those of its
/// ancestors keep its place in them): each item a folder and its target. A
/// move whose folder is above the candidate root is the move of an
/// ancestor, which the user may leave out ([proposeFix]).
List<ReportItem> proposedMoves(ScanCandidate candidate) {
  final root = candidate.root;
  final issues = candidate.issues.items;
  if (issues.containsKey(ReportKind.projectTooShallow)) return const [];
  return [
    for (final kind in [ReportKind.titleTooHigh, ReportKind.misplacedLevel])
      for (final item in issues[kind] ?? const <ReportItem>[])
        if (item.target != null &&
            (root == item.path || isWithin(root, item.path)))
          item,
  ]..sort((a, b) => b.path.length.compareTo(a.path.length));
}

/// Values suggested for the layout level below the folders [parents] of
/// [library] (SPEC §5.8 step 4): its known values there and the folders at
/// that place of its indexed [titles] (titles of other libraries and titles
/// out of the layout depth left out), each once ignoring case, in its first
/// spelling, sorted.
List<String> levelSuggestions(
  Library library,
  List<Title> titles,
  List<String> parents,
) {
  final layout = library.layout;
  if (layout == null || parents.length >= layout.levels.length) return [];
  var known = library.knownValues;
  for (final name in parents) {
    known =
        known
            .where((v) => v.value.toLowerCase() == name.toLowerCase())
            .firstOrNull
            ?.children ??
        const [];
  }
  final values = <String, String>{};
  void add(String value) =>
      values.putIfAbsent(value.toLowerCase(), () => value);
  for (final v in known) {
    add(v.value);
  }
  final depth = parents.length;
  for (final t in titles) {
    if (t.libraryId != library.id) continue;
    final segments = t.path.split('/');
    if (segments.length != layout.levels.length) continue;
    var under = true;
    for (var i = 0; i < depth && under; i++) {
      under = segments[i].toLowerCase() == parents[i].toLowerCase();
    }
    if (under) add(segments[depth]);
  }
  return values.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Path of the title of [layout] named by the folder [values] (one per
/// level, trimmed; an empty intermediate value is `_Unassigned`), the
/// target of a project moved (SPEC §5.8 step 4); null if a value cannot
/// name a folder ([isValidFolderName], reserved names aside) or the title
/// name is empty.
String? layoutTarget(Layout layout, List<String> values) {
  if (values.length != layout.levels.length) return null;
  final folders = [
    for (final (i, v) in values.indexed)
      switch (v.trim()) {
        '' when i < values.length - 1 => Layout.unassigned,
        final name => name,
      },
  ];
  if (folders.any((f) => !isValidFolderName(f) || isReservedFolder(f))) {
    return null;
  }
  return folders.join('/');
}

FixVersion _version(
  ScanCandidate candidate,
  Version version,
  Library library,
  List<NodeFile> nodes,
  Map<String, String> statusLabels,
) {
  final source = joinPath(candidate.root, version.fileName);
  final id = version.metadata?.id;
  String? known(Map<String, String> Function(NodeFile) values) =>
      nodes.map((n) => values(n)[id]).nonNulls.firstOrNull;
  final stem = p.posix.basenameWithoutExtension(source);
  final label = known((n) => n.versionLabels) ?? stem;
  // Subfolders between the root and the project.
  final rest = version.fileName.split('/')..removeLast();
  final member = rest.isEmpty
      ? null
      : library.members
            .where((m) => m.name.toLowerCase() == rest.first.toLowerCase())
            .firstOrNull;
  if (member != null) rest.removeAt(0);
  final statusFolder =
      rest.isNotEmpty &&
          Title.defaultStatuses.contains(rest.first.toLowerCase())
      ? rest.first
      : null;
  final owner = library.members.isEmpty
      ? null
      : member?.id ??
            switch (known((n) => n.versionOwners)) {
              final owner? => MemberId(owner),
              null => null,
            };
  return FixVersion(
    source,
    folder: isValidFolderName(label)
        ? label
        : isValidFolderName(stem)
        ? stem
        : 'Version',
    label: label,
    owner: owner,
    status: statusFolder == null
        ? known((n) => n.versionStatuses)
        : proposeStatus(statusLabels, statusFolder),
    statusFolder: statusFolder,
  );
}
