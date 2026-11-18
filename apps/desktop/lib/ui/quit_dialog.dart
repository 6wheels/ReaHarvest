import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/tasks.dart';
import 'glass_dialog.dart';
import 'tasks_zone.dart' show appNavigatorKey;

/// Lists the [tasks] that run or wait and asks whether to cancel them and
/// quit (SPEC §5.1). False when the user keeps the application running.
Future<bool> confirmQuit(List<BackgroundTask> tasks) async {
  final context = appNavigatorKey.currentContext;
  if (context == null) return true;
  final cancel = await showGlassDialog<bool>(
    context,
    (_) => QuitDialog(tasks),
  );
  return cancel ?? false;
}

class QuitDialog extends StatelessWidget {
  const QuitDialog(this.tasks, {super.key});

  final List<BackgroundTask> tasks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.quitTasksTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.quitTasksBody),
          const SizedBox(height: 12),
          for (final t in tasks) Text('• ${t.label(l10n)}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.keepRunning),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.cancelTasksAndQuit),
        ),
      ],
    );
  }
}
