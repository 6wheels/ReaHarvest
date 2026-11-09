import 'package:flutter/material.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'layout_labels.dart';

/// Shows [report] of the action [title] (SPEC §5.2): one section per kind of
/// outcome, problems first and expanded, each item with its path.
Future<void> showReport(BuildContext context, String title, Report report) =>
    showDialog(
      context: context,
      builder: (context) => _ReportDialog(title, report),
    );

String reportKindLabel(AppLocalizations l10n, ReportKind kind) =>
    switch (kind) {
      ReportKind.scanFailed => l10n.reportScanFailed,
      ReportKind.corrupted => l10n.corruptedTitle,
      ReportKind.fileLost => l10n.reportFileLost,
      ReportKind.titleTooHigh => l10n.reportTitleTooHigh,
      ReportKind.misplacedLevel => l10n.reportMisplacedLevel,
      ReportKind.unknownValue => l10n.reportUnknownValue,
      ReportKind.orphanNode => l10n.orphanNodesTitle,
      ReportKind.toSort => l10n.toSort,
      ReportKind.missingMedia => l10n.reportMissingMedia,
      ReportKind.externalMedia => l10n.reportExternalMedia,
      ReportKind.libraryUnavailable => l10n.reportLibraryUnavailable,
      ReportKind.libraryScanned => l10n.reportLibraryScanned,
      ReportKind.projectMoved => l10n.reportProjectMoved,
      ReportKind.mediaMoved => l10n.reportMediaMoved,
      ReportKind.mediaCopied => l10n.reportMediaCopied,
    };

/// Warning color, between the accent and the error.
const _warning = Color(0xFFE0A33B);

class _ReportDialog extends StatelessWidget {
  const _ReportDialog(this.title, this.report);

  final String title;
  final Report report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: c.muted);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 600,
        child: report.isEmpty
            ? Text(l10n.reportEmpty, style: muted)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (kind, items) in report.sections)
                      ExpansionTile(
                        initiallyExpanded:
                            kind.level == ReportLevel.error ||
                            kind.level == ReportLevel.warning,
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(
                          left: Space.l + Space.s,
                          bottom: Space.s,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        shape: const Border(),
                        leading: switch (kind.level) {
                          ReportLevel.error => Icon(
                            Icons.error_outline_rounded,
                            color: theme.colorScheme.error,
                          ),
                          ReportLevel.warning => const Icon(
                            Icons.warning_amber_rounded,
                            color: _warning,
                          ),
                          ReportLevel.skipped => Icon(
                            Icons.remove_circle_outline_rounded,
                            color: c.muted,
                          ),
                          ReportLevel.done => Icon(
                            Icons.check_circle_outline_rounded,
                            color: c.accent,
                          ),
                        },
                        title: Text(
                          '${reportKindLabel(l10n, kind)} · ${items.length}',
                        ),
                        children: [
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.xs),
                              child: SelectableText.rich(
                                TextSpan(
                                  text: item.path,
                                  style: theme.textTheme.bodySmall,
                                  children: [
                                    if (item.detail case final detail?)
                                      TextSpan(text: '\n$detail', style: muted),
                                    if (item.level case final level?)
                                      TextSpan(
                                        text:
                                            '\n${l10n.reportExpectedLevel(layoutLevelLabel(l10n, level))}',
                                        style: muted,
                                      ),
                                    if (item.target case final target?)
                                      TextSpan(
                                        text: '\n${l10n.reportTarget(target)}',
                                        style: muted,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
