import 'package:flutter/material.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'report_dialog.dart';
import 'widgets.dart';

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
    ReuseDuplicate(:final from, :final poolFile) => l10n.fixOpReuse(
      _short(poolFile),
      _short(from),
    ),
    RewriteProject(:final path) => l10n.fixOpRewrite(_short(path)),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.colors.muted, height: 1.5);
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
    final summary = lines.isEmpty
        ? l10n.fixPreviewNothing
        : [
            if (counts.moved > 0) l10n.fixCountMoved(counts.moved),
            if (counts.copied > 0) l10n.fixCountCopied(counts.copied),
            if (counts.trashed > 0) l10n.fixCountTrashed(counts.trashed),
            if (counts.renamed > 0) l10n.fixCountRenamed(counts.renamed),
            if (counts.rewritten > 0) l10n.fixCountRewritten(counts.rewritten),
            if (counts.blocked > 0) l10n.fixCountBlocked(counts.blocked),
          ].join(' · ');
    return _Expandable(
      title: title,
      summary: summary,
      lines: [for (final line in lines) Text(line, style: muted)],
    );
  }
}

/// Header showing [title] and [summary], unfolding [lines] below it.
class _Expandable extends StatefulWidget {
  const _Expandable({
    required this.title,
    required this.summary,
    required this.lines,
  });

  final String title;
  final String summary;
  final List<Widget> lines;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canOpen = widget.lines.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(Radii.s),
          onTap: canOpen ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s + 4,
              vertical: Space.s,
            ),
            child: Row(
              children: [
                Disclosure(
                  _open ? Disclosure.down : Disclosure.right,
                  color: canOpen ? null : Colors.transparent,
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.summary,
                        style: context.readout.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  // Aligned with the title, past the triangle.
                  padding: const EdgeInsets.fromLTRB(
                    Space.s + 4 + 18 + Space.s,
                    Space.xs,
                    Space.s + 4,
                    Space.m,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.lines,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
