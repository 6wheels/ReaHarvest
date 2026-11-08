import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'layout_labels.dart';
import 'title_detail.dart';
import 'widgets.dart';

/// Opens the "To sort" page over the library (SPEC §5.2).
Future<void> openToSort(BuildContext context) =>
    Navigator.of(context).push(overLibraryRoute((_) => const ToSortPage()));

/// `.RPP` files and folders outside the organization of their library,
/// with a guided move (SPEC §5.2). Back with the back button, Escape or
/// the mouse back button.
class ToSortPage extends StatelessWidget {
  const ToSortPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BackNavigation(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.m,
                Space.m,
                Space.xl,
                Space.m,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.back,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: Space.s),
                  Text(
                    l10n.toSort,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.border),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: const _ToSortList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToSortList extends ConsumerWidget {
  const _ToSortList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final items = ref.watch(toSortProvider);
    final orphans = ref.watch(scanIssuesProvider('orphanNode'));
    final corrupted = ref.watch(scanIssuesProvider('corrupted'));
    final names = {
      for (final l in ref.watch(settingsProvider.select((s) => s.libraries)))
        l.id: l.displayName,
    };
    final multiple =
        {
          for (final i in [...items, ...orphans, ...corrupted]) i.library,
        }.length >
        1;
    String subtitle(({LibraryId library, String path}) item, String path) => [
      if (multiple) ?names[item.library],
      path,
    ].where((s) => s != '.' && s.isNotEmpty).join(' · ');
    Widget hint(String value) => Padding(
      padding: const EdgeInsets.only(top: Space.l),
      child: Text(value, style: text.bodyMedium?.copyWith(color: c.muted)),
    );
    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        if (items.isNotEmpty) ...[
          Text(
            l10n.toSortHint,
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.s),
        ],
        for (final item in items)
          _Item(
            title: p.posix.basename(item.path),
            subtitle: subtitle(item, p.posix.dirname(item.path)),
            child: isProjectFile(item.path)
                ? Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => showSortDialog(
                        context,
                        library: item.library,
                        path: item.path,
                      ),
                      child: Text(l10n.sortAction),
                    ),
                  )
                : Text(
                    l10n.toSortFolderHint,
                    style: text.bodySmall?.copyWith(color: c.muted),
                  ),
          ),
        if (orphans.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          SectionLabel(l10n.orphanNodesTitle),
          hint(l10n.orphanNodesHint),
          for (final item in orphans)
            _Item(
              title: p.posix.dirname(item.path),
              subtitle: subtitle(item, p.posix.basename(item.path)),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => _deleteOrphan(context, ref, item),
                  child: Text(l10n.deleteOrphanNode),
                ),
              ),
            ),
        ],
        if (corrupted.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          SectionLabel(l10n.corruptedTitle),
          hint(l10n.corruptedHint),
          for (final item in corrupted)
            _Item(
              title: p.posix.basename(item.path),
              subtitle: subtitle(item, p.posix.dirname(item.path)),
              child: const SizedBox.shrink(),
            ),
        ],
      ],
    );
  }

  Future<void> _deleteOrphan(
    BuildContext context,
    WidgetRef ref,
    ({LibraryId library, String path}) item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteOrphanNodeTitle),
        content: Text(l10n.deleteOrphanNodeHint(p.posix.dirname(item.path))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteOrphanNode),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(libraryServiceProvider)
          .deleteOrphanNode(item.library, item.path);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.actionFailed('$error'))),
      );
    }
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: text.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: Space.s),
          child,
        ],
      ),
    );
  }
}

/// Guided move of the misplaced project [path] into a title of [library]
/// ("To sort", SPEC §5.2).
Future<void> showSortDialog(
  BuildContext context, {
  required LibraryId library,
  required String path,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SortDialog(library: library, path: path),
);

class _SortDialog extends ConsumerStatefulWidget {
  const _SortDialog({required this.library, required this.path});

  final LibraryId library;
  final String path;

  @override
  ConsumerState<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends ConsumerState<_SortDialog> {
  late final Layout _layout;
  late final List<TextEditingController> _values;

  @override
  void initState() {
    super.initState();
    _layout = ref.read(indexedLibrariesProvider)[widget.library]!.layout!;
    // Prefilled from the current folders, and the file name for the title.
    final folders = p.posix.dirname(widget.path).split('/')
      ..removeWhere((s) => s == '.');
    final levels = _layout.levels.length;
    _values = [
      for (var i = 0; i < levels; i++)
        TextEditingController(
          text: i == levels - 1
              ? p.posix.basenameWithoutExtension(widget.path)
              : (i < folders.length ? folders[i] : Layout.unassigned),
        ),
    ];
  }

  @override
  void dispose() {
    for (final c in _values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => _values.every((c) => isValidFolderName(c.text.trim()));

  /// Existing values of level [i] under the values typed above it.
  List<String> _options(int i) {
    final above = [for (final c in _values.take(i)) c.text.trim()];
    final keys = [for (final l in _layout.levels) l.key];
    return {
      for (final t in ref.read(titlesProvider))
        if (t.libraryId == widget.library &&
            [for (var j = 0; j < i; j++) t.tags[keys[j]]].join('/') ==
                above.join('/'))
          ?t.tags[keys[i]],
    }.toList()..sort();
  }

  Future<void> _move() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    MoveReport? report;
    final done = await runProjectChange(context, ref, () async {
      report = await ref.read(libraryServiceProvider).moveToTitle(
        widget.library,
        widget.path,
        [for (final c in _values) c.text.trim()],
      );
    });
    if (!done) return;
    navigator.pop();
    final r = report!;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          [
            l10n.sortDone,
            if (r.missing.isNotEmpty) l10n.sortMissingMedia(r.missing.length),
            if (r.external.isNotEmpty)
              l10n.sortExternalMedia(r.external.length),
          ].join(' '),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return AlertDialog(
      title: Text(l10n.sortTitle(p.posix.basename(widget.path))),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.sortHint,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: c.muted),
            ),
            for (final (i, level) in _layout.levels.indexed) ...[
              const SizedBox(height: Space.m),
              _LevelField(
                label: layoutLevelLabel(l10n, level),
                controller: _values[i],
                options: () => _options(i),
                error: isValidFolderName(_values[i].text.trim())
                    ? null
                    : l10n.invalidFolderName,
                onChanged: () => setState(() {}),
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
          onPressed: _valid ? _move : null,
          child: Text(l10n.sortConfirm),
        ),
      ],
    );
  }
}

/// Text field of one layout level, with autocompletion on existing values.
class _LevelField extends StatefulWidget {
  const _LevelField({
    required this.label,
    required this.controller,
    required this.options,
    required this.error,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final List<String> Function() options;
  final String? error;
  final VoidCallback onChanged;

  @override
  State<_LevelField> createState() => _LevelFieldState();
}

class _LevelFieldState extends State<_LevelField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsBuilder: (value) {
      final typed = value.text.trim().toLowerCase();
      return widget.options().where((o) => o.toLowerCase().contains(typed));
    },
    onSelected: (_) => widget.onChanged(),
    fieldViewBuilder: (context, controller, focusNode, _) => TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.error,
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: context.colors.raised,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 420),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final o in options)
                ListTile(
                  dense: true,
                  title: Text(o),
                  onTap: () => onSelected(o),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
