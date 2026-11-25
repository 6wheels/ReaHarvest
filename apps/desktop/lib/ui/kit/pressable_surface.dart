import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'surface.dart';

/// Clickable surface: a [color] (transparent by default) and a [side]
/// frame cut to the [radius], with the hover and focus feedback of the
/// theme. [selected] lights it like a selected row: a faint accent fill and
/// an accent frame, over the idle [color] and [side]. Disabled when [onTap]
/// is null: dimmed, unless [dimDisabled] is false (a surface inert by
/// design).
class PressableSurface extends StatelessWidget {
  const PressableSurface({
    super.key,
    required this.onTap,
    required this.child,
    this.color = Colors.transparent,
    this.side = BorderSide.none,
    this.radius = Radii.s,
    this.dimDisabled = true,
    this.selected = false,
  });

  final VoidCallback? onTap;
  final Widget child;
  final Color color;
  final BorderSide side;
  final double radius;
  final bool dimDisabled;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    final corners = BorderRadius.circular(radius);
    final surface = Surface(
      color: selected ? accent.withValues(alpha: Alpha.faint) : color,
      shape: RoundedRectangleBorder(
        borderRadius: corners,
        side: selected
            ? BorderSide(color: accent.withValues(alpha: Alpha.medium))
            : side,
      ),
      child: InkWell(borderRadius: corners, onTap: onTap, child: child),
    );
    return onTap == null && dimDisabled
        ? Opacity(opacity: Alpha.medium, child: surface)
        : surface;
  }
}
