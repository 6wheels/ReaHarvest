import 'package:flutter/material.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'report_dialog.dart';

/// Preview of the media normalization of the title [title] (SPEC §5.8 step
/// 4): the counts of its [plan], and its operations, collapsed by default.
/// Paths are shown relative to the title.
class MediaPlanPreview extends StatelessWidget {
  const MediaPlanPreview({super.key, required this.title, required this.plan});

  final String title;
  final MediaPlan plan;

  String _short(String path) =>
      path.startsWith('$title/') ? path.substring(title.length + 1) : path;

  String _operation(AppLocalizations l10n, MediaOperation op) => switch (op) {
    MoveFile(:final from, :final to) => l10n.fixOpMove(
      _short(from),
      _short(to),
    ),
    CopyFile(:final from, :final to) => l10n.fixOpCopy(
      _short(from),
      _short(to),
    ),
    TrashDuplicate(:final from, :final to, :final poolFile) => l10n.fixOpTrash(
      _short(poolFile),
      _short(from),
      _short(to),
    ),
    RewriteProject(:final path) => l10n.fixOpRewrite(_short(path)),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.colors.muted);
    final counts = countPlan(plan);
    final lines = [
      for (final (kind, items) in plan.blocked.sections)
        for (final item in items)
          l10n.fixOpBlocked(
            reportKindLabel(l10n, kind),
            [
              _short(item.path),
              if (item.detail case final detail?) detail.replaceAll('\n', ', '),
            ].join(' · '),
          ),
      for (final op in plan.operations) _operation(l10n, op),
    ];
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: Space.s),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(title),
      subtitle: Text(
        lines.isEmpty
            ? l10n.fixPreviewNothing
            : l10n.fixPreviewCounts(
                counts.moved,
                counts.copied,
                counts.trashed,
                counts.renamed,
                counts.rewritten,
                counts.blocked,
              ),
        style: muted,
      ),
      children: [for (final line in lines) Text(line, style: muted)],
    );
  }
}
