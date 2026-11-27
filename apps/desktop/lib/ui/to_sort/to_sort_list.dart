import 'package:material_ui/material_ui.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/migration_actions.dart';
import '../../state/navigation.dart';
import '../../state/tasks.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import '../labels.dart';
import '../project_actions.dart';
import '../report_dialog.dart';
import 'candidate_card.dart';
import 'fix_dialog.dart';
import 'move_project_dialog.dart';
import 'outside_file.dart';
import 'to_sort_item.dart';
import 'version_fields.dart';

/// A title candidate of a library, the key of its card.
typedef _CardKey = (LibraryId, String);

/// Statuses of the libraries (SPEC §5.9: the provided list until #47).
Map<String, String> _statuses(AppLocalizations l10n) => {
  for (final s in Title.defaultStatuses) s: statusLabel(l10n, s),
};

/// The card of a title candidate: the candidate, as last scanned, and what
/// the user chose on it. The fix proposed is computed once per scan and
/// per choice of the ancestor move, not at every build.
final class _Choices {
  _Choices(this.library, this.candidate, this.statuses) {
    final proposed = _proposed();
    versions.addAll({for (final v in proposed.versions) v.source: v});
    sameStatus = {for (final v in proposed.versions) v.status}.length <= 1;
    status = proposed.versions.firstOrNull?.status;
  }

  ToSortLibrary library;
  ScanCandidate candidate;
  final Map<String, String> statuses;

  /// The versions with their label, folder, member and status, by source.
  final versions = <String, FixVersion>{};

  /// Whether the misplaced ancestors move along with the title.
  var moveAncestors = true;
  var force = false;

  /// Whether [status] goes to every version.
  late bool sameStatus;
  String? status;

  /// The fix proposed for [candidate], by [moveAncestors].
  final _proposals = <bool, MigrationFix>{};

  /// Takes the [candidate] of a new scan of [library].
  void rescanned(ToSortLibrary library, ScanCandidate candidate) {
    if (identical(candidate, this.candidate)) return;
    this.library = library;
    this.candidate = candidate;
    _proposals.clear();
  }

  MigrationFix _proposed() => _proposals[moveAncestors] ??= proposeFix(
    candidate,
    library.library,
    nodes: library.scan.nodes,
    statusLabels: statuses,
    moveAncestors: moveAncestors,
  );

  /// The fix with the choices of the user.
  MigrationFix fix() {
    final proposed = _proposed();
    return proposed.withChoices(
      versions: [
        for (final v in proposed.versions)
          switch (versions[v.source]) {
            final chosen? when sameStatus => chosen.withChoices(
              folder: chosen.folder,
              label: chosen.label,
              owner: chosen.owner,
              status: status,
            ),
            final chosen? => chosen,
            null => v,
          },
      ],
      force: force,
    );
  }

  /// Whether every version of the fix has a label and a valid folder name.
  bool get isValid => fix().versions.every(
    (v) => v.label.trim().isNotEmpty && isValidFolderName(v.folder),
  );
}

/// The "To sort" page (SPEC §5.2, §5.8 steps 3 and 4): one card per title
/// candidate with a problem, its fix, its versions and their fields; the
/// files outside any title, each attached to a title; the unreadable files,
/// listed only. Cards can be selected ("Fix…" fixes the selected ones, all
/// of them when none is), the selection kept through a rescan for the cards
/// still there. A change on a card rebuilds that card and the counter
/// only.
class ToSortList extends ConsumerStatefulWidget {
  const ToSortList({super.key});

  @override
  ConsumerState<ToSortList> createState() => _ToSortListState();
}

class _ToSortListState extends ConsumerState<ToSortList> {
  final _selected = <_CardKey>{};
  final _choices = <_CardKey, _Choices>{};

  /// Bumped by every change on a card: the counter and "Fix…" follow.
  final _edits = ValueNotifier(0);

