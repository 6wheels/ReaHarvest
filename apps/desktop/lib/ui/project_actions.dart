import 'package:material_ui/material_ui.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/reaper.dart';
import '../state/reaper_actions.dart';
import '../state/tasks.dart';
import 'kit/kit.dart';

/// Runs [change] of a project file, after a confirmation when REAPER is
/// running (SPEC §5.7); failures are reported in the notification zone.
/// Returns whether [change] was done: not on a failure or a cancel.
Future<bool> runProjectChange(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() change,
) async {
  final l10n = AppLocalizations.of(context);
  final tasks = ref.read(tasksProvider.notifier);
  if (await ref.read(reaperRunningProvider)()) {
    if (!context.mounted) return false;
    final confirmed = await showGlassDialog<bool>(
      context,
      (context) => AlertDialog(
        title: Text(l10n.reaperOpenTitle),
        content: Text(l10n.reaperOpenHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.continueAnyway),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }
  try {
    await change();
    return true;
  } on TaskCancelled {
    return false;
  } on Object catch (error) {
    tasks.notify(failureMessage(l10n, error), level: NoticeLevel.error);
    return false;
  }
}

/// Opens [version] of [title] in REAPER; problems are reported in the
/// notification zone.
Future<void> openVersionInReaper(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final l10n = AppLocalizations.of(context);
  final tasks = ref.read(tasksProvider.notifier);
  try {
    if (!await ref.read(reaperActionsProvider).openVersion(title, version)) {
      tasks.notify(l10n.reaperNotFound, level: NoticeLevel.warning);
    }
  } on Object catch (error) {
    tasks.notify(failureMessage(l10n, error), level: NoticeLevel.error);
  }
}

/// Text shown when an action fails with [error].
String failureMessage(AppLocalizations l10n, Object error) => switch (error) {
  ProjectEncodingException() => l10n.projectEncodingFailed,
  SharedVersionFolderException() => l10n.sharedVersionFolder,
  _ => l10n.actionFailed('$error'),
};
