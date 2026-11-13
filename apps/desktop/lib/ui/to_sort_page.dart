import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/library_scans.dart';
import '../state/migration_actions.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'fix_dialog.dart';
import 'layout_labels.dart';
import 'report_dialog.dart';
import 'title_detail.dart';
import 'widgets.dart';

/// Opens the "To sort" page over the library (SPEC §5.2).
Future<void> openToSort(BuildContext context) =>
    Navigator.of(context).push(overLibraryRoute((_) => const ToSortPage()));

/// Issues of the libraries grouped by kind, with a counter per kind
/// (SPEC §5.2, §5.8 step 3), and a guided move for misplaced projects. Back with the back button, Escape or
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
                  const Spacer(),
                  Consumer(
                    builder: (context, ref, _) => Tooltip(
                      message: l10n.fullScanTooltip,
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.read(libraryScansProvider).scanAll(full: true),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(l10n.fullScan),
                      ),
                    ),
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

/// A "To sort" item, as selected: it stays selected through a rescan as
/// long as an issue with the same key is still there.
typedef _Key = (LibraryId, ReportKind, String);

_Key _keyOf(LibraryIssue issue) => (issue.library, issue.kind, issue.item.path);

/// Issues on the media, record path or render target of a project, whose
/// detail lists the references or the value (one per line).
const _mediaKinds = {
  ReportKind.mediaOutsidePool,
  ReportKind.missingMedia,
  ReportKind.externalMedia,
  ReportKind.recordPathNotMedia,
  ReportKind.renderFileForm,
};

class _ToSortList extends ConsumerStatefulWidget {
  const _ToSortList();

  @override
  ConsumerState<_ToSortList> createState() => _ToSortListState();
}

/// Issues of the libraries by kind, the batch-fixable ones selectable
/// (#82): "Fix…" applies to the selected items of its section, or to all
/// of them when none is selected.
class _ToSortListState extends ConsumerState<_ToSortList> {
  final _selected = <_Key>{};

  /// Hint shown under the section of [kind], if any.
  static String? _hint(AppLocalizations l10n, ReportKind kind) =>
      switch (kind) {
        ReportKind.corrupted => l10n.corruptedHint,
        ReportKind.orphanNode => l10n.orphanNodesHint,
        ReportKind.duplicateVersionId => l10n.duplicateVersionIdHint,
        ReportKind.titleTooHigh ||
        ReportKind.misplacedLevel ||
        ReportKind.unknownValue ||
        ReportKind.outsideLayout => l10n.toSortFolderHint,
        _ => null,
      };

  /// Selected items among [issues].
  List<LibraryIssue> _selectedOf(List<LibraryIssue> issues) => [
    for (final i in issues)
      if (_selected.contains(_keyOf(i))) i,
  ];

  /// Selects every item of [issues], or none if all are selected.
  void _toggleAll(List<LibraryIssue> issues) => setState(() {
    final keys = issues.map(_keyOf);
    if (_selectedOf(issues).length == issues.length) {
      _selected.removeAll(keys);
    } else {
      _selected.addAll(keys);
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final issues = ref.watch(issuesProvider);
    final names = {
      for (final l in ref.watch(settingsProvider.select((s) => s.libraries)))
        l.id: l.displayName,
    };
    final multiple = {for (final i in issues) i.library}.length > 1;
    // Sorted by kind within each library: grouped across libraries here.
    final byKind = <ReportKind, List<LibraryIssue>>{};
    for (final i in issues) {
      byKind.putIfAbsent(i.kind, () => []).add(i);
    }
    final kinds = byKind.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    Widget muted(String value, TextStyle? style) =>
        Text(value, style: style?.copyWith(color: c.muted));
    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        if (issues.isNotEmpty) muted(l10n.toSortHint, text.bodyMedium),
        for (final kind in kinds) ...[
          const SizedBox(height: Space.l),
          _sectionHeader(l10n, kind, byKind[kind]!),
          if (_hint(l10n, kind) case final hint?) ...[
            const SizedBox(height: Space.xs),
            muted(hint, text.bodySmall),
          ],
          for (final issue in byKind[kind]!)
            _issueItem(context, ref, issue, multiple ? names : null),
        ],
      ],
    );
  }

