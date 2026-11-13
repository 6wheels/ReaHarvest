import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/reaper_actions.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../widgets.dart';

/// Backup points of a version: open and restore (SPEC §5.4).
class History extends ConsumerWidget {
  const History(this.title, this.version, this.id, {super.key});

  final Title title;
  final Version version;
  final VersionId id;

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    Backup backup,
    String date,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestored)));
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Backup backup) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await ref
          .read(reaperActionsProvider)
          .openBackup(title, backup);
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.reaperNotFound)));
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(l10n, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final backups =
        ref.watch(historyProvider(title.id)).value?[id] ?? const <Backup>[];
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
              const Icon(Icons.history_rounded, size: 16),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(format.format(b.created), style: text.bodyMedium),
              ),
              IconButton(
                tooltip: l10n.openInReaper,
                onPressed: () => _open(context, ref, b),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
              ),
              TextButton(
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
