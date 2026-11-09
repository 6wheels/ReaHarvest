import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Row(
            children: [
              Expanded(
                child: SectionLabel(
                  '${reportKindLabel(l10n, kind)} · ${byKind[kind]!.length}',
                ),
              ),
              if (batchFixKinds.contains(kind))
                TextButton(
                  onPressed: () => _fixAll(context, ref, kind, byKind[kind]!),
                  child: Text(l10n.fixAction),
                ),
            ],
          ),
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

  /// Card of [issue]; its library is named when [names] is set (several
  /// libraries have issues).
  Widget _issueItem(
    BuildContext context,
    WidgetRef ref,
    LibraryIssue issue,
    Map<LibraryId, String>? names,
  ) {
    final l10n = AppLocalizations.of(context);
    final ReportItem(:path, :level, :target) = issue.item;
    // An orphan node file stands for its folder.
    final shown = issue.kind == ReportKind.orphanNode
        ? p.posix.dirname(path)
        : path;
    final folder = p.posix.dirname(shown);
    return _Item(
      title: p.posix.basename(shown),
      subtitle: [
        if (names != null) ?names[issue.library],
        if (folder != '.') folder,
      ].join(' · '),
      details: [
        if (level != null)
          l10n.issueExpectedLevel(layoutLevelLabel(l10n, level)),
        if (target != null) l10n.issueTarget(target),
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
        await ref.read(libraryServiceProvider).fix(library, list);
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
          .read(libraryServiceProvider)
          .deleteOrphanNode(issue.library, path);
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
    this.details = const [],
    this.action,
  });

  final String title;
  final String subtitle;

  /// Lines under the subtitle (expected level, proposed place).
  final List<String> details;
  final Widget? action;

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
          for (final line in details) Text(line, style: text.bodySmall),
          if (action case final action?) ...[
            const SizedBox(height: Space.s),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }
}

/// Guided move of the misplaced project [path] into a title of [library],
/// or of the folder [path] expected at [folderLevel] to its position
/// ("To sort", SPEC §5.2, §5.8 step 4); prefilled with [target] if known,
/// any other destination can be typed.
Future<void> showSortDialog(
  BuildContext context, {
  required LibraryId library,
  required String path,
  String? target,
  LayoutLevel? folderLevel,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SortDialog(
    library: library,
    path: path,
    target: target,
    folderLevel: folderLevel,
  ),
);

class _SortDialog extends ConsumerStatefulWidget {
  const _SortDialog({
    required this.library,
    required this.path,
    this.target,
    this.folderLevel,
  });

  final LibraryId library;
  final String path;
  final String? target;
  final LayoutLevel? folderLevel;

  @override
  ConsumerState<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends ConsumerState<_SortDialog> {
  late final Layout _layout;

  /// Levels down to the position: the title for a project, the expected
  /// level for a folder.
  late final List<LayoutLevel> _levels;
  late final List<TextEditingController> _values;

  @override
  void initState() {
    super.initState();
    _layout = ref.read(indexedLibrariesProvider)[widget.library]!.layout!;
    final key = (widget.folderLevel ?? _layout.leaf).key;
    _levels = [
      ..._layout.levels.takeWhile((l) => l.key != key),
      _layout.levels.firstWhere((l) => l.key == key),
    ];
    // Prefilled from the target, else from the current folders and the
    // file or folder name for the last level.
    final count = _levels.length;
    final target = widget.target?.split('/');
    final folders = p.posix.dirname(widget.path).split('/')
      ..removeWhere((s) => s == '.');
    _values = [
      for (var i = 0; i < count; i++)
        TextEditingController(
          text: target != null && target.length == count
              ? target[i]
              : i == count - 1
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

  /// Moves the project; its report opens at the end of the task.
  Future<void> _move() async {
    final navigator = Navigator.of(context);
    final done = await runProjectChange(context, ref, () {
      final values = [for (final c in _values) c.text.trim()];
      final service = ref.read(libraryServiceProvider);
      return widget.folderLevel == null
          ? service.moveToTitle(widget.library, widget.path, values)
          : service.fix(widget.library, [
              MoveFolder(widget.path, values.join('/')),
            ]);
    });
    if (done) navigator.pop();
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
            for (final (i, level) in _levels.indexed) ...[
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
