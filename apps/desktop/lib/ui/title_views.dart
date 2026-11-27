import 'package:material_ui/material_ui.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'aurora.dart';
import 'kit/kit.dart';
import 'labels.dart';
import 'layout_labels.dart';
import 'overview.dart';
import 'status_trail.dart';
import 'title_actions.dart';

/// Id of a column of the list: a fixed one, or `level:<key>`.
typedef _ColumnId = String;

const _name = 'name';
const _versions = 'versions';
const _tempo = 'tempo';
const _status = 'status';
const _tags = 'tags';
const _modified = 'modified';
const _levelPrefix = 'level:';

typedef _Column = ({_ColumnId id, String label, int flex, bool end});

/// Layout level of [key] in the libraries, else a level named after it.
LayoutLevel _levelOf(Iterable<Library> libraries, String key) {
  for (final library in libraries) {
    for (final level in library.layout?.levels ?? const <LayoutLevel>[]) {
      if (level.key == key) return level;
    }
  }
  return LayoutLevel(key);
}

/// Dense table of titles, sortable by column (SPEC §5.2).
class TitleList extends ConsumerStatefulWidget {
  const TitleList(this.titles, {super.key});

  final List<Title> titles;

  @override
  ConsumerState<TitleList> createState() => _TitleListState();
}

class _TitleListState extends ConsumerState<TitleList> {
  /// Null keeps the search order (best match first).
  _ColumnId? _sortBy;
  var _ascending = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final libraries = ref.watch(indexedLibrariesProvider).values;
    final showTags = ref.watch(settingsProvider.select((s) => s.showTags));
    // One column per non-leaf level of the layouts, in order of appearance.
    final levelKeys = <String>{};
    for (final library in libraries) {
      final levels = library.layout?.levels ?? const <LayoutLevel>[];
      if (levels.length > 1) {
        levelKeys.addAll(levels.take(levels.length - 1).map((l) => l.key));
      }
    }
    final columns = <_Column>[
      (id: _name, label: l10n.columnName, flex: 5, end: false),
      for (final key in levelKeys)
        (
          id: '$_levelPrefix$key',
          label: layoutLevelLabel(l10n, _levelOf(libraries, key)),
          flex: 3,
          end: false,
        ),
      (id: _versions, label: l10n.versions, flex: 2, end: true),
      (id: _tempo, label: l10n.columnBpm, flex: 1, end: true),
      (id: _status, label: l10n.filterStatus, flex: 2, end: false),
      if (showTags) (id: _tags, label: l10n.columnTags, flex: 3, end: false),
      (id: _modified, label: l10n.columnModified, flex: 2, end: true),
    ];
    final flexes = [for (final column in columns) column.flex];
    final titles = [...widget.titles];
    if (_sortBy case final column?) {
      titles.sort((a, b) {
        return _compare(column, a, b, _ascending);
      });
    }
    final selected = ref.watch(overviewProvider);

