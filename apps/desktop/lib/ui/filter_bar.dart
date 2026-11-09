import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'layout_labels.dart';
import 'to_sort_page.dart';

/// Filter chips, saved views, "To sort" / "To adopt" and display mode, below
/// the search bar (SPEC §5.2). Chips offering a single value are hidden.
class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final options = ref.watch(filterOptionsProvider);
    final navigation = ref.watch(navigationProvider);
    final filter = navigation.filter;
    final notifier = ref.read(navigationProvider.notifier);
    final owners = ref.watch(ownerNamesProvider);
    final configured = ref.watch(settingsProvider.select((s) => s.libraries));
    final toSort = ref.watch(issuesProvider).length;
    // Titles with a version to adopt, as shown once filtered.
    final toAdopt = {for (final (t, _) in ref.watch(toAdoptProvider)) t.id}
        .length;
    void set(TitleFilter f) => notifier.setFilter(f);

    final chips = <Widget>[
      for (final (:level, :values) in options.tags)
        if (values.length > 1 || (filter.tags[level.key]?.isNotEmpty ?? false))
          _MultiChoiceChip<String>(
            label: layoutLevelLabel(l10n, level),
            options: values,
            selected: filter.tags[level.key] ?? const {},
            labelOf: (v) => tagValueLabel(l10n, v),
            onChanged: (s) => set(filter.withTag(level.key, s)),
          ),
      if (options.libraries.length > 1 || filter.libraries.isNotEmpty)
        _MultiChoiceChip(
          label: l10n.filterLibrary,
          options: [for (final l in options.libraries) l.id],
          selected: filter.libraries,
          // A saved filter may name a library without titles any more, or
          // even a removed one (raw id).
          labelOf: (id) =>
              configured.where((l) => l.id == id).firstOrNull?.displayName ??
              id,
          onChanged: (s) => set(filter.copyWith(libraries: s)),
        ),
      if (options.modes.length > 1 || filter.modes.isNotEmpty)
        _MultiChoiceChip(
          label: l10n.filterMode,
          options: options.modes,
          selected: filter.modes,
          labelOf: (m) => modeLabel(l10n, m),
          onChanged: (s) => set(filter.copyWith(modes: s)),
        ),
      if (options.statuses.isNotEmpty || filter.statuses.isNotEmpty)
        _MultiChoiceChip(
          label: l10n.filterStatus,
          options: options.statuses,
          selected: filter.statuses,
          labelOf: (s) => statusLabel(l10n, s),
          onChanged: (s) => set(filter.copyWith(statuses: s)),
        ),
      if (options.owners.length > 1 || filter.owners.isNotEmpty)
        _MultiChoiceChip(
          label: l10n.filterOwner,
          options: options.owners,
          selected: filter.owners,
          labelOf: (o) => ownerName(owners, o),
          onChanged: (s) => set(filter.copyWith(owners: s)),
        ),
      if (options.missingPlugins || filter.missingPlugins)
        Pill(
          label: l10n.filterMissingPlugins,
          icon: Icons.extension_off_outlined,
          active: filter.missingPlugins,
          onPressed: () =>
              set(filter.copyWith(missingPlugins: !filter.missingPlugins)),
        ),
      const _SavedViewsChip(),
      if (!filter.isEmpty)
        TextButton(
          onPressed: () => set(const TitleFilter()),
          child: Text(l10n.clearFilters),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
          ),
          const SizedBox(width: Space.m),
          if (toSort > 0) ...[
            Pill(
              label: '${l10n.toSort} · $toSort',
              icon: Icons.move_down_rounded,
              onPressed: () => openToSort(context),
            ),
            const SizedBox(width: Space.s),
          ],
          if (toAdopt > 0) ...[
            Pill(
              label: '${l10n.toAdopt} · $toAdopt',
              icon: Icons.add_task_rounded,
              active: filter.toAdopt,
              onPressed: () => set(filter.copyWith(toAdopt: !filter.toAdopt)),
            ),
            const SizedBox(width: Space.s),
          ],
          SegmentedButton<DisplayMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: DisplayMode.cards,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                tooltip: l10n.displayCards,
              ),
              ButtonSegment(
                value: DisplayMode.list,
                icon: const Icon(Icons.view_list_rounded, size: 18),
                tooltip: l10n.displayList,
              ),
              ButtonSegment(
                value: DisplayMode.tree,
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                tooltip: l10n.displayTree,
              ),
            ],
            selected: {navigation.displayMode},
            onSelectionChanged: (s) => notifier.setDisplayMode(s.single),
          ),
        ],
      ),
    );
  }
}

/// Rounded chip of the filter bar.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.trailing,
    this.active = false,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final IconData? trailing;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.accent : c.muted;
    return Material(
      color: active ? c.accent.withValues(alpha: 0.14) : c.raised,
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? c.accent.withValues(alpha: 0.5) : c.border,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: active ? c.text : c.muted),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 2),
                Icon(trailing, size: 16, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip opening a menu of checkable values.
class _MultiChoiceChip<T> extends StatelessWidget {
  const _MultiChoiceChip({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    // Selected values no longer offered stay listed, to be cleared.
    final values = [...options, ...selected.where((s) => !options.contains(s))];
    final l10n = AppLocalizations.of(context);
    final text = switch (selected.length) {
      0 => label,
      1 => l10n.filterValue(label, labelOf(selected.single)),
      final n => l10n.filterValue(label, '$n'),
    };
    return MenuAnchor(
      menuChildren: [
        for (final v in values)
          CheckboxMenuButton(
            value: selected.contains(v),
            closeOnActivate: false,
            onChanged: (checked) => onChanged(
              checked == true ? {...selected, v} : ({...selected}..remove(v)),
            ),
            child: Text(labelOf(v)),
          ),
      ],
      builder: (context, controller, _) => Pill(
        label: text,
        trailing: Icons.expand_more_rounded,
        active: selected.isNotEmpty,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _SavedViewsChip extends ConsumerWidget {
  const _SavedViewsChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final views = ref.watch(navigationProvider.select((n) => n.savedViews));
    final notifier = ref.read(navigationProvider.notifier);
    return MenuAnchor(
      menuChildren: [
        if (views.isEmpty)
          MenuItemButton(onPressed: null, child: Text(l10n.noSavedView)),
        for (final v in views)
          MenuItemButton(
            onPressed: () => notifier.applyView(v),
            trailingIcon: IconButton(
              tooltip: l10n.deleteView,
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              onPressed: () => notifier.deleteView(v.name),
              icon: const Icon(Icons.close_rounded),
            ),
            child: Text(v.name),
          ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.bookmark_add_outlined, size: 18),
          onPressed: () async {
            final name = await _askViewName(context);
            if (name != null) notifier.saveView(name);
          },
          child: Text(l10n.saveView),
        ),
      ],
      builder: (context, controller, _) => Pill(
        label: l10n.views,
        icon: Icons.bookmark_outline_rounded,
        trailing: Icons.expand_more_rounded,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  static Future<String?> _askViewName(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    void submit(BuildContext context) {
      final name = controller.text.trim();
      if (name.isNotEmpty) Navigator.of(context).pop(name);
    }

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.saveView),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.viewName),
          onSubmitted: (_) => submit(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => submit(context),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
