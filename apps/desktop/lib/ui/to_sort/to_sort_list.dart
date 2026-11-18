import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';

import '../../l10n/app_localizations.dart';
import '../../state/tasks.dart';
import '../../state/migration_actions.dart';
import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../layout_labels.dart';
import '../report_dialog.dart';
import '../widgets.dart';
import 'to_sort_item.dart';

/// Issues on the media, record path or render target of a project, whose
/// detail lists the references or the value (one per line).
const _mediaKinds = {
  ReportKind.mediaOutsideVersion,
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

/// Issues of the libraries by kind. Their fixes are offered per title
/// candidate by the page of #149.
class _ToSortListState extends ConsumerState<ToSortList> {
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
          SectionLabel(
            '${reportKindLabel(l10n, kind)} · ${byKind[kind]!.length}',
          ),
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
    return Item(
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
        ReportKind.orphanNode => OutlinedButton(
          onPressed: () => _deleteOrphan(context, ref, issue),
          child: Text(l10n.deleteOrphanNode),
        ),
        _ => null,
      },
    );
  }

  Future<void> _deleteOrphan(
    BuildContext context,
    WidgetRef ref,
    LibraryIssue issue,
  ) async {
    final path = issue.item.path;
    final l10n = AppLocalizations.of(context);
    final tasks = ref.read(tasksProvider.notifier);
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
      tasks.notify(failureMessage(l10n, error), level: NoticeLevel.error);
    }
  }
}
