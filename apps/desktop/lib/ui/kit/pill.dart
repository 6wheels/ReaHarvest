import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'disclosure.dart';
import 'pressable_surface.dart';

/// Console tag or key.
///
/// Without [onPressed] it is an inert tag (status, alerts, tags of a
/// title): mono capitals in a frame lit with [color] (muted by default),
/// with a small remove button when [onDeleted] is set.
///
/// With [onPressed] it is a key of the filter bar: a legend in a square
/// frame, lit with the accent when [active]; an optional [icon], a [count]
/// readout at the end and, when [menuOpen] is not null, the triangle of the
/// menu it opens.
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.color,
    this.icon,
    this.menuOpen,
    this.count,
    this.active = false,
    this.onPressed,
    this.onDeleted,
    this.deleteTooltip,
    this.uppercase = true,
  }) : assert(
         onPressed != null ||
             (icon == null && count == null && menuOpen == null && !active),
         'icon, count, menuOpen and active are for a key: give onPressed',
       );

  final String label;

  /// Color of an inert tag; the key takes its own from [active].
  final Color? color;

  /// Icon of a key.
  final IconData? icon;

  /// Whether the menu a key opens is open; null when it opens none.
  final bool? menuOpen;
  final int? count;
  final bool active;
  final VoidCallback? onPressed;

  /// Removes a tag: shows a remove button, named [deleteTooltip].
  final VoidCallback? onDeleted;
  final String? deleteTooltip;

  /// Whether an inert tag shows its label in capitals (a tag typed by the
  /// user keeps its case).
  final bool uppercase;

  @override
  Widget build(BuildContext context) =>
      onPressed == null ? _tag(context) : _key(context);

  Widget _tag(BuildContext context) {
    final color = this.color ?? context.colors.muted;
    return Container(
      // The remove button, when there is one, ends the tag on its own.
      padding: EdgeInsets.only(
        left: Space.sm,
        right: onDeleted == null ? Space.sm : 0,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: Alpha.tint),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: color.withValues(alpha: Alpha.medium)),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                child: Text(
                  uppercase ? label.toUpperCase() : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.legendSmall.copyWith(color: color),
                ),
              ),
            ),
            if (onDeleted case final onDeleted?) _remove(onDeleted, color),
          ],
        ),
      ),
    );
  }

  /// Remove button of a tag: a small cross, its target as high as the tag.
  Widget _remove(VoidCallback onDeleted, Color color) {
    final button = PressableSurface(
      onTap: onDeleted,
      radius: Radii.xs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Center(
          child: Icon(Icons.close_rounded, size: IconSize.xs, color: color),
        ),
      ),
    );
    return switch (deleteTooltip) {
      final tooltip? => Tooltip(message: tooltip, child: button),
      null => button,
    };
  }

  Widget _key(BuildContext context) {
    final c = context.colors;
    final color = active ? c.accent : c.muted;
    return PressableSurface(
      onTap: onPressed,
      selected: active,
      color: c.raised,
      side: BorderSide(color: c.border),
      child: SizedBox(
        height: Sizes.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: IconSize.s, color: color),
                const SizedBox(width: Space.sm),
              ],
              Text.rich(
                TextSpan(
                  text: label.toUpperCase(),
                  children: [
                    if (count != null)
                      TextSpan(
                        text: '$labelSeparator$count',
                        style: AppText.color(c.accent),
                      ),
                  ],
                ),
                style: context.legend.copyWith(
                  color: active ? c.text : c.muted,
                ),
              ),
              if (menuOpen case final open?) ...[
                const SizedBox(width: Space.xxs),
                Disclosure(
                  open ? Disclosure.up : Disclosure.down,
                  size: IconSize.xl,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
