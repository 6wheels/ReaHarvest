import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/migration_actions.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../layout_labels.dart';
import '../widgets.dart';
import 'fix_dialog.dart';

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