  @override
  void dispose() {
    _edits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = context.type.caption.copyWith(color: context.colors.muted);
    final libraries = ref.watch(toSortProvider);
    final multiple = libraries.length > 1;
    final statuses = _statuses(l10n);
    final cards = <Widget>[];
    final shown = <_CardKey, _Choices>{};
    final outside = <Widget>[];
    final unreadable = <Widget>[];
    final others = <Widget>[];
    for (final library in libraries) {
      final id = library.entry.id;
      final name = multiple ? library.entry.displayName : null;
      final scan = library.scan;
      for (final candidate in scan.candidates) {
        if (candidate.issues.isEmpty) continue;
        final key = (id, candidate.root);
        final choices = (_choices[key] ??= _Choices(
          library,
          candidate,
          statuses,
        ))..rescanned(library, candidate);
        shown[key] = choices;
        cards.add(
          _CandidateTile(
            key: ValueKey(key),
            choices: choices,
            library: name,
            selected: _selected.contains(key),
            onSelected: (on) =>
                setState(() => on ? _selected.add(key) : _selected.remove(key)),
            onEdited: () => _edits.value++,
            onMove: (version) => _moveProject(context, choices, version),
          ),
        );
      }
      final titles = [for (final t in scan.titles) t.path]..sort();
      for (final path in [
        for (final i
            in scan.issues.items[ReportKind.fileOutsideTitle] ??
                const <ReportItem>[])
          i.path,
        ...scan.orphanNodes,
      ]..sort()) {
        outside.add(
          OutsideFile(
            key: ValueKey(('outside', id, path)),
            path: path,
            titles: titles,
            library: name,
            onAttach: (title) => _run(context, {
              id: [AttachFile(path, title)],
            }),
          ),
        );
      }
      for (final path in scan.corrupted) {
        unreadable.add(_plain(path, name));
      }
      // Issues of folders outside any candidate (a node file naming
      // another level).
      final inCards = {
        for (final c in scan.candidates)
          for (final (kind, items) in c.issues.sections)
            for (final i in items) (kind, i.path),
      };
      for (final (kind, items) in scan.issues.sections) {
        if (kind == ReportKind.fileOutsideTitle) continue;
        for (final item in items) {
          if (inCards.contains((kind, item.path))) continue;
          others.add(
            _plain(item.path, name, detail: reportKindLabel(l10n, kind)),
          );
        }
      }
    }
    final empty =
        cards.isEmpty &&
        outside.isEmpty &&
        unreadable.isEmpty &&
        others.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        if (!empty) Text(l10n.toSortHint, style: muted),
        if (cards.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          ValueListenableBuilder(
            valueListenable: _edits,
            builder: (context, _, _) => _header(context, shown),
          ),
          ...cards,
        ],
        if (outside.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel('${l10n.outsideFilesTitle} · ${outside.length}'),
          const SizedBox(height: Space.xs),
          Text(l10n.outsideFilesHint, style: muted),
          ...outside,
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel('${l10n.toSort} · ${others.length}'),
          const SizedBox(height: Space.xs),
          Text(l10n.toSortFolderHint, style: muted),
          ...others,
        ],
        if (unreadable.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel('${l10n.corruptedTitle} · ${unreadable.length}'),
          const SizedBox(height: Space.xs),
          Text(l10n.corruptedHint, style: muted),
          ...unreadable,
        ],
      ],
    );
  }

  /// "Select all", the counter and "Fix…" over the [shown] cards: the
  /// selected ones, all of them when none is.
  Widget _header(BuildContext context, Map<_CardKey, _Choices> shown) {
    final l10n = AppLocalizations.of(context);
    final keys = shown.keys.toSet();
    final selected = _selected.intersection(keys);
    final toRun = [
      for (final MapEntry(:key, value: choices) in shown.entries)
        if (selected.isEmpty || selected.contains(key)) (key.$1, choices),
    ];
    final valid = toRun.every((c) => c.$2.isValid);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: Space.m,
          children: [
            Expanded(
              child: CheckRow(
                value: selected.length == keys.length,
                label: l10n.selectAll,
                onChanged: (all) => setState(() {
                  _selected.removeAll(keys);
                  if (all) _selected.addAll(keys);
                }),
              ),
            ),
            Text(
              l10n.selectedCount(selected.length),
              style: context.type.readout,
            ),
            FilledButton(
              onPressed: valid
                  ? () => _run(context, {
                      for (final (library, _) in toRun)
                        library: [
                          for (final (l, choices) in toRun)
                            if (l == library) choices.fix(),
                        ],
                    })
                  : null,
              child: Text(l10n.fixAction),
            ),
          ],
        ),
        if (!valid)
          Text(
            l10n.toSortFixInvalid,
            style: context.type.caption.copyWith(color: context.colors.muted),
          ),
      ],
    );
  }

  /// An entry with no action: its name, its folder and [detail].
  static Widget _plain(String path, String? library, {String? detail}) {
    final folder = p.posix.dirname(path);
    return Item(
      title: p.posix.basename(path),
      subtitle: [?library, if (folder != '.') folder].join(' · '),
      details: [?detail],
    );
  }

  /// Moves the project of [version] to the title the user chooses, after
  /// the preview.
  Future<void> _moveProject(
    BuildContext context,
    _Choices choices,
    FixVersion version,
  ) async {
    final library = choices.library;
    final target = await askProjectTarget(
      context,
      library: library.library,
      titles: library.scan.titles,
      project: p.posix.basename(version.source),
    );
    if (target == null || !context.mounted) return;
    await _run(context, {
      library.entry.id: [
        MoveProject(
          version,
          target,
          level: library.library.layout!.leaf.key,
          force: choices.force,
        ),
      ],
    });
  }

  /// Previews [fixes], then runs them library by library, each batch in
  /// the foreground (SPEC §5.2), once confirmed.
  Future<void> _run(
    BuildContext context,
    Map<LibraryId, List<MigrationFix>> fixes,
  ) async {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.read(tasksProvider.notifier);
    final actions = ref.read(migrationActionsProvider);
    if (!await confirmFixes(context, fixes)) return;
    for (final MapEntry(key: library, value: batch) in fixes.entries) {
      try {
        await actions.fix(library, batch);
      } on Object catch (error) {
        tasks.notify(failureMessage(l10n, error), level: NoticeLevel.error);
      }
    }
  }
}

