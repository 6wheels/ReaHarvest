import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart' show LibraryEntry;
import 'package:reaharvest_repository/reaharvest_repository.dart'
    show isValidFolderName;

import '../l10n/app_localizations.dart';
import '../state/library_catalog.dart';
import '../theme/app_theme.dart';
import 'layout_labels.dart';

/// Editor of the known values of the intermediate levels of [layout] (SPEC
/// §3.1), as a tree: values can be removed, unless [used], and added at
/// each level.
class KnownValuesEditor extends StatelessWidget {
  const KnownValuesEditor({
    super.key,
    required this.layout,
    required this.values,
    required this.onChanged,
    this.used = const {},
  });

  final Layout layout;
  final List<KnownValue> values;
  final ValueChanged<List<KnownValue>> onChanged;

  /// Paths (joined with `/`) of the values still used by a folder.
  final Set<String> used;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final problem = values.problemFor(layout.levels.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._level(context, values, const []),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              knownValuesProblemLabel(l10n, problem),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  /// Rows of [level] values under [parent], then the field adding one.
  List<Widget> _level(
    BuildContext context,
    List<KnownValue> level,
    List<String> parent,
  ) {
    final depth = parent.length;
    final last = depth == layout.levels.length - 2;
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final indent = EdgeInsets.only(left: depth * Space.l);
    return [
      for (final v in level) ...[
        Padding(
          padding: indent,
          child: Row(
            children: [
              Icon(
                last ? Icons.label_outline_rounded : Icons.folder_outlined,
                size: 16,
                color: c.muted,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  v.value == Layout.unassigned ? l10n.unassigned : v.value,
                ),
              ),
              IconButton(
                tooltip: l10n.removeValue(v.value),
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.close_rounded),
                onPressed: used.contains([...parent, v.value].join('/'))
                    ? null
                    : () => onChanged(values.withoutPath([...parent, v.value])),
              ),
            ],
          ),
        ),
        if (!last) ..._level(context, v.children, [...parent, v.value]),
      ],
      Padding(
        padding: indent,
        child: Row(
          children: [
            Expanded(
              child: _AddValue(
                key: ValueKey('add:${parent.join('/')}'),
                label: l10n.addValue(
                  layoutLevelLabel(l10n, layout.levels[depth]),
                ),
                taken: {for (final v in level) v.value},
                onAdded: (value) =>
                    onChanged(values.withPath([...parent, value])),
              ),
            ),
            // A level below a value may be left unassigned (no album).
            if (depth > 0 && !level.any((v) => v.value == Layout.unassigned))
              TextButton(
                onPressed: () =>
                    onChanged(values.withPath([...parent, Layout.unassigned])),
                child: Text(l10n.unassigned),
              ),
          ],
        ),
      ),
    ];
  }
}

String knownValuesProblemLabel(
  AppLocalizations l10n,
  KnownValuesProblem problem,
) => switch (problem) {
  KnownValuesProblem.empty => l10n.knownValuesEmpty,
  KnownValuesProblem.missingChild => l10n.knownValuesMissingChild,
  // Not reachable from the editor, which adds values level by level.
  KnownValuesProblem.tooDeep ||
  KnownValuesProblem.duplicate => l10n.knownValuesInvalid,
};

/// Field adding a value, on Enter; rejects invalid and [taken] names.
class _AddValue extends StatefulWidget {
  const _AddValue({
    super.key,
    required this.label,
    required this.taken,
    required this.onAdded,
  });

  final String label;
  final Set<String> taken;
  final ValueChanged<String> onAdded;

  @override
  State<_AddValue> createState() => _AddValueState();
}

class _AddValueState extends State<_AddValue> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final name = _controller.text.trim();
    return isValidFolderName(name) && !widget.taken.contains(name);
  }

  void _add() {
    if (!_valid) return;
    widget.onAdded(_controller.text.trim());
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    onChanged: (_) => setState(() {}),
    onSubmitted: (_) => _add(),
    decoration: InputDecoration(
      isDense: true,
      hintText: widget.label,
      prefixIcon: const Icon(Icons.add_rounded, size: 16),
      prefixIconConstraints: const BoxConstraints(minWidth: 28),
      border: InputBorder.none,
      suffixIcon: _controller.text.trim().isEmpty
          ? null
          : IconButton(
              tooltip: widget.label,
              iconSize: 16,
              icon: const Icon(Icons.check_rounded),
              onPressed: _valid ? _add : null,
            ),
    ),
  );
}

/// Edits the known values of the library [entry] with [layout] (library
/// settings, SPEC §3.1); values still used by a folder cannot be removed.
Future<void> showKnownValues(
  BuildContext context,
  LibraryEntry entry,
  Layout layout,
) => showDialog(
  context: context,
  builder: (context) => _KnownValuesDialog(entry, layout),
);

class _KnownValuesDialog extends ConsumerStatefulWidget {
  const _KnownValuesDialog(this.entry, this.layout);

  final LibraryEntry entry;
  final Layout layout;

  @override
  ConsumerState<_KnownValuesDialog> createState() => _KnownValuesDialogState();
}

class _KnownValuesDialogState extends ConsumerState<_KnownValuesDialog> {
  List<KnownValue>? _values;
  var _used = const <String>{};

  @override
  void initState() {
    super.initState();
    ref.read(libraryCatalogProvider).knownValuesOf(widget.entry).then((r) {
      if (mounted) {
        setState(() {
          _values = r.values;
          _used = r.used;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final values = _values;
    final valid =
        values != null &&
        values.problemFor(widget.layout.levels.length) == null;
    return AlertDialog(
      title: Text('${l10n.knownValues} · ${widget.entry.displayName}'),
      content: SizedBox(
        width: 480,
        child: values == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_used.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.s),
                        child: Text(
                          l10n.knownValuesUsed,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.colors.muted),
                        ),
                      ),
                    KnownValuesEditor(
                      layout: widget.layout,
                      values: values,
                      used: _used,
                      onChanged: (v) => setState(() => _values = v),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: valid
              ? () {
                  Navigator.of(context).pop();
                  ref
                      .read(libraryCatalogProvider)
                      .setKnownValues(widget.entry, values);
                }
              : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
