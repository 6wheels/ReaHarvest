import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/library_catalog.dart';
import '../../state/providers.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../labels.dart';
import '../widgets.dart';
import 'version_ui_actions.dart';

/// Source of a new version.
enum _Source { blank, template, duplicate }

/// Asks for a new version of [title] (blank, from a template, or a copy of
/// [selected]) and creates it. Returns its file name, null when cancelled.
Future<String?> showNewVersionDialog(
  BuildContext context,
  Title title,
  Version? selected,
) => showDialog<String>(
  context: context,
  builder: (_) => _NewVersionDialog(title, selected),
);

class _NewVersionDialog extends ConsumerStatefulWidget {
  const _NewVersionDialog(this.title, this.selected);

  final Title title;
  final Version? selected;

  @override
  ConsumerState<_NewVersionDialog> createState() => _NewVersionDialogState();
}

class _NewVersionDialogState extends ConsumerState<_NewVersionDialog> {
  final _label = TextEditingController();
  late final _name = TextEditingController(text: _suggested);
  var _source = _Source.blank;
  String? _template;

  /// The file name follows the label until edited by hand.
  var _nameEdited = false;

  /// The label is required: its error shows once it has been typed in.
  var _labelEdited = false;
  var _busy = false;

  String get _suggested =>
      suggestedVersionName(titleName(widget.title), _label.text);

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    if (versionNameError(l10n, widget.title, _name.text) != null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final name = await ref
          .read(versionActionsProvider)
          .addVersion(
            widget.title,
            withProjectExtension(_name.text),
            _label.text,
            source: _source == _Source.duplicate ? widget.selected : null,
            template: _source == _Source.template ? _template : null,
          );
      navigator.pop(name);
    } on Object catch (e) {
      fail(messenger, l10n, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final templates =
        ref.watch(projectTemplatesProvider(widget.title.libraryId)).value ??
        const <String>[];
    // Shown only when written: the library declares the local member.
    final owner = ref.watch(localOwnerProvider(widget.title.libraryId)) == null
        ? null
        : ref.watch(settingsProvider.select((s) => s.identity.displayName));
    final selected = widget.selected;
    final error = versionNameError(l10n, widget.title, _name.text);
    final labelMissing = _label.text.trim().isEmpty;
    final ready =
        !_busy &&
        error == null &&
        !labelMissing &&
        (_source != _Source.template || _template != null);
    Widget source(_Source value, String label, {String? hint, bool? enabled}) =>
        RadioListTile<_Source>(
          value: value,
          dense: true,
          contentPadding: EdgeInsets.zero,
          enabled: enabled ?? true,
          title: Text(label),
          subtitle: hint == null ? null : Text(hint),
        );
    return AlertDialog(
      title: Text(l10n.newVersion),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<_Source>(
              groupValue: _source,
              onChanged: (v) => setState(() => _source = v ?? _source),
              child: Column(
                children: [
                  source(
                    _Source.blank,
                    l10n.versionSourceBlank,
                    hint: l10n.versionSourceBlankHint,
                  ),
                  source(
                    _Source.template,
                    l10n.versionSourceTemplate,
                    hint: templates.isEmpty ? l10n.noTemplate : null,
                    enabled: templates.isNotEmpty,
                  ),
                  if (selected != null)
                    source(
                      _Source.duplicate,
                      l10n.versionSourceDuplicate(
                        p.posix.withoutExtension(selected.fileName),
                      ),
                    ),
                ],
              ),
            ),
            if (_source == _Source.template)
              DropdownButtonFormField<String>(
                initialValue: _template,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.versionSourceTemplate,
                  isDense: true,
                ),
                items: [
                  for (final t in templates)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        p.basenameWithoutExtension(t),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _template = v),
              ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _label,
              autofocus: true,
              onChanged: (_) => setState(() {
                _labelEdited = true;
                if (!_nameEdited) _name.text = _suggested;
              }),
              decoration: InputDecoration(
                labelText: l10n.versionLabel,
                errorText: _labelEdited && labelMissing
                    ? l10n.labelRequired
                    : null,
                isDense: true,
              ),
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() => _nameEdited = true),
              onSubmitted: (_) => ready ? _create() : null,
              decoration: InputDecoration(
                labelText: l10n.fileName,
                errorText: error,
                isDense: true,
              ),
            ),
            if (owner != null) ...[
              const SizedBox(height: Space.s),
              Text(
                l10n.filterValue(l10n.filterOwner, owner),
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: ready ? _create : null,
          child: BusyLabel(l10n.create, busy: _busy),
        ),
      ],
    );
  }
}