    Widget cell(_ColumnId id, Title t) => switch (id) {
      _name => _NameCell(t),
      _versions => _Text('${t.versions.length}', end: true),
      _tempo => _Text('${tempoOf(t) ?? ''}', end: true),
      _status => Padding(
        padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, 0),
        child: StatusTrail(t.status),
      ),
      _tags => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        child: Align(alignment: Alignment.centerLeft, child: TagLine(t.tags)),
      ),
      _modified => _Text(shortDate(l10n, lastModified(t)), end: true),
      _ => _Text(
        levelValueLabel(
          l10n,
          _levelValue(t, id.substring(_levelPrefix.length)),
        ),
      ),
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: _Row(
            trailing: true,
            flexes: flexes,
            cells: [
              for (final column in columns)
                _HeaderCell(
                  label: column.label,
                  end: column.end,
                  sorted: _sortBy == column.id ? _ascending : null,
                  onTap: () => setState(() {
                    if (_sortBy != column.id) {
                      _sortBy = column.id;
                      _ascending = true;
                    } else if (_ascending) {
                      _ascending = false;
                    } else {
                      _sortBy = null;
                    }
                  }),
                ),
            ],
          ),
        ),
        Divider(height: Sizes.hairline, color: c.border),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              Space.xl,
              Space.xs,
              Space.xl,
              libraryBottomPadding(overviewOpen: selected != null),
            ),
            itemCount: titles.length,
            itemExtent: 40,
            itemBuilder: (context, i) {
              final t = titles[i];
              return TitleRow(
                key: ValueKey(t.id),
                title: t,
                selected: selected == t.id,
                child: _Row(
                  flexes: flexes,
                  cells: [for (final column in columns) cell(column.id, t)],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Value of the non-leaf level [key] of [t]; blank without it.
  static String _levelValue(Title t, String key) =>
      t.levels.keys.lastOrNull == key ? '' : t.levels[key] ?? '';

  /// Order of [a] and [b] by [column]; the empty values (no BPM, status or
  /// date) come last in both directions.
  static int _compare(_ColumnId column, Title a, Title b, bool ascending) {
    final direction = ascending ? 1 : -1;
    int text(String x, String y) =>
        direction * x.toLowerCase().compareTo(y.toLowerCase());
    int nullable<T extends Comparable<Object>>(T? x, T? y) => x == null
        ? (y == null ? 0 : 1)
        : (y == null ? -1 : direction * x.compareTo(y));
    return switch (column) {
      _name => text(titleName(a), titleName(b)),
      _versions => direction * a.versions.length.compareTo(b.versions.length),
      _tempo => nullable(tempoOf(a), tempoOf(b)),
      _status => nullable(
        a.status == null ? null : Title.defaultStatuses.indexOf(a.status!),
        b.status == null ? null : Title.defaultStatuses.indexOf(b.status!),
      ),
      _tags => text(a.tags.join(','), b.tags.join(',')),
      _modified => nullable(lastModified(a), lastModified(b)),
      _ => text(
        _levelValue(a, column.substring(_levelPrefix.length)),
        _levelValue(b, column.substring(_levelPrefix.length)),
      ),
    };
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cells,
    required this.flexes,
    this.trailing = false,
  });

  final List<Widget> cells;

  /// Widths of the cells, shared by the header and the rows.
  final List<int> flexes;

  /// Leaves room for the row actions (header).
  final bool trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, cell) in cells.indexed)
        Expanded(flex: flexes[i], child: cell),
      if (trailing) const SizedBox(width: titleActionsWidth + Space.s),
    ],
  );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.end,
    this.sorted,
    required this.onTap,
  });

  final String label;

  /// Right-aligned, like its figures.
  final bool end;

  /// Ascending (true), descending (false) or not sorted (null).
  final bool? sorted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableSurface(
      radius: 0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Space.s,
          horizontal: Space.sm,
        ),
        child: Row(
          mainAxisAlignment: end
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: context.legend.copyWith(
                  color: sorted == null ? c.muted : c.text,
                ),
              ),
            ),
            if (sorted case final ascending?)
              Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: IconSize.xs,
                color: c.text,
              ),
          ],
        ),
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell(this.title, {this.tags = const []});

  final Title title;

  /// Tags shown after the name.
  final List<String> tags;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: Space.sm),
      _Swatch(title.id),
      const SizedBox(width: Space.s),
      Flexible(
        flex: 3,
        child: Text(
          titleName(title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: Weights.medium),
        ),
      ),
      if (tags.isNotEmpty) ...[
        const SizedBox(width: Space.s),
        Flexible(flex: 2, child: TagLine(tags)),
      ] else
        const Spacer(),
    ],
  );
}

class _Text extends StatelessWidget {
  const _Text(this.text, {this.end = false});

  final String text;
  final bool end;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: context.readout,
    ),
  );
}

/// Side of the square of the colors of a title.
const _swatch = 18.0;

