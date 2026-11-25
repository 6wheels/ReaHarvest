import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Title;

import '../../theme/app_theme.dart';

/// Periods of the animations of a [Led]: breathing and blinking.
const _pulsePeriod = Duration(milliseconds: 1100);
const _blinkHalf = Duration(milliseconds: 800);
const _blinkSwitch = Duration(milliseconds: 120);

/// Curve of the breathing of a [Led], spread of its glow around the dot.
const _pulseCurve = Curves.easeInOut;
const _glowSpread = 0.6;

/// Opacity of the glow of a lit [Led].
const _ledGlow = 0.6;

/// How a [Led] shines.
enum LedMode {
  /// Lit and still.
  steady,

  /// Breathes from off to its color (work in progress).
  pulse,

  /// Blinks on and off (failure).
  blink,
}

/// Status light: a small dot, glowing when [lit], still, breathing or
/// blinking according to [mode]; always still when the system asks for
/// fewer animations.
class Led extends StatefulWidget {
  const Led(
    this.color, {
    super.key,
    this.lit = true,
    this.size = IconSize.ledM,
    this.mode = LedMode.steady,
  });

  final Color color;
  final bool lit;
  final double size;
  final LedMode mode;

  @override
  State<Led> createState() => _LedState();
}

class _LedState extends State<Led> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);

  /// Toggles the blink: the controller only runs during a switch, so an
  /// idle app redraws nothing.
  Timer? _blinkTimer;

  /// The system asks for fewer animations: the light stays still.
  var _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _animate();
  }

  @override
  void didUpdateWidget(Led old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode || old.lit != widget.lit) _animate();
  }

  LedMode get _mode => _still ? LedMode.steady : widget.mode;

  void _animate() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    switch (widget.lit ? _mode : LedMode.steady) {
      case LedMode.steady:
        _controller
          ..stop()
          ..value = 1;
      case LedMode.pulse:
        _controller
          ..duration = _pulsePeriod
          ..repeat(reverse: true);
      case LedMode.blink:
        _controller
          ..stop()
          ..value = 1;
        _blinkTimer = Timer.periodic(_blinkHalf, (_) {
          _controller.animateTo(
            _controller.value > 0.5 ? 0 : 1,
            duration: _blinkSwitch,
          );
        });
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final off = context.colors.border;
    final size = widget.size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Light level from 0 (off) to 1 (fully lit).
        final level = !widget.lit
            ? 0.0
            : switch (_mode) {
                LedMode.steady => 1.0,
                LedMode.pulse => _pulseCurve.transform(t),
                LedMode.blink => t,
              };
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(off, widget.color, level),
            boxShadow: [
              if (level > 0)
                BoxShadow(
                  color: widget.color.withValues(alpha: _ledGlow * level),
                  blurRadius: size * (_glowSpread + level),
                ),
            ],
          ),
        );
      },
    );
  }
}
