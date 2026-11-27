import 'package:material_ui/material_ui.dart' hide Title;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';

/// Width of the member and status drop-downs of a version.
const _choiceWidth = 150.0;

/// Fields of one version of a "To sort" title card (SPEC §5.8 step 4): its
/// project, its label (required) and its folder (a valid folder name; a
/// reserved one gets ` (2)`), its member when the library declares
/// [members], its status when [statuses] is set, and the move of its
/// project to another title ([onMove]). Each change gives the version with
/// the user's choices to [onChanged].
class VersionFields extends StatefulWidget {
  const VersionFields({
    super.key,
    required this.project,
    required this.version,
    required this.onChanged,
    this.members = const [],
    this.statuses,
    this.onMove,
  });

  /// Name of its project, relative to the card.
  final String project;

  /// The version as proposed, with the choices made so far.
  final FixVersion version;
  final ValueChanged<FixVersion> onChanged;

  /// Members of the library; none: no member field.
  final List<Member> members;

  /// Statuses offered (key to label); null: no status field (the card gives
  /// one to all its versions).
  final Map<String, String>? statuses;
  final VoidCallback? onMove;

  @override
  State<VersionFields> createState() => _VersionFieldsState();
}

class _VersionFieldsState extends State<VersionFields> {
  late final _label = TextEditingController(text: widget.version.label);
  late final _folder = TextEditingController(text: widget.version.folder);

  /// The "Move a project" button, built once: a button rebuilt restarts a
  /// theme animation (its `AnimatedTheme` gets a new `ThemeData` on every
  /// build), and a keystroke would rebuild it. Dropped when the language
  /// changes or the button appears or goes.
  Widget? _move;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _move = null;
  }

  @override
  void didUpdateWidget(VersionFields old) {
    super.didUpdateWidget(old);
    if ((old.onMove == null) != (widget.onMove == null)) _move = null;
  }

  @override
  void dispose() {
    _label.dispose();
    _folder.dispose();
    super.dispose();
  }

  /// Gives the version with the texts of the fields, [owner] and [status].
  void _emit(MemberId? owner, String? status) => widget.onChanged(
    widget.version.withChoices(
      folder: _folder.text,
      label: _label.text,
      owner: owner,
      status: status,
    ),
  );

  /// A text changed: the member and status kept.
  void _typed() => _emit(widget.version.owner, widget.version.status);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final v = widget.version;
    final folder = _folder.text;
    final statuses = widget.statuses;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.readoutSmall,
                ),
              ),
              if (widget.onMove != null)
                _move ??= IconAction(
                  icon: const Icon(Icons.drive_file_move_outline),
                  tooltip: l10n.toSortMoveProject,
                  onPressed: () => widget.onMove?.call(),
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s,
            children: [
              Expanded(
                child: TextField(
                  controller: _label,
                  onChanged: (_) => setState(_typed),
                  decoration: InputDecoration(
                    labelText: l10n.toSortVersionLabel,
                    isDense: true,
                    errorText: v.label.trim().isEmpty
                        ? l10n.labelRequired
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _folder,
                  onChanged: (_) => setState(_typed),
                  decoration: InputDecoration(
                    labelText: l10n.toSortVersionFolder,
                    isDense: true,
                    errorText: isValidFolderName(folder)
                        ? null
                        : l10n.invalidFolderName,
                    helperText: isReservedFolder(folder)
                        ? l10n.toSortReservedFolder
                        : null,
                  ),
                ),
              ),
              if (widget.members.isNotEmpty)
                SizedBox(
                  width: _choiceWidth,
                  child: Dropdown<MemberId?>(
                    label: l10n.toSortVersionMember,
                    value: v.owner,
                    options: {
                      null: l10n.noMember,
                      for (final m in widget.members) m.id: m.name,
                    },
                    onChanged: (owner) => _emit(owner, v.status),
                  ),
                ),
              if (statuses != null)
                SizedBox(
                  width: _choiceWidth,
                  child: Dropdown<String?>(
                    label: l10n.toSortVersionStatus,
                    value: v.status,
                    options: {null: l10n.noStatus, ...statuses},
                    onChanged: (status) => _emit(v.owner, status),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