/// Small aurora swatch identifying a title in lists.
class _Swatch extends StatelessWidget {
  const _Swatch(this.id);

  final NodeId id;

  @override
  Widget build(BuildContext context) {
    final lights = AuroraPalette.of(
      id,
      light: Theme.of(context).brightness == Brightness.light,
    ).lights;
    return Container(
      width: _swatch,
      height: _swatch,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lights.first, lights.last],
        ),
      ),
    );
  }
}

/// Clickable title row: a click shows the title overview; its actions show
/// on hover at the end of the row.
class TitleRow extends ConsumerStatefulWidget {
  const TitleRow({
    super.key,
    required this.title,
    required this.selected,
    required this.child,
  });

  final Title title;
  final bool selected;
  final Widget child;

  @override
  ConsumerState<TitleRow> createState() => _TitleRowState();
}

class _TitleRowState extends ConsumerState<TitleRow> {
  var _hovered = false;

  @override
  void didUpdateWidget(TitleRow old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) revealSelectedTitle(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PressableSurface(
        selected: widget.selected,
        radius: Radii.xs,
        onTap: () =>
            ref.read(overviewProvider.notifier).toggle(widget.title.id),
        child: Row(
          children: [
            // Lit edge of the selected strip.
            AnimatedContainer(
              duration: Motion.fast,
              width: Sizes.bar,
              margin: const EdgeInsets.symmetric(vertical: Space.sm),
              color: widget.selected ? c.accent : Colors.transparent,
            ),
            Expanded(child: widget.child),
            TitleActions(widget.title, visible: _hovered || widget.selected),
            const SizedBox(width: Space.s),
          ],
        ),
      ),
    );
  }
}

/// Titles grouped by library, then by the levels above the title (SPEC
/// §5.2: Artist → Album → Title). Groups can be collapsed.
class TitleTree extends ConsumerStatefulWidget {
  const TitleTree(this.titles, {super.key});

  final List<Title> titles;

  @override
  ConsumerState<TitleTree> createState() => _TitleTreeState();
}

typedef _TreeRow = ({
  String key,
  int depth,
  String? group,
  Title? title,
  String? count,
});

/// Width of the versions and of the status columns of the tree rows, so that
/// they line up on every row.
const _versionsWidth = 120.0;
const _statusWidth = 200.0;

