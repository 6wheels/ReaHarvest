import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';

/// Glow of a [ChoiceLight] and its opacity (partial fill, partial glow, lit
/// glow), size of the bar of its partial state.
const _lightGlow = 6.0;

const _partialFill = 0.25;

const _partialGlow = 0.3;

const _litGlow = 0.5;

const _dashWidth = 6.0;

const _dashHeight = 2.0;

/// Square light of a checkable entry, lit when [checked]; half lit with a
/// bar when null (some of a group selected).
class ChoiceLight extends StatelessWidget {
  const ChoiceLight({super.key, required this.checked});

  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final partial = checked == null;
    final on = checked ?? true;
    return AnimatedContainer(
      duration: Motion.fast,
      width: IconSize.ledL,
      height: IconSize.ledL,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: partial
            ? c.accent.withValues(alpha: _partialFill)
            : on
            ? c.accent
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: on ? c.accent : c.muted),
        boxShadow: [
          if (on)
            BoxShadow(
              color: c.accent.withValues(
                alpha: partial ? _partialGlow : _litGlow,
              ),
              blurRadius: _lightGlow,
            ),
        ],
      ),
      child: partial
          ? Container(width: _dashWidth, height: _dashHeight, color: c.accent)
          : null,
    );
  }
}
