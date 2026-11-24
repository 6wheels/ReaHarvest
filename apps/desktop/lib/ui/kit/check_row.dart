import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'choice_light.dart';
import 'pressable_surface.dart';

/// A setting switched on or off: a row with a [ChoiceLight] lit when
/// [value] is true and its [label] to the right. Disabled when [onChanged]
/// is null.
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    return Semantics(
      checked: value,
      enabled: changed != null,
      child: PressableSurface(
        onTap: changed == null ? null : () => changed(!value),
        radius: Radii.xs,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s,
            vertical: Space.xs,
          ),
          child: Row(
            children: [
              ChoiceLight(checked: value),
              const SizedBox(width: Space.s),
              Expanded(child: Text(label, style: context.type.body)),
            ],
          ),
        ),
      ),
    );
  }
}
