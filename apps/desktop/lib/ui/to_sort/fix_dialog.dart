import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/migration_actions.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import '../report_dialog.dart';

/// Width of the drop-down of a choice.
const _fieldWidth = 200.0;

/// Width of the preview dialog.
const _previewWidth = 640.0;

/// Labeled dropdown of [options] (value -> label).
class Choice<T> extends StatelessWidget {
  const Choice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: _fieldWidth,
          child: Dropdown<T>(
            value: value,
            options: options,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );
}

/// Previews the migration [fixes] of each library (dry run, SPEC §5.8 step
/// 4): the plan of each fix, its counts and operations. Whether the user
/// confirmed them.
Future<bool> confirmFixes(
  BuildContext context,
  Map<LibraryId, List<MigrationFix>> fixes,
) async =>
    await showGlassDialog<bool>(context, (_) => FixPreview(fixes)) ?? false;

/// The preview of [confirmFixes].
class FixPreview extends ConsumerStatefulWidget {
  const FixPreview(this.fixes, {super.key});

  final Map<LibraryId, List<MigrationFix>> fixes;

  @override
  ConsumerState<FixPreview> createState() => _FixPreviewState();
}

class _FixPreviewState extends ConsumerState<FixPreview> {
  final _previews = <PlanPreview>[];

  /// Each fix with its plan, once computed.
  List<(MigrationFix, MediaPlan)>? _plans;
  Object? _error;

  int get _count => widget.fixes.values.fold(0, (n, f) => n + f.length);

  @override
  void initState() {
    super.initState();
    unawaited(_compute());
  }

  /// Computes the plans, library by library.
  Future<void> _compute() async {
    final actions = ref.read(migrationActionsProvider);
    final plans = <(MigrationFix, MediaPlan)>[];
    try {
      for (final MapEntry(key: library, value: fixes) in widget.fixes.entries) {
        final preview = actions.preview(library, fixes);
        _previews.add(preview);
        final byPath = await preview.plans;
        for (final fix in fixes) {
          plans.add((fix, byPath[fix.path]!));
        }
      }
    } on PreviewCancelled {
      return;
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    if (mounted) setState(() => _plans = plans);
  }

  @override
  void dispose() {
    for (final preview in _previews) {
      unawaited(preview.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = context.type.caption.copyWith(color: context.colors.muted);
    final plans = _plans;
    return AlertDialog(
      title: Text(l10n.taskFix(_count)),
      content: SizedBox(
        width: _previewWidth,
        child: switch ((plans, _error)) {
          (_, final error?) => Text(
            l10n.fixPreviewFailed('$error'),
            style: muted,
          ),
          (null, _) => BusyLabel(l10n.fixPreviewLoading, busy: true),
          (final plans?, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final (fix, plan) in plans) _PlanTile(fix, plan)],
            ),
          ),
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: plans == null
              ? null
              : () => Navigator.of(context).pop(true),
          child: Text(l10n.taskFix(_count)),
        ),
      ],
    );
  }
}

/// The [plan] of [fix]: its counts, then its operations and what it leaves
/// as it is, collapsed.
class _PlanTile extends StatelessWidget {
  const _PlanTile(this.fix, this.plan);

  final MigrationFix fix;
  final MediaPlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final muted = context.type.caption.copyWith(color: c.muted);
    final counts = countPlan(plan);
    final failed = plan.blocked.items.containsKey(ReportKind.fixFailed);
    final nothing = plan.operations.isEmpty && plan.blocked.isEmpty;
    final lines = [
      for (final op in plan.operations)
        switch (op) {
          MoveFile(:final from, :final to) => l10n.fixOpMove(from, to),
          CopyFile(:final from, :final to) => l10n.fixOpCopy(from, to),
          RewriteProject(:final path) => l10n.fixOpRewrite(path),
          _ => null,
        },
      for (final (kind, items) in plan.blocked.sections)
        for (final item in items)
          l10n.fixOpBlocked(
            reportKindLabel(l10n, kind),
            [item.path, ?item.detail].join(' · '),
          ),
    ].nonNulls;
    return DisclosureTile(
      // Blinking red when it fails, amber when it leaves files as they are,
      // green otherwise.
      leading: SizedBox(
        width: IconSize.l,
        child: Center(
          child: failed
              ? Led(c.ledRed, mode: LedMode.blink)
              : counts.blocked > 0
              ? Led(c.ledAmber)
              : Led(c.ledGreen),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fix.path == fix.target
                ? fix.path
                : l10n.toSortMove(fix.path, fix.target),
          ),
          Text(
            nothing
                ? l10n.fixPreviewNothing
                : [
                    l10n.fixCountMoved(counts.moved),
                    l10n.fixCountCopied(counts.copied),
                    l10n.fixCountRewritten(counts.rewritten),
                    if (counts.blocked > 0)
                      l10n.fixCountBlocked(counts.blocked),
                  ].join(' · '),
            style: muted,
          ),
        ],
      ),
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: SelectableText(line, style: context.type.caption),
          ),
      ],
    );
  }
}
