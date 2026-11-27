import 'package:material_ui/material_ui.dart' hide Title;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import '../layout_labels.dart';

/// Width of the dialog.
const _width = 420.0;

/// Asks the title of [library] the [project] moves to ("Move a project",
/// SPEC §5.8 step 4): one field per layout level, with the values suggested
/// by [levelSuggestions] from its indexed [titles], or free input (a new
/// value says that the level will be created). The path of the title
/// ([layoutTarget]); null if cancelled.
Future<String?> askProjectTarget(
  BuildContext context, {
  required Library library,
  required List<Title> titles,
  required String project,
}) => showGlassDialog<String>(
  context,
  (_) => MoveProjectDialog(library: library, titles: titles, project: project),
);

/// The dialog of [askProjectTarget].
class MoveProjectDialog extends StatefulWidget {
  const MoveProjectDialog({
    super.key,
    required this.library,
    required this.titles,
    required this.project,
  });

  final Library library;
  final List<Title> titles;
  final String project;

  @override
  State<MoveProjectDialog> createState() => _MoveProjectDialogState();
}

class _MoveProjectDialogState extends State<MoveProjectDialog> {
  late final Layout _layout = widget.library.layout!;
  late final _values = [
    for (final _ in _layout.levels) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final c in _values) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _target =>
      layoutTarget(_layout, [for (final c in _values) c.text]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = _target;
    return AlertDialog(
      title: Text(l10n.toSortMoveProjectTitle(widget.project)),
      content: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.toSortMoveProjectHint,
              style: context.type.caption.copyWith(color: context.colors.muted),
            ),
            const SizedBox(height: Space.m),
            for (final (i, level) in _layout.levels.indexed)
              LevelField(
                label: layoutLevelLabel(l10n, level),
                controller: _values[i],
                autofocus: i == 0,
                options: () => levelSuggestions(widget.library, widget.titles, [
                  for (final c in _values.take(i)) c.text.trim(),
                ]),
                error: null,
                newValueHint: l10n.levelWillBeCreated,
                onChanged: () => setState(() {}),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: target == null
              ? null
              : () => Navigator.of(context).pop(target),
          child: Text(l10n.fixAction),
        ),
      ],
    );
  }
}
