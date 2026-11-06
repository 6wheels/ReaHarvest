import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Colors of an aurora visual, derived from a stable seed (the title id),
/// so that a title always looks the same and titles look different.
@immutable
final class AuroraPalette {
  const AuroraPalette._(this.sky, this.lights, this.seed);

  factory AuroraPalette.of(String seed) {
    final hash = _fnv1a(seed);
    final hue = (hash % 360).toDouble();
    HSLColor at(double offset, double s, double l) =>
        HSLColor.fromAHSL(1, (hue + offset) % 360, s, l);
    return AuroraPalette._(
      at(200, 0.45, 0.09).toColor(),
      [
        at(0, 0.72, 0.58).toColor(),
        at(38, 0.68, 0.55).toColor(),
        at(78, 0.62, 0.62).toColor(),
      ],
      hash,
    );
  }

  /// Night sky behind the lights.
  final Color sky;

  /// Light curtains, back to front.
  final List<Color> lights;

  /// Hash of the seed, also used to place the curtains.
  final int seed;

  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  @override
  bool operator ==(Object other) => other is AuroraPalette && other.seed == seed;

  @override
  int get hashCode => seed;
}

/// Paints soft light curtains over a night sky. [phase] (0..1) drifts the
/// curtains slightly, for hover animations. Gradients only (no blur), so it
/// stays cheap to repaint.
final class AuroraPainter extends CustomPainter {
  const AuroraPainter(this.palette, {this.phase = 0});

  final AuroraPalette palette;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = palette.sky);
    final seed = palette.seed;
    for (final (i, color) in palette.lights.indexed) {
      // Pseudo-random but stable placement from the seed bits.
      final bits = (seed >> (i * 7)) & 0x7f;
      final x = 0.15 + (bits & 0x0f) / 15 * 0.7;
      final y = 0.25 + ((bits >> 4) & 0x07) / 7 * 0.35;
      final drift = math.sin((phase + i / 3) * math.pi) * 0.06 * phase;
      final center = Offset(
        size.width * (x + drift),
        size.height * (y - drift / 2),
      );
      final radius = size.shortestSide * (0.55 + i * 0.08);
      canvas.save();
      // Stretch vertically and tilt: curtain shape.
      canvas.translate(center.dx, center.dy);
      canvas.rotate((bits.isEven ? -1 : 1) * (0.25 + i * 0.12));
      canvas.scale(0.55, 1.35);
      final shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.85),
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.screen,
      );
      canvas.restore();
    }
    // Bottom shade for text legibility.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x00000000), Color(0xB0000000)],
          stops: [0, 0.4, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(AuroraPainter old) =>
      old.palette != palette || old.phase != phase;
}