  /// Label and counter of the section of [issues], all of [kind]; for a
  /// batch-fixable kind, its "select all" box, the number of selected
  /// items and "Fix…".
  Widget _sectionHeader(
    AppLocalizations l10n,
    ReportKind kind,
    List<LibraryIssue> issues,
  ) {
    final label = SectionLabel(
      '${reportKindLabel(l10n, kind)} · ${issues.length}',
    );
    if (!batchFixKinds.contains(kind)) return label;
    final selected = _selectedOf(issues);
    return Row(
      children: [
        Checkbox(
          tristate: true,
          value: selected.isEmpty
              ? false
              : selected.length == issues.length
              ? true
              : null,
          semanticLabel: l10n.selectAll,
          onChanged: (_) => _toggleAll(issues),
        ),
        Expanded(child: label),
        if (selected.isNotEmpty)
          Text(
            l10n.selectedCount(selected.length),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.colors.muted),
          ),
        TextButton(
          onPressed: () =>
              _fixAll(context, ref, kind, selected.isEmpty ? issues : selected),
          child: Text(l10n.fixAction),
        ),
      ],
    );
  }

  /// Card of [issue]; its library is named when [names] is set (several
  /// libraries have issues).
  Widget _issueItem(
    BuildContext context,
    WidgetRef ref,
    LibraryIssue issue,
    Map<LibraryId, String>? names,
  ) {
    final l10n = AppLocalizations.of(context);
    final ReportItem(:path, :detail, :level, :target) = issue.item;
    // An orphan node file stands for its folder.
    final shown = issue.kind == ReportKind.orphanNode
        ? p.posix.dirname(path)
        : path;
    final folder = p.posix.dirname(shown);
    final key = _keyOf(issue);
    return _Item(
      selected: batchFixKinds.contains(issue.kind)
          ? _selected.contains(key)
          : null,
      onSelected: (on) =>
          setState(() => on ? _selected.add(key) : _selected.remove(key)),
      title: p.posix.basename(shown),
      subtitle: [
        if (names != null) ?names[issue.library],
        if (folder != '.') folder,
      ].join(' · '),
      details: [
        if (level != null)
          l10n.issueExpectedLevel(layoutLevelLabel(l10n, level)),
        if (target != null) l10n.issueTarget(target),
        if (_mediaKinds.contains(issue.kind) && detail != null)
          if (detail.isEmpty)
            l10n.issueProjectFolder
          else
            ...detail.split('\n'),
      ],
      action: switch (issue.kind) {
        ReportKind.projectTooDeep ||
        ReportKind.projectTooShallow => OutlinedButton(
          onPressed: () => showSortDialog(
            context,
            library: issue.library,
            path: path,
            target: target,
          ),
          child: Text(l10n.sortAction),
        ),
        ReportKind.titleTooHigh ||
        ReportKind.misplacedLevel ||
        ReportKind.unknownValue ||
        ReportKind.outsideLayout => OutlinedButton(
          onPressed: () => showSortDialog(
            context,
            library: issue.library,
            path: path,
            target: target,
            folderLevel: level,
            chooseLevel: issue.kind == ReportKind.unknownValue,
          ),
          child: Text(l10n.sortAction),
        ),
        ReportKind.orphanNode => OutlinedButton(
          onPressed: () => _deleteOrphan(context, ref, issue),
          child: Text(l10n.deleteOrphanNode),
        ),
        _ => null,
      },
    );
  }

  /// Previews then applies the batch fix of [issues] of [kind], library by
  /// library, after the REAPER warning.
  Future<void> _fixAll(
    BuildContext context,
    WidgetRef ref,
    ReportKind kind,
    List<LibraryIssue> issues,
  ) async {
    final fixes = await showFixDialog(context, kind, issues);
    if (fixes == null || !context.mounted) return;
    await runProjectChange(context, ref, () async {
      for (final MapEntry(key: library, value: list) in fixes.entries) {
        await ref.read(migrationActionsProvider).fix(library, list);
      }
    });
  }

  Future<void> _deleteOrphan(
    BuildContext context,
    WidgetRef ref,
    LibraryIssue issue,
  ) async {
    final path = issue.item.path;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteOrphanNodeTitle),
        content: Text(l10n.deleteOrphanNodeHint(p.posix.dirname(path))),
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
          .read(migrationActionsProvider)
          .deleteOrphanNode(issue.library, path);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(l10n, error))),
      );
    }
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.title,
    required this.subtitle,
    this.details = const [],
    this.action,
    this.selected,
    this.onSelected,
  });

  /// Whether the item is selected; null if it cannot be.
  final bool? selected;
  final ValueChanged<bool>? onSelected;

  final String title;
  final String subtitle;

  /// Lines under the subtitle (expected level, proposed place).
  final List<String> details;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selected case final value?)
            Padding(
              padding: const EdgeInsets.only(right: Space.s),
              child: Checkbox(
                value: value,
                semanticLabel: title,
                onChanged: (on) => onSelected?.call(on!),
              ),
            ),
          Expanded(child: _content(context)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: text.bodySmall?.copyWith(color: c.muted)),
        for (final line in details) Text(line, style: text.bodySmall),
        if (action case final action?) ...[
          const SizedBox(height: Space.s),
          Align(alignment: Alignment.centerRight, child: action),
        ],
      ],
    );
  }
}

