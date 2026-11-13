import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/migration_actions.dart';
import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../layout_labels.dart';
import '../report_dialog.dart';
import '../widgets.dart';
import 'fix_dialog.dart';
import 'sort_dialog.dart';
import 'to_sort_item.dart';

/// A "To sort" item, as selected: it stays selected through a rescan as
/// long as an issue with the same key is still there.
typedef _Key = (LibraryId, ReportKind, String);

_Key _keyOf(LibraryIssue issue) => (issue.library, issue.kind, issue.item.path);

/// Issues on the media, record path or render target of a project, whose
/// detail lists the references or the value (one per line).
const _mediaKinds = {
  ReportKind.mediaOutsidePool,
  ReportKind.missingMedia,
  ReportKind.externalMedia,
  ReportKind.recordPathNotMedia,
  ReportKind.renderFileForm,
};

class ToSortList extends ConsumerStatefulWidget {
  const ToSortList({super.key});

  @override
  ConsumerState<ToSortList> createState() => _ToSortListState();
}

/// Issues of the libraries by kind, the batch-fixable ones selectable
/// (#82): "Fix…" applies to the selected items of its section, or to all
/// of them when none is selected.
class _ToSortListState extends ConsumerState<ToSortList> {
  final _selected = <_Key>{};

  /// Hint shown under the section of [kind], if any.
  static String? _hint(AppLocalizations l10n, ReportKind kind) =>
      switch (kind) {
        ReportKind.corrupted => l10n.corruptedHint,
        ReportKind.orphanNode => l10n.orphanNodesHint,
        ReportKind.duplicateVersionId => l10n.duplicateVersionIdHint,
        ReportKind.titleTooHigh ||
        ReportKind.misplacedLevel ||
        ReportKind.unknownValue ||
        ReportKind.outsideLayout => l10n.toSortFolderHint,
        _ => null,
      };

  /// Selected items among [issues].
  List<LibraryIssue> _selectedOf(List<LibraryIssue> issues) => [
    for (final i in issues)
      if (_selected.contains(_keyOf(i))) i,
  ];

  /// Selects every item of [issues], or none if all are selected.
  void _toggleAll(List<LibraryIssue> issues) => setState(() {
    final keys = issues.map(_keyOf);
    if (_selectedOf(issues).length == issues.length) {
      _selected.removeAll(keys);
    } else {
      _selected.addAll(keys);
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final issues = ref.watch(issuesProvider);
    final names = {
      for (final l in ref.watch(settingsProvider.select((s) => s.libraries)))
        l.id: l.displayName,
    };
    final multiple = {for (final i in issues) i.library}.length > 1;
    // Sorted by kind within each library: grouped across libraries here.
    final byKind = <ReportKind, List<LibraryIssue>>{};
    for (final i in issues) {
      byKind.putIfAbsent(i.kind, () => []).add(i);
    }
    final kinds = byKind.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    Widget muted(String value, TextStyle? style) =>
        Text(value, style: style?.copyWith(color: c.muted));
    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        if (issues.isNotEmpty) muted(l10n.toSortHint, text.bodyMedium),
        for (final kind in kinds) ...[
          const SizedBox(height: Space.l),
          _sectionHeader(l10n, kind, byKind[kind]!),
          if (_hint(l10n, kind) case final hint?) ...[
            const SizedBox(height: Space.xs),
            muted(hint, text.bodySmall),
          ],
          for (final issue in byKind[kind]!)
            _issueItem(context, ref, issue, multiple ? names : null),
        ],
      ],
    );
  }

