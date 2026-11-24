import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';

/// Period of the sweep of a [Meter] of unknown progress.
const _sweepPeriod = Duration(milliseconds: 1400);

/// Opacity of the glow of a lit LED of a [Meter]; of the core and the body
/// of an unlit one.
const _meterGlow = 0.5;
const _unlitCore = 0.14;
const _unlitBody = 0.10;

/// Progress as a segmented level meter: narrow upright LEDs, green then
/// amber then red along the scale like a VU meter, the unlit ones faintly
/// tinted. An unknown [value] sweeps a few lit LEDs across, dimmer at both
/// ends.
class Meter extends StatefulWidget {
  const Meter(this.value, {super.key, this.height = 10});

  /// From 0 to 1; null when unknown.
  final double? value;
  final double height;

  @override
  State<Meter> createState() => _MeterState();
}

class _MeterState extends State<Meter> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: _sweepPeriod,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Meter old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.value == null) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    width: double.infinity,
    child: CustomPaint(
      painter: _MeterPainter(
        context.colors,
        widget.value,
        widget.value == null ? _controller : null,
      ),
    ),
  );
}

/// Paints the LEDs of a [Meter] on whole physical pixels, so that every LED
/// has the same width and every gap the same width at any size and screen
/// scale. Such a row rarely fills a width exactly: the number of LEDs (about
/// 24) is the one leaving the fewest pixels, shared at both ends.
class _MeterPainter extends CustomPainter {
  _MeterPainter(this.c, this.value, this.sweep) : super(repaint: sweep);

  final AppColors c;
  final double? value;

  /// Position of the sweep while the value is unknown.
  final Animation<double>? sweep;

  /// Usual number of LEDs, and the spread allowed around it.
  static const _segments = 24;
  static const _spread = 4;

  /// Space between two LEDs.
  static const _gap = 3.0;

  /// Width of the window lit while the progress is unknown, and the level of
  /// its two end LEDs.
  static const _window = 5;
  static const _edgeLevel = 0.45;

  /// Position on the scale where the LEDs turn amber, then red.
  static const _amberFrom = 0.7;
  static const _redFrom = 0.9;

  /// Corner radius of a LED, blur of its glow.
  static const _corner = 1.0;
  static const _glowBlur = 2.0;

  /// Lens of a lit LED: share of white in its core, then the opacity of the
  /// core and of the body of the LED, from off to fully lit.
  static const _lens = 0.35;
  static const _coreFloor = 0.4;
  static const _bodyFloor = 0.35;

  /// Color of the LED at [i] of [n] on the scale.
  Color _colorAt(int i, int n) {
    final position = i / (n - 1);
    return position < _amberFrom
        ? c.ledGreen
        : position < _redFrom
        ? c.ledAmber
        : c.ledRed;
  }

  /// Light level of the LED at [i] of [n], from 0 (off) to 1.
  double _levelAt(int i, int n) {
    if (value case final v?) return i < (v * n).round() ? 1 : 0;
    final head = ((sweep?.value ?? 0) * (n + _window)).floor();
    final offset = head - i;
    if (offset < 0 || offset >= _window) return 0;
    return offset == 0 || offset == _window - 1 ? _edgeLevel : 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Scale and position of this box on the screen, in physical pixels.
    final m = canvas.getTransform();
    final (sx, sy, tx, ty) = (m[0], m[5], m[12], m[13]);
    final left = tx.round();
    final width = (tx + size.width * sx).round() - left;
    final gap = (_gap * sx).round().clamp(1, 1 << 20);
    // LED count and width leaving the fewest pixels unused, nearest to 24.
    var (n, led, rest) = (0, 0, width);
    for (var d = 0; d <= _spread; d++) {
      for (final count in {_segments - d, _segments + d}) {
        final w = (width - gap * (count - 1)) ~/ count;
        final r = width - w * count - gap * (count - 1);
        if (w >= 1 && r < rest) (n, led, rest) = (count, w, r);
      }
    }
    if (n == 0) return;
    final start = left + rest ~/ 2;
    final top = (ty.roundToDouble() - ty) / sy;
    final height = (size.height * sy).round() / sy;
    for (var i = 0; i < n; i++) {
      final color = _colorAt(i, n);
      final level = _levelAt(i, n);
      final x = (start + i * (led + gap) - tx) / sx;
      final rect = Rect.fromLTWH(x, top, led / sx, height);
      final rrect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(_corner),
      );
      if (level > 0) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = color.withValues(alpha: _meterGlow * level)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, _glowBlur * level),
        );
      }
      // Brighter core, like the lens of a lit LED.
      final colors = level == 0
          ? [
              color.withValues(alpha: _unlitCore),
              color.withValues(alpha: _unlitBody),
            ]
          : [
              Color.lerp(
                color,
                Tone.white,
                _lens * level,
              )!.withValues(alpha: _coreFloor + (1 - _coreFloor) * level),
              color.withValues(alpha: _bodyFloor + (1 - _bodyFloor) * level),
            ];
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.value != value || old.c != c || old.sweep != sweep;
}
