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

/// Layout choices: the provided templates, then the free tree (null).
const _choices = <LayoutTemplate?>[...LayoutTemplate.values, null];

class _LibraryFormState extends ConsumerState<LibraryForm> {
  final _name = TextEditingController();
  String? _folder;
  Library? _existing;
  LayoutTemplate? _template = LayoutTemplate.recommended;
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
      if (_name.text.trim().isEmpty) _name.text = p.basename(folder);
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(libraryServiceProvider)
          .addLocal(
            folder: _folder!,
            displayName: _name.text,
            layout: _template?.create(),
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
          child: _existing != null
              ? Text(
                  l10n.existingLibrary,
                  style: text.bodyMedium?.copyWith(color: c.muted),
                )
              : Column(
                  children: [
                    for (final t in _choices)
                      _LayoutChoice(
                        template: t,
                        selected: _template == t,
                        onTap: () => setState(() => _template = t),
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

class _LayoutChoice extends StatelessWidget {
  const _LayoutChoice({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  /// Null for the free tree.
  final LayoutTemplate? template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final t = template;
    final name = switch (t) {
      LayoutTemplate.classic => l10n.layoutClassic,
      LayoutTemplate.projectOriented => l10n.layoutProjectOriented,
      LayoutTemplate.film => l10n.layoutFilm,
      null => l10n.layoutFreeTree,
    };
    final detail = t == null
        ? l10n.layoutFreeTreeHint
        : t
              .create()
              .levels
              .map((level) => layoutLevelLabel(l10n, level))
              .join(' / ');

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
                          if (t == LayoutTemplate.recommended) ...[
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
