import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Side of the thumb at rest and while hovered, focused or dragged.
const _thumbSize = 14.0;
const _thumbSizeActive = 16.0;

/// Glow of the thumb at rest and while active.
const _glow = 6.0;
const _glowActive = 12.0;

/// Opacity of the glow of the thumb.
const _glowAlpha = 0.5;

/// Thumb of a slider drawn like a lit [ChoiceLight]: a square with nearly
/// square corners, filled with the accent and framed, glowing. It grows,
/// glows wider and takes the frame of the text color while hovered,
/// focused or dragged; disabled, it is dark and unlit. Differences of
/// shape, luminance and glow, never of hue.
class LightThumbShape extends SliderComponentShape {
  const LightThumbShape({
    required this.accent,
    required this.active,
    required this.off,
    required this.background,
  });

  /// Fill and frame of the lit thumb.
  final Color accent;

  /// Frame while hovered, focused or dragged.
  final Color active;

  /// Frame of the disabled thumb.
  final Color off;

  /// Fill of the thumb while not lit: it hides the track behind it.
  final Color background;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_thumbSizeActive);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final enabled = enableAnimation.value;
    final t = activationAnimation.value;
    final side = _thumbSize + (_thumbSizeActive - _thumbSize) * t;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: side, height: side),
      const Radius.circular(Radii.s),
    );
    if (enabled > 0) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = accent.withValues(alpha: _glowAlpha * enabled)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (_glow + (_glowActive - _glow) * t) / 2,
          ),
      );
    }
    canvas.drawRRect(
      rect,
      Paint()..color = Color.lerp(background, accent, enabled)!,
    );
    canvas.drawRRect(
      rect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Sizes.hairline
        ..color = Color.lerp(off, Color.lerp(accent, active, t), enabled)!,
    );
  }
}

/// Invisible area around the thumb of a slider: it has the size of the
/// active thumb, so that hovering the thumb is detected, and draws nothing.
class LightHoverShape extends SliderComponentShape {
  const LightHoverShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_thumbSizeActive);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}
