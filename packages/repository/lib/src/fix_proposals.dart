import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'fixes.dart';

/// Issue kinds fixed in batch from the "To sort" page (SPEC §5.8 step 4).
const batchFixKinds = {
  ReportKind.titleTooHigh,
  ReportKind.misplacedLevel,
  ReportKind.unknownValue,
  ReportKind.projectTooDeep,
  ...normalizeKinds,
};

/// Issue kinds fixed by normalizing the media of the title of the project
/// (#69): the whole title is fixed at once, its media being shared.
const normalizeKinds = {
  ReportKind.mediaOutsidePool,
  ReportKind.recordPathNotMedia,
};

/// Title folder of the project [path] whose media are to normalize: its
/// folder, or the title of the pool holding it (a subproject).
String mediaTitleOf(String path) {
  final dir = p.posix.dirname(path);
  return p.posix.basename(dir).toLowerCase() == 'media'
      ? p.posix.dirname(dir)
      : dir;
}

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

/// Whether moving the folder [path] of [library] to [target] merges it
/// with an existing folder (#81): [target] holds titles of [library].
/// Compared case-insensitively, like Windows paths.
bool mergesInto(
  Iterable<Title> titles,
  LibraryId library,
  String path,
  String target,
) {
  final folder = target.toLowerCase();
  if (folder == path.toLowerCase()) return false;
  return titles.any((t) {
    final title = t.path.toLowerCase();
    return t.libraryId == library &&
        (title == folder || title.startsWith('$folder/'));
  });
}

/// An issue to fix: the report item of a library.
typedef FixIssue = ({LibraryId library, ReportItem item});

/// What is proposed for one issue. Folder kinds have a [target] and
/// [levels] (the proposed values of the levels above the folder); a
/// project too deep has the other fields; a normalization has none.
typedef FixProposal = ({
  FixIssue issue,

  /// Proposed target path: folder kinds, and the title of a lifted project.
  String? target,

  /// Proposed values of the levels above the folder; empty if not a folder.
  List<String> levels,

  /// Lift: member of the member subfolder.
  Member? member,

  /// Lift: status subfolder.
  String? statusFolder,

  /// Lift: status proposed from the status subfolder.
  String? status,

  /// Whether moving the folder to [target] merges it with an existing one.
  bool merges,

  /// Lift: label of the version, the free file name without its extension.
  String? label,
});

/// Proposals for the issues of one kind. [layout] is that of the first
/// issue's library (folder kinds). [commonValues] holds, for each level
/// above the leaf, the value proposed for every item, or null if they
/// differ. [members] are the members each library declares; [owners]
/// all of them; [owner] is the default owner, null when no library
/// declares members; [local] the local member.
typedef FixProposals = ({
  List<FixProposal> items,
  Layout? layout,
  int? level,
  List<String?> commonValues,
  Map<LibraryId, List<Member>> members,
  List<Member> owners,
  MemberId? owner,
  MemberId? local,
});

/// Choices of the user: the checked items (indexes in the proposals), the
/// values of the levels (empty or missing keeps each proposal), the
/// default owner, and the status chosen for each status subfolder.
typedef FixChoices = ({
  Set<int> checked,
  List<String> levelValues,
  MemberId? owner,
  Map<String, String?> statuses,
});

/// Proposals for [issues], all of [kind] (SPEC §5.8 step 4). [level] is the
/// level of the unknown folders (index in the layout), the level of their
/// item if null. [libraries] and [titles] are the indexed ones;
/// [statusLabels] maps the statuses of the libraries to their label;
/// [identity] is the local member.
FixProposals proposeFixes(
  ReportKind kind,
  List<FixIssue> issues, {
  required Map<LibraryId, Library> libraries,
  required Iterable<Title> titles,
  required Map<String, String> statusLabels,
  MemberId? identity,
  int? level,
}) {
  final folders =
      !normalizeKinds.contains(kind) && kind != ReportKind.projectTooDeep;
  final layout = folders ? libraries[issues.first.library]!.layout! : null;
  final chosen = kind == ReportKind.unknownValue && layout != null
      ? level ?? _levelOf(layout, issues.first.item)
      : null;
  final members = {
    for (final library in {for (final i in issues) i.library})
      library: libraries[library]?.members ?? const <Member>[],
  };
  final owners = {
    for (final list in members.values)
      for (final m in list) m.id: m,
  }.values.toList();
  final owner = owners.any((m) => m.id == identity)
      ? identity
      : owners.firstOrNull?.id;
  final items = [
    for (final issue in issues)
      switch (kind) {
        ReportKind.projectTooDeep => _lift(
          issue,
          members[issue.library]!,
          titles,
          statusLabels,
        ),
        _ when normalizeKinds.contains(kind) => (
          issue: issue,
          target: null,
          levels: const <String>[],
          member: null,
          statusFolder: null,
          status: null,
          merges: false,
          label: null,
        ),
        _ => _folder(layout!, issue, chosen, titles),
      },
  ];
  return (
    items: items,
    layout: layout,
    level: chosen,
    commonValues: [
      if (layout != null)
        for (var j = 0; j < layout.levels.length - 1; j++)
          _common([
            for (final item in items)
              if (j < item.levels.length) item.levels[j],
          ]),
    ],
    members: members,
    owners: owners,
    owner: owner,
    local: identity,
  );
}

