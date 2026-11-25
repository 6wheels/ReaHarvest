import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'choice_light.dart';
import 'pressable_surface.dart';

/// Size of the track of a [LightSwitch]: room for two lights.
const _trackWidth = IconSize.ledL * 2 + Space.xs * 3;
const _trackHeight = IconSize.ledL + Space.xs * 2;

/// On/off switch: a [ChoiceLight] sliding in a frame, to the end and lit
/// when [value] is true, to the start and dark otherwise (position and
/// luminance, never the hue alone). Disabled when [onChanged] is null.
class LightSwitch extends StatelessWidget {
  const LightSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final changed = onChanged;
    return Semantics(
      toggled: value,
      enabled: changed != null,
      child: PressableSurface(
        onTap: changed == null ? null : () => changed(!value),
        color: value ? c.accent.withValues(alpha: Alpha.faint) : c.raised,
        side: BorderSide(
          color: value ? c.accent.withValues(alpha: Alpha.strong) : c.border,
        ),
        child: SizedBox(
          width: _trackWidth,
          height: _trackHeight,
          child: Padding(
            padding: const EdgeInsets.all(Space.xs),
            child: AnimatedAlign(
              duration: Motion.fast,
              curve: Motion.curve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: ChoiceLight(checked: value),
            ),
          ),
        ),
      ),
    );
  }
}
