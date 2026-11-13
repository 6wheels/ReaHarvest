import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/version_actions.dart';
import '../widgets.dart';

Future<bool?> confirm(
  BuildContext context, {
  required String title,
  required String content,
  required String action,
  String? cancel,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancel ?? l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
}

void fail(ScaffoldMessengerState messenger, AppLocalizations l10n, Object e) =>
    messenger.showSnackBar(SnackBar(content: Text(failureMessage(l10n, e))));

/// Sets the [status] of [version] of [title]; failures in a snackbar.
Future<void> setVersionStatusFromUi(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
  String? status,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(versionActionsProvider).setStatusOf(title, version, status);
  } on Object catch (e) {
    fail(messenger, l10n, e);
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
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await confirm(
    context,
    title: l10n.deleteVersionTitle(p.posix.withoutExtension(version.fileName)),
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
    messenger.showSnackBar(SnackBar(content: Text(l10n.versionDeleted)));
  }
}