String? _common(List<String> values) {
  final distinct = values.toSet();
  return distinct.length == 1 ? distinct.single : null;
}

/// Index in [layout] of the level of the folder [item].
int _levelOf(Layout layout, ReportItem item) =>
    layout.levels.indexWhere((l) => l.key == item.level!.key);

FixProposal _folder(
  Layout layout,
  FixIssue issue,
  int? level,
  Iterable<Title> titles,
) {
  final item = issue.item;
  final count = level ?? _levelOf(layout, item);
  final target = item.target?.split('/');
  final List<String> levels;
  if (target != null && target.length == count + 1) {
    levels = target.take(count).toList();
  } else {
    final parents = p.posix.dirname(item.path).split('/')
      ..removeWhere((s) => s == '.');
    levels = [
      for (var j = 0; j < count; j++)
        j < parents.length ? parents[j] : Layout.unassigned,
    ];
  }
  final proposed = _join(levels, item.path);
  return (
    issue: issue,
    target: proposed,
    levels: levels,
    member: null,
    statusFolder: null,
    status: null,
    merges: mergesInto(titles, issue.library, item.path, proposed),
    label: null,
  );
}

String _join(List<String> levels, String path) =>
    [...levels, p.posix.basename(path)].join('/');

FixProposal _lift(
  FixIssue issue,
  List<Member> members,
  Iterable<Title> titles,
  Map<String, String> statusLabels,
) {
  final item = issue.item;
  final title = item.target!;
  final folder = p.posix.dirname(item.path);
  final segments = folder.substring(title.length + 1).split('/');
  final member = members
      .where((m) => m.name.toLowerCase() == segments.first.toLowerCase())
      .firstOrNull;
  final statusFolder =
      (member == null ? segments : segments.skip(1)).lastOrNull;
  return (
    issue: issue,
    target: title,
    levels: const [],
    member: member,
    statusFolder: statusFolder,
    status: statusFolder == null
        ? null
        : proposeStatus(statusLabels, statusFolder),
    merges: false,
    label: _freeLabel(titles, issue.library, title, item.path),
  );
}

/// File name without extension that [path] gets in the indexed title
/// [title]: the same name, or `name (n)` if a version already has it (as
/// `freePath`, names compared ignoring case).
String _freeLabel(
  Iterable<Title> titles,
  LibraryId library,
  String title,
  String path,
) {
  final taken = {
    for (final t in titles)
      if (t.libraryId == library && t.path.toLowerCase() == title.toLowerCase())
        for (final v in t.versions) v.fileName.toLowerCase(),
  };
  final stem = p.posix.basenameWithoutExtension(path);
  final ext = p.posix.extension(path);
  for (var i = 1; ; i++) {
    final name = i == 1 ? stem : '$stem ($i)';
    if (!taken.contains('$name$ext'.toLowerCase())) return name;
  }
}

/// Target of the folder [proposal] under the chosen [levelValues]: each
/// non-empty value replaces the proposed one of its level.
String folderTarget(FixProposal proposal, List<String> levelValues) => _join([
  for (final (j, value) in proposal.levels.indexed)
    j < levelValues.length && levelValues[j].trim().isNotEmpty
        ? levelValues[j].trim()
        : value,
], proposal.issue.item.path);

/// Owner of the lifted project [proposal]: its member subfolder, else the
/// [chosen] default owner when its library declares it, else the local
/// member if declared, else its first member; none when its library
/// declares no members.
Member? liftOwner(
  FixProposals proposals,
  FixProposal proposal,
  MemberId? chosen,
) {
  final members = proposals.members[proposal.issue.library] ?? const [];
  if (members.isEmpty) return null;
  Member? find(MemberId? id) => members.where((m) => m.id == id).firstOrNull;
  return proposal.member ??
      find(chosen) ??
      find(proposals.local) ??
      members.first;
}

/// Fixes of the checked items, by library, in order: one normalization per
/// title.
Map<LibraryId, List<MigrationFix>> buildFixes(
  ReportKind kind,
  FixProposals proposals,
  FixChoices choices,
) {
  final fixes = <LibraryId, List<MigrationFix>>{};
  for (final i in choices.checked.toList()..sort()) {
    final proposal = proposals.items[i];
    final item = proposal.issue.item;
    final MigrationFix fix;
    if (normalizeKinds.contains(kind)) {
      fix = NormalizeMedia(mediaTitleOf(item.path));
    } else if (kind == ReportKind.projectTooDeep) {
      final folder = proposal.statusFolder;
      final status = folder == null ? null : choices.statuses[folder];
      fix = LiftProject(
        item.path,
        item.target!,
        owner: liftOwner(proposals, proposal, choices.owner)?.id,
        status: status,
        statusFolder: status == null ? folder : null,
      );
    } else {
      fix = MoveFolder(item.path, folderTarget(proposal, choices.levelValues));
    }
    final list = fixes.putIfAbsent(proposal.issue.library, () => []);
    if (fix is NormalizeMedia && list.any((f) => f.path == fix.path)) continue;
    list.add(fix);
  }
  return fixes;
}