  /// Label and counter of the section of [issues], all of [kind]; for a
  /// batch-fixable kind, its "select all" box, the number of selected
  /// items and "Fix…".
  Widget _sectionHeader(
    AppLocalizations l10n,
    ReportKind kind,
    List<LibraryIssue> issues,
  ) {
    final label = SectionLabel(
      '${reportKindLabel(l10n, kind)} · ${issues.length}',
    );
    if (!batchFixKinds.contains(kind)) return label;
    final selected = _selectedOf(issues);
    return Row(
      children: [
        Checkbox(
          tristate: true,
          value: selected.isEmpty
              ? false
              : selected.length == issues.length
              ? true
              : null,
          semanticLabel: l10n.selectAll,
          onChanged: (_) => _toggleAll(issues),
        ),
        Expanded(child: label),
        if (selected.isNotEmpty)
          Text(
            l10n.selectedCount(selected.length),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.colors.muted),
          ),
        TextButton(
          onPressed: () =>
              _fixAll(context, ref, kind, selected.isEmpty ? issues : selected),
          child: Text(l10n.fixAction),
        ),
      ],
    );
  }

  /// Card of [issue]; its library is named when [names] is set (several
  /// libraries have issues).
  Widget _issueItem(
    BuildContext context,
    WidgetRef ref,
    LibraryIssue issue,
    Map<LibraryId, String>? names,
  ) {
    final l10n = AppLocalizations.of(context);
    final ReportItem(:path, :detail, :level, :target) = issue.item;
    // An orphan node file stands for its folder.
    final shown = issue.kind == ReportKind.orphanNode
        ? p.posix.dirname(path)
        : path;
    final folder = p.posix.dirname(shown);
    final key = _keyOf(issue);
    return Item(
      selected: batchFixKinds.contains(issue.kind)
          ? _selected.contains(key)
          : null,
      onSelected: (on) =>
          setState(() => on ? _selected.add(key) : _selected.remove(key)),
      title: p.posix.basename(shown),
      subtitle: [
        if (names != null) ?names[issue.library],
        if (folder != '.') folder,
      ].join(' · '),
      details: [
        if (level != null)
          l10n.issueExpectedLevel(layoutLevelLabel(l10n, level)),
        if (target != null) l10n.issueTarget(target),
        if (_mediaKinds.contains(issue.kind) && detail != null)
          if (detail.isEmpty)
            l10n.issueProjectFolder
          else
            ...detail.split('\n'),
      ],
      action: switch (issue.kind) {
        ReportKind.projectTooDeep ||
        ReportKind.projectTooShallow => OutlinedButton(
          onPressed: () => showSortDialog(
            context,
            library: issue.library,
            path: path,
            target: target,
          ),
          child: Text(l10n.sortAction),
        ),
        ReportKind.titleTooHigh ||
        ReportKind.misplacedLevel ||
        ReportKind.unknownValue ||
        ReportKind.outsideLayout => OutlinedButton(
          onPressed: () => showSortDialog(
            context,
            library: issue.library,
            path: path,
            target: target,
            folderLevel: level,
            chooseLevel: issue.kind == ReportKind.unknownValue,
          ),
          child: Text(l10n.sortAction),
        ),
        ReportKind.orphanNode => OutlinedButton(
          onPressed: () => _deleteOrphan(context, ref, issue),
          child: Text(l10n.deleteOrphanNode),
        ),
        _ => null,
      },
    );
  }

  /// Previews then applies the batch fix of [issues] of [kind], library by
  /// library, after the REAPER warning.
  Future<void> _fixAll(
    BuildContext context,
    WidgetRef ref,
    ReportKind kind,
    List<LibraryIssue> issues,
  ) async {
    final fixes = await showFixDialog(context, kind, issues);
    if (fixes == null || !context.mounted) return;
    await runProjectChange(context, ref, () async {
      for (final MapEntry(key: library, value: list) in fixes.entries) {
        await ref.read(migrationActionsProvider).fix(library, list);
      }
    });
  }

  Future<void> _deleteOrphan(
    BuildContext context,
    WidgetRef ref,
    LibraryIssue issue,
  ) async {
    final path = issue.item.path;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteOrphanNodeTitle),
        content: Text(l10n.deleteOrphanNodeHint(p.posix.dirname(path))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteOrphanNode),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(migrationActionsProvider)
          .deleteOrphanNode(issue.library, path);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(l10n, error))),
      );
    }
  }
}
