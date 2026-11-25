import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/reaper_actions.dart';
import '../../state/tasks.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import '../project_actions.dart';

/// Backup points of a version: open and restore (SPEC §5.4).
class History extends ConsumerWidget {
  const History(this.title, this.version, {super.key});

  final Title title;
  final Version version;

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    Backup backup,
    String date,
  ) async {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.read(tasksProvider.notifier);
    final confirmed = await showGlassDialog<bool>(
      context,
      (context) => AlertDialog(
        title: Text(l10n.restoreTitle),
        content: Text(l10n.restoreHint(date)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final done = await runProjectChange(
      context,
      ref,
      () => ref.read(versionActionsProvider).restore(title, version, backup),
    );
    if (done) {
      tasks.notify(l10n.backupRestored);
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Backup backup) async {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.read(tasksProvider.notifier);
    try {
      final opened = await ref
          .read(reaperActionsProvider)
          .openBackup(title, backup);
      if (!opened) {
        tasks.notify(l10n.reaperNotFound, level: NoticeLevel.warning);
      }
    } on Object catch (error) {
      tasks.notify(failureMessage(l10n, error), level: NoticeLevel.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final backups =
        ref.watch(historyProvider((title.id, version.fileName))).value ??
        const <Backup>[];
    final format = DateFormat.yMMMd(l10n.localeName).add_Hm();
    if (backups.isEmpty) {
      return Text(
        l10n.noBackups,
        style: text.bodyMedium?.copyWith(color: c.muted),
      );
    }
    return Column(
      children: [
        for (final b in backups)
          Row(
            children: [
              const Icon(Icons.history_rounded, size: IconSize.m),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(format.format(b.created), style: text.bodyMedium),
              ),
              IconButton(
                tooltip: l10n.openInReaper,
                onPressed: () => _open(context, ref, b),
                icon: const ReaperIcon(),
              ),
              OutlinedButton(
                onPressed: () =>
                    _restore(context, ref, b, format.format(b.created)),
                child: Text(l10n.restore),
              ),
            ],
          ),
      ],
    );
  }
}
