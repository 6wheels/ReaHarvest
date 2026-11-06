import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
import '../state/pickers.dart';
import '../theme/app_theme.dart';
import 'layout_labels.dart';
import 'path_row.dart';

/// Adds a local library: folder, name, mode and organization (SPEC §5.1).
/// Calls [onAdded] once the library is configured and scanned.
class LibraryForm extends ConsumerStatefulWidget {
  const LibraryForm({
    super.key,
    required this.submitLabel,
    required this.onAdded,
  });

  final String submitLabel;
  final VoidCallback onAdded;

  @override
  ConsumerState<LibraryForm> createState() => _LibraryFormState();
}

/// Index of the free tree in the layout choices, after the templates.
final _freeTreeChoice = LayoutTemplate.values.length;

class _LibraryFormState extends ConsumerState<LibraryForm> {
  final _name = TextEditingController();
  String? _folder;
  Library? _existing;
  /// Selected choice: a template, the free tree, or the current custom
  /// layout of an existing library.
  var _choice = LayoutTemplate.recommended.index;
  LibraryProblem? _problem;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _chooseFolder() async {
    final folder = await ref.read(pickersProvider).folder(initial: _folder);
    if (folder == null) return;
    Library? existing;
    LibraryProblem? problem;
    try {
      existing = await ref.read(libraryServiceProvider).existing(folder);
      if (existing != null && existing.mode != LibraryMode.local) {
        problem = LibraryProblem.unsupportedMode;
      }
    } on LibraryException catch (e) {
      problem = e.problem;
    }
    if (!mounted) return;
    setState(() {
      _folder = folder;
      _existing = existing;
      _problem = problem;
      if (existing != null) _choice = _choiceOf(existing.layout);
      if (_name.text.trim().isEmpty) _name.text = p.basename(folder);
    });
  }

  /// Choice matching [layout]: a template, the free tree, or the custom one.
  static int _choiceOf(Layout? layout) {
    if (layout == null) return _freeTreeChoice;
    for (final t in LayoutTemplate.values) {
      if (sameLayout(t.create(), layout)) return t.index;
    }
    return _freeTreeChoice + 1;
  }

  /// Existing custom layout, offered as an extra choice.
  Layout? get _custom => switch (_existing?.layout) {
    final l? when _choiceOf(l) > _freeTreeChoice => l,
    _ => null,
  };

  Layout? get _layout => _choice < _freeTreeChoice
      ? LayoutTemplate.values[_choice].create()
      : _choice == _freeTreeChoice
      ? null
      : _custom;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(libraryServiceProvider)
          .addLocal(
            folder: _folder!,
            displayName: _name.text,
            layout: _layout,
          );
      widget.onAdded();
    } on LibraryException catch (e) {
      if (mounted) setState(() => _problem = e.problem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final canSubmit = _folder != null && _problem == null && !_busy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PathRow(
          label: l10n.libraryFolder,
          value: _folder,
          placeholder: l10n.noFolder,
          onChoose: _chooseFolder,
        ),
        FormRow(
          label: l10n.libraryName,
          child: TextField(
            controller: _name,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        FormRow(
          label: l10n.libraryMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<LibraryMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: LibraryMode.local,
                    label: Text(l10n.modeLocal),
                  ),
                  ButtonSegment(
                    value: LibraryMode.cloud,
                    label: Text(l10n.modeCloud),
                    enabled: false,
                  ),
                  ButtonSegment(
                    value: LibraryMode.collab,
                    label: Text(l10n.modeCollab),
                    enabled: false,
                  ),
                ],
                selected: const {LibraryMode.local},
                onSelectionChanged: (_) {},
              ),
              const SizedBox(height: Space.xs),
              Text(
                l10n.modesComingSoon,
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
        FormRow(
          label: l10n.libraryLayout,
          alignTop: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_existing != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: Text(
                    l10n.existingLibrary,
                    style: text.bodySmall?.copyWith(color: c.muted),
                  ),
                ),
              for (final t in LayoutTemplate.values)
                _LayoutChoice(
                  name: switch (t) {
                    LayoutTemplate.classic => l10n.layoutClassic,
                    LayoutTemplate.projectOriented =>
                      l10n.layoutProjectOriented,
                    LayoutTemplate.film => l10n.layoutFilm,
                  },
                  detail: _levels(l10n, t.create()),
                  recommended: t == LayoutTemplate.recommended,
                  selected: _choice == t.index,
                  onTap: () => setState(() => _choice = t.index),
                ),
              _LayoutChoice(
                name: l10n.layoutFreeTree,
                detail: l10n.layoutFreeTreeHint,
                selected: _choice == _freeTreeChoice,
                onTap: () => setState(() => _choice = _freeTreeChoice),
              ),
              if (_custom case final custom?)
                _LayoutChoice(
                  name: l10n.layoutCurrent,
                  detail: _levels(l10n, custom),
                  selected: _choice > _freeTreeChoice,
                  onTap: () => setState(() => _choice = _freeTreeChoice + 1),
                ),
            ],
          ),
        ),
        if (_problem case final problem?)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Text(
              switch (problem) {
                LibraryProblem.unsupportedMode => l10n.errorUnsupportedMode,
                LibraryProblem.overlap => l10n.errorOverlap,
                LibraryProblem.invalidFile => l10n.errorInvalidFile,
              },
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: canSubmit ? _submit : null,
            child: Text(widget.submitLabel),
          ),
        ),
      ],
    );
  }
}

String _levels(AppLocalizations l10n, Layout layout) =>
    layout.levels.map((level) => layoutLevelLabel(l10n, level)).join(' / ');

class _LayoutChoice extends StatelessWidget {
  const _LayoutChoice({
    required this.name,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final String name;
  final String detail;
  final bool recommended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.10) : c.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? c.accent.withValues(alpha: 0.6) : c.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.m,
              vertical: Space.s + 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(name, style: text.bodyLarge),
                          if (recommended) ...[
                            const SizedBox(width: Space.s),
                            Text(
                              l10n.recommended,
                              style: text.labelSmall?.copyWith(color: c.accent),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        detail,
                        style: text.bodySmall?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: Motion.fast,
                  child: Icon(Icons.check_rounded, color: c.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
