import 'package:material_ui/material_ui.dart' hide Title;

import '../../theme/app_theme.dart';

/// Small square action of a row or a card: an [icon] (an [Icon] or any
/// 16 px widget) glowing in the accent on hover (see the theme). Over an
/// aurora ([onAurora]) it sits on a small frosted pad with a hairline, to
/// stand out.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onAurora = false,
  });

  /// Size of the action, square (the icon button size of the theme).
  static const size = IconSize.action;

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool onAurora;

  @override
  Widget build(BuildContext context) {
    // Explicit, so that a field holding it (suffix) does not restyle it.
    final theme = Theme.of(context).iconButtonTheme.style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      style: onAurora
          ? glowButtonStyle(
              context,
              ink: dark ? Tone.white : context.colors.text,
            ).merge(theme)
          : theme,
    );
    if (!onAurora) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? Tone.black.withValues(alpha: Alpha.medium)
            : Tone.white.withValues(alpha: Alpha.strong),
        borderRadius: BorderRadius.circular(Radii.s),
      ),
      child: button,
    );
  }
}
