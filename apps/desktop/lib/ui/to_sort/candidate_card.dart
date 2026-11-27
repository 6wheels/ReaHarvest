import 'package:material_ui/material_ui.dart' hide Title;

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import 'to_sort_item.dart';

/// Width of the drop-down of the status given to every version.
const _statusWidth = 150.0;

/// Card of a title candidate in "To sort" (SPEC §5.2, §5.8 steps 3 and 4):
/// a selectable [Item] naming what is wrong ([issues]) and the [fix]
/// proposed, the [moves] it makes, then its [versions] (their fields), the
/// status given to every version and the Force switch.
///
/// A move of an [ancestorMove] (the misplaced folder above the title, moved
/// along) can be dropped with [onMoveAncestors]. With [statuses], a status
/// field gives one status to every version ([sameStatus]), else each
/// version has its own.
class CandidateCard extends StatelessWidget {
  const CandidateCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.issues,
    required this.fix,
    required this.versions,
    required this.force,
    required this.onForce,
    this.moves = const [],
    this.ancestorMove,
    this.moveAncestors = true,
    this.onMoveAncestors,
    this.statuses,
    this.sameStatus = false,
    this.onSameStatus,
    this.status,
    this.onStatus,
    this.selected,
    this.onSelected,
  });

  final String title;
  final String subtitle;

  /// What is wrong, one line each.
  final List<String> issues;

  /// The fix proposed, in words.
  final String fix;

  /// The moves of the title the fix makes, in words.
  final List<String> moves;

  /// The move of a misplaced ancestor composed with the move of the title,
  /// in words; null if none.
  final String? ancestorMove;
  final bool moveAncestors;
  final ValueChanged<bool>? onMoveAncestors;

  /// The fields of each version.
  final List<Widget> versions;

  /// Statuses of the library (key to label); null: no status field.
  final Map<String, String>? statuses;
  final bool sameStatus;
  final ValueChanged<bool>? onSameStatus;

  /// The status given to every version with [sameStatus].
  final String? status;
  final ValueChanged<String?>? onStatus;

  /// Whether the fix is forced (`MigrationFix.force`).
  final bool force;
  final ValueChanged<bool> onForce;

  final bool? selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = context.type.caption.copyWith(color: context.colors.muted);
    final statuses = this.statuses;
    return Item(
      title: title,
      subtitle: subtitle,
      details: issues,
      selected: selected,
      onSelected: onSelected,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fix, style: context.type.body),
          for (final move in moves) Text(move, style: muted),
          if (ancestorMove case final ancestor?)
            CheckRow(
              value: moveAncestors,
              label: ancestor,
              onChanged: onMoveAncestors,
            ),
          ...versions,
          const SizedBox(height: Space.s),
          Row(
            spacing: Space.s,
            children: [
              if (statuses != null) ...[
                Expanded(
                  child: CheckRow(
                    value: sameStatus,
                    label: l10n.toSortSameStatus,
                    onChanged: onSameStatus,
                  ),
                ),
                if (sameStatus)
                  SizedBox(
                    width: _statusWidth,
                    child: Dropdown<String?>(
                      label: l10n.toSortVersionStatus,
                      value: status,
                      options: {null: l10n.noStatus, ...statuses},
                      onChanged: (s) => onStatus?.call(s),
                    ),
                  ),
              ] else
                const Spacer(),
              Tooltip(
                message: l10n.toSortForceHint,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    Text(l10n.toSortForce, style: context.type.body),
                    LightSwitch(value: force, onChanged: onForce),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
