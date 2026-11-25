import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';

/// Plain surface of the interface: a [color] (transparent by default) cut
/// to a [shape], optionally raised. Gives its descendants the material they
/// need to paint on (ink, text fields).
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.color = Colors.transparent,
    this.shape,
    this.elevation = 0,
    this.shadowColor,
  }) : panel = false;

  /// A panel or a menu: surface fill, hairline frame, `Radii.s` corners,
  /// raised by [elevation].
  const Surface.panel({super.key, required this.child, this.elevation = 0})
    : color = Colors.transparent,
      shape = null,
      shadowColor = null,
      panel = true;

  final Widget child;
  final Color color;
  final ShapeBorder? shape;
  final double elevation;
  final Color? shadowColor;
  final bool panel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: panel ? c.surface : color,
      shape: panel
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.s),
              side: BorderSide(color: c.border),
            )
          : shape,
      elevation: elevation,
      shadowColor: shadowColor,
      child: child,
    );
  }
}
