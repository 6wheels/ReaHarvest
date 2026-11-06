import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// A labelled form row: fixed-width label, then the field.
class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.label,
    required this.child,
    this.alignTop = false,
  });

  final String label;
  final Widget child;
  final bool alignTop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.m),
    child: Row(
      crossAxisAlignment: alignTop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: Padding(
            padding: EdgeInsets.only(top: alignTop ? Space.s : 0),
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ],
    ),
  );
}

/// A path shown with a "Choose…" button and, when [onReset] is set, a
/// reset-to-default button.
class PathRow extends StatelessWidget {
  const PathRow({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onChoose,
    this.onReset,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onChoose;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final style = Theme.of(context).textTheme.bodyMedium;
    final path = value;
    return FormRow(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: path == null
                ? Text(placeholder, style: style?.copyWith(color: c.muted))
                : Tooltip(
                    message: path,
                    child: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
          ),
          if (onReset case final reset?)
            IconButton(
              tooltip: l10n.resetToDefault,
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: reset,
            ),
          const SizedBox(width: Space.xs),
          OutlinedButton(onPressed: onChoose, child: Text(l10n.choose)),
        ],
      ),
    );
  }
}
