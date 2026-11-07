import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'aurora.dart';
import 'labels.dart';

enum _Column { name, tags, versions, tempo, status, modified }

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
    final selected = ref.watch(panelProvider);
    final labels = {
      _Column.name: l10n.columnName,
      _Column.tags: '',
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
        Divider(height: 1, color: c.border),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.xs,
              Space.xl,
              Space.xl,
            ),
            itemCount: titles.length,
            itemExtent: 40,
            itemBuilder: (context, i) {
              final t = titles[i];
              return TitleRow(
                key: ValueKey(t.id),
                title: t,
                selected: selected == TitlePanel(t.id),
                child: _Row(
                  cells: [
                    _NameCell(t),
                    _Text(
                      parentTags(t)
                          .map((v) => tagValueLabel(l10n, v))
                          .join(' · '),
                    ),
                    _Text('${t.versions.length}'),
                    _Text('${tempoOf(t) ?? ''}'),
                    _Text(t.status == null ? '' : statusLabel(l10n, t.status!)),
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
      _Column.tags => text(parentTags(a).join('/'), parentTags(b).join('/')),
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
  const _Row({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, cell) in cells.indexed)
        Expanded(flex: _flex[i], child: cell),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: 6),
        child: Row(
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: sorted == null ? c.muted : c.text,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            if (sorted case final ascending?)
              Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
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
      const SizedBox(width: 6),
      _Swatch(title.id),
      const SizedBox(width: Space.s),
      Expanded(
        child: Text(
          titleName(title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500),
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
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.colors.muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// Small aurora swatch identifying a title in lists.
class _Swatch extends StatelessWidget {
  const _Swatch(this.id);

  final NodeId id;

  @override
  Widget build(BuildContext context) {
    final lights = AuroraPalette.of(id).lights;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lights.first, lights.last],
        ),
      ),
    );
  }
}

/// Clickable title row opening the detail panel.
class TitleRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Material(
      color: selected ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            ref.read(panelProvider.notifier).toggle(TitlePanel(title.id)),
        child: child,
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
        final pa = [...parentTags(a), titleName(a)].join('\u0000');
        final pb = [...parentTags(b), titleName(b)].join('\u0000');
        return pa.toLowerCase().compareTo(pb.toLowerCase());
      });
      var open = <String>[];
      for (final t in titles) {
        final groups = parentTags(t);
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
            group: tagValueLabel(l10n, groups[d]),
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
    final selected = ref.watch(panelProvider);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      itemCount: rows.length,
      itemExtent: 36,
      itemBuilder: (context, i) {
        final row = rows[i];
        final indent = Space.l * row.depth;
        if (row.title case final t?) {
          return TitleRow(
            key: ValueKey(row.key),
            title: t,
            selected: selected == TitlePanel(t.id),
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
        return InkWell(
          key: ValueKey(row.key),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(
            () => collapsed
                ? _collapsed.remove(row.key)
                : _collapsed.add(row.key),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: indent),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: collapsed ? -0.25 : 0,
                  duration: Motion.fast,
                  child: Icon(Icons.expand_more_rounded, color: c.muted),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    row.group!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
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