class _TitleTreeState extends ConsumerState<TitleTree> {
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final libraries = {
      for (final l in ref.watch(settingsProvider.select((s) => s.libraries)))
        l.id: l.displayName,
    };
    final byLibrary = {for (final t in widget.titles) t.libraryId: <Title>[]};
    for (final t in widget.titles) {
      byLibrary[t.libraryId]!.add(t);
    }
    final levelLibraries = ref.watch(indexedLibrariesProvider).values;
    final showTags = ref.watch(settingsProvider.select((s) => s.showTags));
    final counts = _childCounts(byLibrary, l10n, levelLibraries);
    final rows = <_TreeRow>[];
    final rootDepth = byLibrary.length > 1 ? 1 : 0;
    for (final MapEntry(key: id, value: titles) in byLibrary.entries) {
      if (rootDepth == 1) {
        rows.add((
          key: id,
          depth: 0,
          group: libraries[id] ?? id,
          title: null,
          count: counts[id],
        ));
        if (_collapsed.contains(id)) continue;
      }
      titles.sort((a, b) {
        final pa = [...parentLevels(a), titleName(a)].join('\u0000');
        final pb = [...parentLevels(b), titleName(b)].join('\u0000');
        return pa.toLowerCase().compareTo(pb.toLowerCase());
      });
      var open = <String>[];
      for (final t in titles) {
        final groups = parentLevels(t);
        var common = 0;
        while (common < open.length &&
            common < groups.length &&
            open[common] == groups[common]) {
          common++;
        }
        open = [...groups];
        for (var d = common; d < groups.length; d++) {
          final key = '$id/${groups.take(d + 1).join('/')}';
          if (_isHidden(key)) break;
          rows.add((
            key: key,
            depth: rootDepth + d,
            group: levelValueLabel(l10n, groups[d]),
            title: null,
            count: counts[key],
          ));
        }
        final key = '$id/${[...groups, t.id].join('/')}';
        if (!_isHidden(key)) {
          rows.add((
            key: key,
            depth: rootDepth + groups.length,
            group: null,
            title: t,
            count: null,
          ));
        }
      }
    }
    final selected = ref.watch(overviewProvider);

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        0,
        Space.xl,
        libraryBottomPadding(overviewOpen: selected != null),
      ),
      itemCount: rows.length,
      itemExtent: 36,
      itemBuilder: (context, i) {
        final row = rows[i];
        final indent = Space.l * row.depth;
        if (row.title case final t?) {
          return TitleRow(
            key: ValueKey(row.key),
            title: t,
            selected: selected == t.id,
            child: Padding(
              padding: EdgeInsets.only(left: indent + Space.l),
              child: Row(
                children: [
                  Expanded(
                    child: _NameCell(t, tags: showTags ? t.tags : const []),
                  ),
                  SizedBox(
                    width: _versionsWidth,
                    child: _Text(
                      l10n.versionCount(t.versions.length),
                      end: true,
                    ),
                  ),
                  SizedBox(
                    width: _statusWidth,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.sm,
                        Space.md,
                        Space.sm,
                        0,
                      ),
                      child: StatusTrail(t.status),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final collapsed = _collapsed.contains(row.key);
        return PressableSurface(
          key: ValueKey(row.key),
          radius: Radii.xs,
          onTap: () => setState(
            () => collapsed
                ? _collapsed.remove(row.key)
                : _collapsed.add(row.key),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: indent),
            child: Row(
              children: [
                Disclosure(collapsed ? Disclosure.right : Disclosure.down),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    row.group!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.legend.copyWith(color: c.text),
                  ),
                ),
                SizedBox(
                  width: _versionsWidth,
                  child: _Text(row.count ?? '', end: true),
                ),
                // Where the status and the row actions are on a title.
                const SizedBox(
                  width: _statusWidth + titleActionsWidth + Space.s,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Count of the children of every group, by its row key: the library, then
  /// each level group; labelled with the name of the level below it.
  static Map<String, String> _childCounts(
    Map<LibraryId, List<Title>> byLibrary,
    AppLocalizations l10n,
    Iterable<Library> libraries,
  ) {
    final children = <String, Set<String>>{};
    final childLevel = <String, String>{};
    for (final MapEntry(key: id, value: titles) in byLibrary.entries) {
      for (final t in titles) {
        final groups = parentLevels(t);
        final keys = [
          for (final e in t.levels.entries)
            if (e.value.isNotEmpty) e.key,
        ];
        // The library is above the first level; a group, above the next.
        for (var d = -1; d < groups.length; d++) {
          final group = d < 0 ? id : '$id/${groups.take(d + 1).join('/')}';
          final child = d + 1 < groups.length ? groups[d + 1] : '\u0000${t.id}';
          children
              .putIfAbsent(group, () => {})
              .add('${groups.take(d + 2).join('/')}/$child');
          if (keys.isNotEmpty) {
            childLevel[group] = keys[(d + 1).clamp(0, keys.length - 1)];
          }
        }
      }
    }
    return {
      for (final MapEntry(key: group, value: set) in children.entries)
        if (childLevel[group] case final key?)
          group: levelCountLabel(l10n, _levelOf(libraries, key), set.length),
    };
  }

  /// Whether a parent group of [key] is collapsed.
  bool _isHidden(String key) {
    for (var i = key.lastIndexOf('/'); i > 0; i = key.lastIndexOf('/', i - 1)) {
      if (_collapsed.contains(key.substring(0, i))) return true;
    }
    return false;
  }
}
