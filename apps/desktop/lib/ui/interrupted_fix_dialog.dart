import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/migration_actions.dart';
import 'tasks_zone.dart' show appNavigatorKey;
import 'widgets.dart';

/// Shows, one after the other, the fixes offered to be undone
/// ([interruptedFixesProvider], SPEC §5.8 step 5): "Undo" runs the undo as
/// a task whose report opens at the end, after the REAPER warning (SPEC
/// §5.7); "Later" runs nothing. Takes no room.
class InterruptedFixPrompt extends ConsumerStatefulWidget {
  const InterruptedFixPrompt({super.key});

  @override
  ConsumerState<InterruptedFixPrompt> createState() =>
      _InterruptedFixPromptState();
}

class _InterruptedFixPromptState extends ConsumerState<InterruptedFixPrompt> {
  var _showing = false;

  Future<void> _showNext() async {
    final fix = ref.read(interruptedFixesProvider).firstOrNull;
    final context = appNavigatorKey.currentContext;
    if (_showing || fix == null || context == null) return;
    _showing = true;
    final undo = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.interruptedFixTitle),
          content: Text(l10n.interruptedFixBody(fix.path, fix.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.later),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.undoFix),
            ),
          ],
        );
      },
    );
    _showing = false;
    if (!mounted) return;
    // The next offer, if any, is shown by the listener.
    ref.read(interruptedFixesProvider.notifier).answered(fix.library);
    final navigator = appNavigatorKey.currentContext;
    if ((undo ?? false) && navigator != null && navigator.mounted) {
      await runProjectChange(
        navigator,
        ref,
        () =>
            ref.read(migrationActionsProvider).undoInterruptedFix(fix.library),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(interruptedFixesProvider, (_, _) => _showNext());
    return const SizedBox.shrink();
  }
}
