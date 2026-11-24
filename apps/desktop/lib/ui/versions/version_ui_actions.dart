import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/tasks.dart';
import '../../state/version_actions.dart';
import '../formats.dart';
import '../kit/kit.dart';
import '../project_actions.dart';

/// Asks to confirm [action]; [danger] marks an action that moves or deletes
/// several things at once.
Future<bool?> confirm(
  BuildContext context, {
  required String title,
  required String content,
  required String action,
  String? cancel,
  bool danger = false,
}) {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  return showGlassDialog<bool>(
    context,
    (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancel ?? l10n.cancel),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
}

/// Reports the failure [e] of an action in the notification zone; a cancel
/// ([TaskCancelled]) is no failure.
void fail(TasksNotifier tasks, AppLocalizations l10n, Object e) {
  if (e is TaskCancelled) return;
  tasks.notify(failureMessage(l10n, e), level: NoticeLevel.error);
}

/// Sets the [status] of [version] of [title]; failures in the notification
/// zone.
Future<void> setVersionStatusFromUi(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
  String? status,
) async {
  final l10n = AppLocalizations.of(context);
  final tasks = ref.read(tasksProvider.notifier);
  try {
    await ref.read(versionActionsProvider).setStatusOf(title, version, status);
  } on Object catch (e) {
    fail(tasks, l10n, e);
  }
}

/// Moves [version] of [title] to the trash, after confirmation and the
/// REAPER warning.
Future<void> deleteVersionFromUi(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final l10n = AppLocalizations.of(context);
  final tasks = ref.read(tasksProvider.notifier);
  final confirmed = await confirm(
    context,
    title: l10n.deleteVersionTitle(versionName(version)),
    content: l10n.deleteVersionHint,
    action: l10n.deleteVersion,
  );
  if (confirmed != true || !context.mounted) return;
  final done = await runProjectChange(
    context,
    ref,
    () => ref.read(versionActionsProvider).trashVersion(title, version),
  );
  if (done) {
    tasks.notify(l10n.versionDeleted);
  }
}

/// Moves every other version of [title] than [version] to the trash, after
/// one confirmation and the REAPER warning (SPEC §5.4).
Future<void> keepOnlyVersionFromUi(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final l10n = AppLocalizations.of(context);
  final tasks = ref.read(tasksProvider.notifier);
  final confirmed = await confirm(
    context,
    title: l10n.keepOnlyVersionTitle(versionName(version)),
    content: l10n.keepOnlyVersionHint(versionFolderCount(title) - 1),
    action: l10n.keepOnlyVersionAction,
    danger: true,
  );
  if (confirmed != true || !context.mounted) return;
  final done = await runProjectChange(
    context,
    ref,
    () => ref.read(versionActionsProvider).keepOnly(title, version),
  );
  if (done) {
    tasks.notify(l10n.onlyVersionKept);
  }
}
