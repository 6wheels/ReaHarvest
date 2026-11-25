import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/tasks.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../kit/kit.dart';
import '../project_actions.dart';
import 'version_ui_actions.dart';

/// Width of the dialog.
const _width = 440.0;

/// Asks for a new name (of its folder and its `.RPP`) and label of
/// [version] of [title] and applies them. A rename waits for the REAPER
/// warning (SPEC §5.7); a label, stored outside the project, does not (SPEC
/// §4.2). Returns its [Version.fileName], null when cancelled or failed.
Future<String?> showEditVersionDialog(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final values = await showGlassDialog<(String, String)>(
    context,
    (_) => _EditVersionDialog(title, version),
  );
  if (values == null || !context.mounted) return null;
  final (name, label) = values;
  if (name == version.folder && label == (version.metadata?.label ?? '')) {
    return null;
  }
  Future<String?> edit() => ref
      .read(versionActionsProvider)
      .editVersion(title, version, name: name, label: label);
  if (name != version.folder) {
    String? result;
    await runProjectChange(context, ref, () async => result = await edit());
    return result;
  }
  final l10n = AppLocalizations.of(context);
  final tasks = ref.read(tasksProvider.notifier);
  try {
    return await edit();
  } on Object catch (e) {
    fail(tasks, l10n, e);
    return null;
  }
}

class _EditVersionDialog extends StatefulWidget {
  const _EditVersionDialog(this.title, this.version);

  final Title title;
  final Version version;

  @override
  State<_EditVersionDialog> createState() => _EditVersionDialogState();
}

class _EditVersionDialogState extends State<_EditVersionDialog> {
  late final _name = TextEditingController(text: versionName(widget.version));
  late final _label = TextEditingController(
    text: widget.version.metadata?.label ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    super.dispose();
  }

  String? _error(AppLocalizations l10n) => versionNameError(
    l10n,
    widget.title,
    _name.text,
    current: widget.version.folder,
  );

  /// An adopted version keeps a label (SPEC §4.2).
  bool get _labelMissing =>
      widget.version.isAdopted && _label.text.trim().isEmpty;

  void _save() {
    if (_error(AppLocalizations.of(context)) != null || _labelMissing) return;
    Navigator.of(context).pop((versionNameOf(_name.text), _label.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adopted = widget.version.isAdopted;
    final error = _error(l10n);
    return AlertDialog(
      title: Text(l10n.editVersionTitle),
      content: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: l10n.versionFolderName,
                // Room kept for the error: the dialog keeps its size.
                helperText: ' ',
                errorText: error,
                isDense: true,
              ),
            ),
            const SizedBox(height: Space.xs),
            TextField(
              controller: _label,
              enabled: adopted,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: l10n.versionLabel,
                helperText: adopted ? ' ' : l10n.labelNeedsAdoption,
                errorText: _labelMissing ? l10n.labelRequired : null,
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: error == null && !_labelMissing ? _save : null,
          child: Text(actionLabel(l10n.editVersion)),
        ),
      ],
    );
  }
}