/// Guided move of the misplaced project [path] into a title of [library],
/// or of the folder [path] expected at [folderLevel] to its position
/// ("To sort", SPEC §5.2, §5.8 step 4); prefilled with [target] if known,
/// any other destination can be typed. With [chooseLevel], the level of
/// the folder can be changed (unknown values).
Future<void> showSortDialog(
  BuildContext context, {
  required LibraryId library,
  required String path,
  String? target,
  LayoutLevel? folderLevel,
  bool chooseLevel = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SortDialog(
    library: library,
    path: path,
    target: target,
    folderLevel: folderLevel,
    chooseLevel: chooseLevel,
  ),
);

class _SortDialog extends ConsumerStatefulWidget {
  const _SortDialog({
    required this.library,
    required this.path,
    this.target,
    this.folderLevel,
    this.chooseLevel = false,
  });

  final LibraryId library;
  final String path;
  final String? target;
  final LayoutLevel? folderLevel;
  final bool chooseLevel;

  @override
  ConsumerState<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends ConsumerState<_SortDialog> {
  late final Layout _layout;

  /// Index in the layout of the position: the title for a project, the
  /// expected (or chosen) level for a folder.
  late int _level;

  /// One value per layout level; those down to [_level] are shown.
  late final List<TextEditingController> _all;

  List<TextEditingController> get _values => _all.take(_level + 1).toList();

  @override
  void initState() {
    super.initState();
    _layout = ref.read(indexedLibrariesProvider)[widget.library]!.layout!;
    final key = (widget.folderLevel ?? _layout.leaf).key;
    _level = _layout.levels.indexWhere((l) => l.key == key);
    _all = [for (final _ in _layout.levels) TextEditingController()];
    _prefill();
  }

  /// Prefills the shown values from the target, else from the current
  /// folders and the file or folder name for the last level.
  void _prefill() {
    final count = _level + 1;
    final target = widget.target?.split('/');
    final folders = p.posix.dirname(widget.path).split('/')
      ..removeWhere((s) => s == '.');
    for (var i = 0; i < count; i++) {
      _all[i].text = target != null && target.length == count
          ? target[i]
          : i == count - 1
          ? p.posix.basenameWithoutExtension(widget.path)
          : (i < folders.length ? folders[i] : Layout.unassigned);
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => _values.every((c) => isValidFolderName(c.text.trim()));

  /// Existing values of level [i] under the values typed above it.
  List<String> _options(int i) => levelValues(
    ref.read(titlesProvider),
    {widget.library},
    _layout,
    i,
    [for (final c in _values.take(i)) c.text.trim()],
  );

  /// Closes the dialog and moves the project or folder, as a task whose
  /// report opens at the end.
  Future<void> _move() async {
    final navigator = Navigator.of(context);
    final values = [for (final c in _values) c.text.trim()];
    final service = ref.read(migrationActionsProvider);
    final library = widget.library;
    final path = widget.path;
    final folder = widget.folderLevel != null;
    await runProjectChange(context, ref, () {
      // Closed first: the report opens over the page, not over the dialog.
      navigator.pop();
      return folder
          ? service.fix(library, [MoveFolder(path, values.join('/'))])
          : service.moveToTitle(library, path, values);
    });
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
            if (widget.chooseLevel)
              Choice<int>(
                label: l10n.sortFolderIs,
                value: _level,
                options: {
                  for (final (j, l) in _layout.levels.indexed)
                    j: layoutLevelLabel(l10n, l),
                },
                onChanged: (j) => setState(() {
                  _level = j;
                  _prefill();
                }),
              ),
            for (var i = 0; i <= _level; i++) ...[
              const SizedBox(height: Space.m),
              LevelField(
                label: layoutLevelLabel(l10n, _layout.levels[i]),
                controller: _values[i],
                options: () => _options(i),
                error: isValidFolderName(_values[i].text.trim())
                    ? null
                    : l10n.invalidFolderName,
                onChanged: () => setState(() {}),
              ),
            ],
            if (widget.folderLevel != null &&
                mergesInto(
                  ref.read(titlesProvider),
                  widget.library,
                  widget.path,
                  [for (final c in _values) c.text.trim()].join('/'),
                )) ...[
              const SizedBox(height: Space.m),
              Text(
                l10n.sortMergeHint,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: c.muted),
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
