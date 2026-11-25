import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'choice_light.dart';
import 'pressable_surface.dart';

/// One choice among several, a row with a [ChoiceLight] lit when [selected],
/// its [label] and an optional [hint] under it, and an optional [trailing]
/// widget at the end of the row. Disabled when [onTap] is null.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.hint,
    this.trailing,
  });

  final bool selected;
  final String label;
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    enabled: onTap != null,
    child: PressableSurface(
      onTap: onTap,
      radius: Radii.xs,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s,
          vertical: Space.xs,
        ),
        child: Row(
          children: [
            ChoiceLight(checked: selected),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.type.body),
                  if (hint != null)
                    Text(
                      hint!,
                      style: context.type.small.copyWith(
                        color: context.colors.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: Space.s),
              trailing,
            ],
          ],
        ),
      ),
    ),
  );
}
