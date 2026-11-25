import 'package:material_ui/material_ui.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'kit/kit.dart';
import 'layout_labels.dart';

/// Width of the dialog.
const _width = 600.0;

/// Shows [report] of the action [title] (SPEC §5.2): one section per kind of
/// outcome, problems first and expanded, each item with its path.
Future<void> showReport(BuildContext context, String title, Report report) =>
    showGlassDialog(context, (context) => _ReportDialog(title, report));

String _expectedLevelText(AppLocalizations l10n, LayoutLevel level) =>
    '\n${l10n.reportExpectedLevel(layoutLevelLabel(l10n, level))}';

String reportKindLabel(AppLocalizations l10n, ReportKind kind) =>
    switch (kind) {
      ReportKind.scanFailed => l10n.reportScanFailed,
      ReportKind.corrupted => l10n.corruptedTitle,
      ReportKind.fileLost => l10n.reportFileLost,
      ReportKind.fixFailed => l10n.reportFixFailed,
      ReportKind.undoFailed => l10n.reportUndoFailed,
      ReportKind.statusFolderUnmatched => l10n.reportStatusFolderUnmatched,
      ReportKind.targetExists => l10n.reportTargetExists,
      ReportKind.folderMoved => l10n.reportFolderMoved,
      ReportKind.fileRenamed => l10n.reportFileRenamed,
      ReportKind.titleTooHigh => l10n.reportTitleTooHigh,
      ReportKind.misplacedLevel => l10n.reportMisplacedLevel,
      ReportKind.unknownValue => l10n.reportUnknownValue,
      ReportKind.outsideLayout => l10n.reportOutsideLayout,
      ReportKind.projectTooDeep => l10n.reportProjectTooDeep,
      ReportKind.projectTooShallow => l10n.reportProjectTooShallow,
      ReportKind.knownVersionElsewhere => l10n.reportKnownVersionElsewhere,
      ReportKind.projectInTitleFolder => l10n.reportProjectInTitleFolder,
      ReportKind.severalProjectsInVersion =>
        l10n.reportSeveralProjectsInVersion,
      ReportKind.memberFolder => l10n.reportMemberFolder,
      ReportKind.statusFolder => l10n.reportStatusFolder,
      ReportKind.duplicateVersionId => l10n.reportDuplicateVersionId,
      ReportKind.orphanNode => l10n.orphanNodesTitle,
      ReportKind.mediaOutsideVersion => l10n.reportMediaOutsideVersion,
      ReportKind.missingMedia => l10n.reportMissingMedia,
      ReportKind.externalMedia => l10n.reportExternalMedia,
      ReportKind.recordPathNotMedia => l10n.reportRecordPathNotMedia,
      ReportKind.renderFileForm => l10n.reportRenderFileForm,
      ReportKind.referencedByPlugin => l10n.reportReferencedByPlugin,
      ReportKind.libraryUnavailable => l10n.reportLibraryUnavailable,
      ReportKind.libraryScanned => l10n.reportLibraryScanned,
      ReportKind.projectMoved => l10n.reportProjectMoved,
      ReportKind.mediaMoved => l10n.reportMediaMoved,
      ReportKind.mediaCopied => l10n.reportMediaCopied,
      ReportKind.mediaNormalized => l10n.reportMediaNormalized,
      ReportKind.fixUndone => l10n.reportFixUndone,
    };

class _ReportDialog extends StatelessWidget {
  const _ReportDialog(this.title, this.report);

  final String title;
  final Report report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final muted = context.type.caption.copyWith(color: c.muted);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: _width,
        child: report.isEmpty
            ? Text(l10n.reportEmpty, style: muted)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (kind, items) in report.sections)
                      DisclosureTile(
                        initiallyExpanded:
                            kind.level == ReportLevel.error ||
                            kind.level == ReportLevel.warning,
                        // The level as a light: blinking for an error, dark
                        // when skipped, steady otherwise; the sections are in
                        // the order of the levels.
                        leading: SizedBox(
                          width: IconSize.l,
                          child: Center(
                            child: switch (kind.level) {
                              ReportLevel.error => Led(
                                c.ledRed,
                                mode: LedMode.blink,
                              ),
                              ReportLevel.warning => Led(c.ledAmber),
                              ReportLevel.skipped => Led(c.muted, lit: false),
                              ReportLevel.done => Led(c.ledGreen),
                            },
                          ),
                        ),
                        title: Text(
                          '${reportKindLabel(l10n, kind)} · ${items.length}',
                        ),
                        children: [
                          if (kind == ReportKind.referencedByPlugin)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.xs),
                              child: Text(
                                l10n.reportReferencedByPluginHint,
                                style: muted,
                              ),
                            ),
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.xs),
                              child: SelectableText.rich(
                                TextSpan(
                                  text: item.path,
                                  style: context.type.caption,
                                  children: [
                                    if (item.detail case final detail?)
                                      TextSpan(text: '\n$detail', style: muted),
                                    if (item.level case final level?)
                                      TextSpan(
                                        text: _expectedLevelText(l10n, level),
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
