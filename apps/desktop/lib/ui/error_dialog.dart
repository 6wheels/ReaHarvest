import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'tasks_zone.dart';

var _shown = false;

/// Shows the unexpected [error] over the application (SPEC §5.2): its
/// message and selectable stack trace, with "Copy" and "Open the logs". One
/// popup at a time: errors raised while it is open are only logged.
void showErrorDialog(Object error, StackTrace? stack) {
  final context = appNavigatorKey.currentContext;
  if (_shown || context == null) return;
  _shown = true;
  showDialog<void>(
    context: context,
    builder: (_) => ErrorDialog(error, stack),
  ).whenComplete(() => _shown = false);
}

class ErrorDialog extends ConsumerWidget {
  const ErrorDialog(this.error, this.stack, {super.key});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = '$error\n\n${stack ?? ''}'.trimRight();
    return AlertDialog(
      title: Text(l10n.unexpectedError),
      content: SizedBox(
        width: 640,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: SelectableText(detail, style: context.readout),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: detail)),
          child: Text(l10n.copy),
        ),
        TextButton(
          onPressed: () =>
              ref.read(openFolderProvider)(ref.read(logFolderProvider)),
          child: Text(l10n.openLogs),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
