import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'glass_dialog.dart';
import 'labels.dart';
import 'layout_labels.dart';
import 'to_sort/to_sort_page.dart';
import 'widgets.dart'
    show ChoiceLight, Disclosure, MenuLegend, actionLabel, focusMenuEntry;

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
      for (final (:level, :values) in options.levels)
        if (values.length > 1 ||
            (filter.levels[level.key]?.isNotEmpty ?? false))
          _MultiChoiceChip<String>(
            label: layoutLevelLabel(l10n, level),
            options: values,
            selected: filter.levels[level.key] ?? const {},
            labelOf: (v) => levelValueLabel(l10n, v),
            onChanged: (s) => set(filter.withLevel(level.key, s)),
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
          labelOf: (o) => owners[o] ?? l10n.unknownOwner,
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
        Pill(
          label: l10n.clearFilters,
          icon: Icons.close_rounded,
          onPressed: () => set(const TitleFilter()),
        ),
    ];

    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.m,
        vertical: Space.s - 2,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: Space.xs + 2,
              runSpacing: Space.xs + 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
          ),
          const SizedBox(width: Space.m),
          if (toSort > 0) ...[
            Pill(
              label: l10n.toSort,
              count: toSort,
              icon: Icons.move_down_rounded,
              onPressed: () => openToSort(context),
            ),
            const SizedBox(width: Space.s),
          ],
          if (toAdopt > 0) ...[
            Pill(
              label: l10n.toAdopt,
              count: toAdopt,
              icon: Icons.add_task_rounded,
              active: filter.toAdopt,
              onPressed: () => set(filter.copyWith(toAdopt: !filter.toAdopt)),
            ),
            const SizedBox(width: Space.s),
          ],
          _DisplaySwitch(
            selected: navigation.displayMode,
            onChanged: notifier.setDisplayMode,
          ),
        ],
      ),
    );
  }
}

/// Console switch of the filter bar: a legend in a square frame, lit with
/// the accent when [active]; an optional [count] readout at the end.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.menuOpen,
    this.count,
    this.active = false,
    this.onPressed,
  });

  final String label;
  final IconData? icon;

  /// Whether the menu it opens is open; null when it opens none.
  final bool? menuOpen;
  final int? count;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.accent : c.muted;
    return Material(
      color: active ? c.accent.withValues(alpha: 0.10) : c.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        side: BorderSide(
          color: active ? c.accent.withValues(alpha: 0.55) : c.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.s),
        onTap: onPressed,
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                ],
                Text.rich(
                  TextSpan(
                    text: label.toUpperCase(),
                    children: [
                      if (count != null)
                        TextSpan(
                          text: '$labelSeparator$count',
                          style: TextStyle(color: c.accent),
                        ),
                    ],
                  ),
                  style: context.legend.copyWith(
                    color: active ? c.text : c.muted,
                  ),
                ),
                if (menuOpen case final open?) ...[
                  const SizedBox(width: 2),
                  Disclosure(
                    open ? Disclosure.up : Disclosure.down,
                    size: 20,
                    color: color,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Display mode selector: a row of square switches in one frame, as high
/// as the filter switches; the selected one is lit.
class _DisplaySwitch extends StatelessWidget {
  const _DisplaySwitch({required this.selected, required this.onChanged});

  final DisplayMode selected;
  final ValueChanged<DisplayMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final modes = [
      (DisplayMode.cards, Icons.grid_view_rounded, l10n.displayCards),
      (DisplayMode.list, Icons.view_list_rounded, l10n.displayList),
      (DisplayMode.tree, Icons.account_tree_outlined, l10n.displayTree),
    ];
    return Container(
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final (mode, icon, tooltip) in modes)
            Tooltip(
              message: tooltip,
              child: Material(
                color: mode == selected
                    ? c.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.xs),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  onTap: () => onChanged(mode),
                  child: SizedBox(
                    width: 28,
                    height: 20,
                    child: Icon(
                      icon,
                      size: 14,
                      color: mode == selected ? c.accent : c.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip opening a menu of checkable values. From the keyboard: the arrows
/// move through the values, Space checks or unchecks one, Enter or Escape
/// closes the menu.
class _MultiChoiceChip<T> extends StatefulWidget {
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
  State<_MultiChoiceChip<T>> createState() => _MultiChoiceChipState<T>();
}

class _MultiChoiceChipState<T> extends State<_MultiChoiceChip<T>> {
  final _menu = MenuController();

  /// The first value, focused when the menu opens.
  final _first = FocusNode();

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _MultiChoiceChip(:label, :options, :selected, :labelOf, :onChanged) =
        widget;
    // Selected values no longer offered stay listed, to be cleared.
    final values = [...options, ...selected.where((s) => !options.contains(s))];
    final text = switch (selected.length) {
      0 => label,
      1 => '$label$labelSeparator${labelOf(selected.single)}',
      final n => '$label$labelSeparator$n',
    };
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, Space.xs),
      onOpen: () => focusMenuEntry(_first),
      menuChildren: [
        MenuLegend(label),
        for (final (i, v) in values.indexed)
          // Space (and a click) toggles the value, Enter closes.
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): _menu.close,
              const SingleActivator(LogicalKeyboardKey.numpadEnter):
                  _menu.close,
            },
            child: MenuItemButton(
              focusNode: i == 0 ? _first : null,
              closeOnActivate: false,
              leadingIcon: ChoiceLight(checked: selected.contains(v)),
              onPressed: () => onChanged(
                selected.contains(v)
                    ? ({...selected}..remove(v))
                    : {...selected, v},
              ),
              child: Text(labelOf(v)),
            ),
          ),
      ],
      builder: (context, controller, _) => Pill(
        label: text,
        menuOpen: controller.isOpen,
        active: selected.isNotEmpty,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Chip opening the saved views; its first entry is focused on opening, so
/// that the keyboard (arrows, Enter, Escape) drives the menu.
class _SavedViewsChip extends ConsumerStatefulWidget {
  const _SavedViewsChip();

  @override
  ConsumerState<_SavedViewsChip> createState() => _SavedViewsChipState();
}

class _SavedViewsChipState extends ConsumerState<_SavedViewsChip> {
  final _first = FocusNode();

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final views = ref.watch(navigationProvider.select((n) => n.savedViews));
    final notifier = ref.read(navigationProvider.notifier);
    return MenuAnchor(
      alignmentOffset: const Offset(0, Space.xs),
      onOpen: () => focusMenuEntry(_first),
      menuChildren: [
        MenuLegend(l10n.views),
        if (views.isEmpty)
          MenuItemButton(onPressed: null, child: Text(l10n.noSavedView)),
        for (final (i, v) in views.indexed)
          MenuItemButton(
            focusNode: i == 0 ? _first : null,
            onPressed: () => notifier.applyView(v),
            trailingIcon: IconButton(
              tooltip: l10n.deleteView,
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              onPressed: () => notifier.deleteView(v.name),
              icon: const Icon(Icons.close_rounded),
            ),
            child: Text(v.name),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Space.xs),
          child: Divider(height: 1),
        ),
        MenuItemButton(
          // The first entry when no view is saved yet.
          focusNode: views.isEmpty ? _first : null,
          leadingIcon: const Icon(Icons.bookmark_add_outlined),
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
        menuOpen: controller.isOpen,
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

    return showGlassDialog<String>(
      context,
      (context) => AlertDialog(
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
            child: Text(actionLabel(l10n.saveView)),
          ),
        ],
      ),
    );
  }
}
