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
import 'overview.dart';
import 'status_trail.dart';
import 'title_actions.dart';

enum _Column { name, levels, versions, tempo, status, modified }

/// Dense table of titles, sortable by column (SPEC §5.2).
class TitleList extends ConsumerStatefulWidget {
  const TitleList(this.titles, {super.key});

  final List<Title> titles;

  @override
  ConsumerState<TitleList> createState() => _TitleListState();
}

class _TitleListState extends ConsumerState<TitleList> {
  /// Null keeps the search order (best match first).
  _Column? _sortBy;
  var _ascending = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final titles = [...widget.titles];
    if (_sortBy case final column?) {
      titles.sort((a, b) {
        final r = _compare(l10n, column, a, b);
        return _ascending ? r : -r;
      });
    }
    final selected = ref.watch(overviewProvider);
    final labels = {
      _Column.name: l10n.columnName,
      _Column.levels: '',
      _Column.versions: l10n.versions,
      _Column.tempo: 'BPM',
      _Column.status: l10n.filterStatus,
      _Column.modified: l10n.columnModified,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: _Row(
            trailing: true,
            cells: [
              for (final column in _Column.values)
                _HeaderCell(
                  label: labels[column]!,
                  sorted: _sortBy == column ? _ascending : null,
                  onTap: () => setState(() {
                    if (_sortBy != column) {
                      _sortBy = column;
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
                  cells: [
                    _NameCell(t),
                    _Text(
                      parentLevels(t)
                          .map((v) => levelValueLabel(l10n, v))
                          .join(' · '),
                    ),
                    _Text('${t.versions.length}'),
                    _Text('${tempoOf(t) ?? ''}'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.sm,
                        Space.md,
                        Space.sm,
                        0,
                      ),
                      child: StatusTrail(t.status),
                    ),
                    _Text(shortDate(l10n, lastModified(t))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static int _compare(AppLocalizations l10n, _Column column, Title a, Title b) {
    int text(String x, String y) => x.toLowerCase().compareTo(y.toLowerCase());
    int nullable<T extends Comparable<Object>>(T? x, T? y) =>
        x == null ? (y == null ? 0 : 1) : (y == null ? -1 : x.compareTo(y));
    return switch (column) {
      _Column.name => text(titleName(a), titleName(b)),
      _Column.levels => text(
        parentLevels(a).join('/'),
        parentLevels(b).join('/'),
      ),
      _Column.versions => a.versions.length.compareTo(b.versions.length),
      _Column.tempo => nullable(tempoOf(a), tempoOf(b)),
      _Column.status => nullable(
        a.status == null ? null : Title.defaultStatuses.indexOf(a.status!),
        b.status == null ? null : Title.defaultStatuses.indexOf(b.status!),
      ),
      _Column.modified => nullable(lastModified(a), lastModified(b)),
    };
  }
}

/// Column widths of the list, shared by the header and the rows.
const _flex = [5, 4, 1, 1, 2, 2];

class _Row extends StatelessWidget {
  const _Row({required this.cells, this.trailing = false});

  final List<Widget> cells;

  /// Leaves room for the row actions (header).
  final bool trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, cell) in cells.indexed)
        Expanded(flex: _flex[i], child: cell),
      if (trailing) const SizedBox(width: titleActionsWidth + Space.s),
    ],
  );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, this.sorted, required this.onTap});

  final String label;

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
  const _NameCell(this.title);

  final Title title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: Space.sm),
      _Swatch(title.id),
      const SizedBox(width: Space.s),
      Expanded(
        child: Text(
          titleName(title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: Weights.medium),
        ),
      ),
    ],
  );
}

class _Text extends StatelessWidget {
  const _Text(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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

typedef _TreeRow = ({String key, int depth, String? group, Title? title});

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
    final rows = <_TreeRow>[];
    final rootDepth = byLibrary.length > 1 ? 1 : 0;
    for (final MapEntry(key: id, value: titles) in byLibrary.entries) {
      if (rootDepth == 1) {
        rows.add((key: id, depth: 0, group: libraries[id] ?? id, title: null));
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
          ));
        }
        final key = '$id/${[...groups, t.id].join('/')}';
        if (!_isHidden(key)) {
          rows.add((
            key: key,
            depth: rootDepth + groups.length,
            group: null,
            title: t,
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
                  Expanded(child: _NameCell(t)),
                  _Text(l10n.versionCount(t.versions.length)),
                  _Text(t.status == null ? '' : statusLabel(l10n, t.status!)),
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
              ],
            ),
          ),
        );
      },
    );
  }

  /// Whether a parent group of [key] is collapsed.
  bool _isHidden(String key) {
    for (var i = key.lastIndexOf('/'); i > 0; i = key.lastIndexOf('/', i - 1)) {
      if (_collapsed.contains(key.substring(0, i))) return true;
    }
    return false;
  }
}
