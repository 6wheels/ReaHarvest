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

/// Existing values of level [i] of [layout] among the [titles] of
/// [libraries], under the values [above] (an empty value matches any).
List<String> levelValues(
  Iterable<Title> titles,
  Set<LibraryId> libraries,
  Layout layout,
  int i,
  List<String> above,
) {
  final keys = [for (final l in layout.levels) l.key];
  return {
    for (final t in titles)
      if (libraries.contains(t.libraryId) &&
          [
            for (final (j, value) in above.indexed)
              value.isEmpty || t.tags[keys[j]] == value,
          ].every((ok) => ok))
        ?t.tags[keys[i]],
  }.toList()..sort();
}

/// Fix proposed for the title [candidate] of a layout [library] (SPEC §5.8
/// step 4, #148): its versions attached to the title it is matched to (one
/// of its versions known by that title), or
/// organized at its layout position (the target of its position issue,
/// else where it is; a candidate placed above the title level gets a new
/// title named after its first project, missing levels unassigned). Each
/// version is pre-filled: label from [node] (the node file of the candidate
/// root), else its file name; folder named after its label; owner from its
/// member subfolder, else from [node], when the library declares members;
/// status from its status subfolder through [statusLabels]
/// ([proposeStatus]), else from [node].
MigrationFix proposeFix(
  ScanCandidate candidate,
  Library library, {
  NodeFile? node,
  Map<String, String> statusLabels = const {},
}) {
  final layout = library.layout!;
  final root = candidate.root;
  final level = layout.leaf.key;
  final versions = [
    for (final v in candidate.versions)
      _version(candidate, v, library, node, statusLabels),
  ];
  final issues = candidate.issues.items;
  final matched = candidate.title != root
      ? candidate.title
      : issues[ReportKind.knownVersionElsewhere]?.firstOrNull?.target;
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
  for (final kind in [ReportKind.titleTooHigh, ReportKind.misplacedLevel]) {
    for (final item in issues[kind] ?? const <ReportItem>[]) {
      if (item.target case final to?
          when root == item.path || isWithin(root, item.path)) {
        target = '$to${root.substring(item.path.length)}';
      }
    }
  }
  return OrganizeTitle(root, target, versions, level: level);
}

FixVersion _version(
  ScanCandidate candidate,
  Version version,
  Library library,
  NodeFile? node,
  Map<String, String> statusLabels,
) {
  final source = joinPath(candidate.root, version.fileName);
  final id = version.metadata?.id;
  final stem = p.posix.basenameWithoutExtension(source);
  final label = node?.versionLabels[id] ?? stem;
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
            switch (node?.versionOwners[id]) {
              final owner? => MemberId(owner),
              null => null,
            };
  return FixVersion(
    source,
    folder: isValidFolderName(label) ? label : stem,
    label: label,
    owner: owner,
    status: statusFolder == null
        ? node?.versionStatuses[id]
        : proposeStatus(statusLabels, statusFolder),
    statusFolder: statusFolder,
  );
}