/// The card of the candidate of [choices]: its own changes rebuild it
/// alone, then [onEdited] tells the page.
class _CandidateTile extends StatefulWidget {
  const _CandidateTile({
    super.key,
    required this.choices,
    required this.library,
    required this.selected,
    required this.onSelected,
    required this.onEdited,
    required this.onMove,
  });

  final _Choices choices;

  /// Name of its library, when several are shown.
  final String? library;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEdited;
  final ValueChanged<FixVersion> onMove;

  @override
  State<_CandidateTile> createState() => _CandidateTileState();
}

class _CandidateTileState extends State<_CandidateTile> {
  void _update(void Function() change) {
    setState(change);
    widget.onEdited();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final choices = widget.choices;
    final candidate = choices.candidate;
    final fix = choices.fix();
    final root = candidate.root;
    final parent = root.isEmpty ? '' : p.posix.dirname(root);
    final moves = proposedMoves(candidate);
    final composed =
        moves.any((m) => m.path == root) && moves.any((m) => m.path != root);
    String move(ReportItem m) => l10n.toSortMove(m.path, m.target!);
    return CandidateCard(
      title: root.isEmpty
          ? choices.library.entry.displayName
          : p.posix.basename(root),
      subtitle: [
        ?widget.library,
        if (parent != '.' && parent.isNotEmpty) parent,
      ].join(' · '),
      issues: [
        for (final (kind, items) in candidate.issues.sections)
          '${reportKindLabel(l10n, kind)} · ${items.length}',
      ],
      fix: switch (fix) {
        AttachVersions(:final target) => l10n.toSortAttach(target),
        _ when fix.target == root => l10n.toSortOrganize,
        _ => l10n.toSortOrganizeAt(fix.target),
      },
      moves: [
        for (final m in moves)
          if (!composed || m.path == root) move(m),
      ],
      ancestorMove: composed
          ? [
              for (final m in moves)
                if (m.path != root) move(m),
            ].join('\n')
          : null,
      moveAncestors: choices.moveAncestors,
      onMoveAncestors: (on) => _update(() => choices.moveAncestors = on),
      selected: widget.selected,
      onSelected: widget.onSelected,
      statuses: choices.statuses,
      sameStatus: choices.sameStatus,
      onSameStatus: (on) => _update(() => choices.sameStatus = on),
      status: choices.status,
      onStatus: (s) => _update(() => choices.status = s),
      force: choices.force,
      onForce: (on) => _update(() => choices.force = on),
      versions: [
        for (final v in fix.versions)
          if (choices.versions[v.source] ?? v case final chosen)
            VersionFields(
              key: ValueKey(chosen.source),
              project: root.isEmpty
                  ? chosen.source
                  : chosen.source.substring(root.length + 1),
              version: chosen,
              members: choices.library.library.members,
              statuses: choices.sameStatus ? null : choices.statuses,
              onChanged: (changed) =>
                  _update(() => choices.versions[changed.source] = changed),
              onMove: () => widget.onMove(chosen),
            ),
      ],
    );
  }
}
