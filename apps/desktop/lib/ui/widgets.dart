import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/reaper_actions.dart';
import '../state/reaper.dart';
import '../theme/app_theme.dart';

/// Color of warnings (missing plugins, duplicates).
const warningColor = Color(0xFFE5A04D);

/// Small console tag (status, alerts): mono capitals in a lit frame.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.xs),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.legend.copyWith(color: color, fontSize: 9.5),
    ),
  );
}

/// How a [Led] shines.
enum LedMode {
  /// Lit and still.
  steady,

  /// Breathes from off to its color (work in progress).
  pulse,

  /// Blinks on and off, slowly (failure).
  blink,
}

/// Status light: a small dot, glowing when [lit], still, breathing or
/// blinking according to [mode].
class Led extends StatefulWidget {
  const Led(
    this.color, {
    super.key,
    this.lit = true,
    this.size = 7,
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

  @override
  void initState() {
    super.initState();
    _animate();
  }

  @override
  void didUpdateWidget(Led old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode || old.lit != widget.lit) _animate();
  }

  void _animate() {
    switch (widget.lit ? widget.mode : LedMode.steady) {
      case LedMode.steady:
        _controller
          ..stop()
          ..value = 1;
      case LedMode.pulse:
        _controller
          ..duration = const Duration(milliseconds: 1100)
          ..repeat(reverse: true);
      case LedMode.blink:
        _controller
          ..duration = const Duration(milliseconds: 1600)
          ..repeat();
    }
  }

  @override
  void dispose() {
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
            : switch (widget.mode) {
                LedMode.steady => 1.0,
                LedMode.pulse => Curves.easeInOut.transform(t),
                // On for the first half of the cycle, with soft edges.
                LedMode.blink =>
                  t < 0.5
                      ? (t * 12).clamp(0.0, 1.0)
                      : (1 - (t - 0.5) * 12).clamp(0.0, 1.0),
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
                  color: widget.color.withValues(alpha: 0.6 * level),
                  blurRadius: size * (0.6 + level),
                ),
            ],
          ),
        );
      },
    );
  }
}

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
  static const _segments = 24;

  /// Width of the window lit while the progress is unknown.
  static const _window = 5;

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
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

  /// Color of the LED at [i] on the scale.
  Color _colorAt(AppColors c, int i) {
    final position = i / (_segments - 1);
    return position < 0.7
        ? c.ledGreen
        : position < 0.9
        ? c.ledAmber
        : c.ledRed;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = widget.value;
        // Light level of the LED at [i], from 0 (off) to 1.
        double level(int i) {
          if (value != null) return i < (value * _segments).round() ? 1 : 0;
          final head = (_controller.value * (_segments + _window)).floor();
          final offset = head - i;
          if (offset < 0 || offset >= _window) return 0;
          return offset == 0 || offset == _window - 1 ? 0.45 : 1;
        }

        return Row(
          spacing: 2,
          children: [
            for (var i = 0; i < _segments; i++)
              Expanded(
                child: _MeterLed(_colorAt(c, i), level(i), widget.height),
              ),
          ],
        );
      },
    );
  }
}

/// One LED of a [Meter].
class _MeterLed extends StatelessWidget {
  const _MeterLed(this.color, this.level, this.height);

  final Color color;
  final double level;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(1),
      // Brighter core, like the lens of a lit LED.
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: level == 0
            ? [color.withValues(alpha: 0.14), color.withValues(alpha: 0.10)]
            : [
                Color.lerp(
                  color,
                  Colors.white,
                  0.35 * level,
                )!.withValues(alpha: 0.4 + 0.6 * level),
                color.withValues(alpha: 0.35 + 0.65 * level),
              ],
      ),
      boxShadow: [
        if (level > 0)
          BoxShadow(
            color: color.withValues(alpha: 0.5 * level),
            blurRadius: 4 * level,
          ),
      ],
    ),
  );
}

/// Waiting for content: an amber light breathing in the middle.
class BusyLight extends StatelessWidget {
  const BusyLight({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Led(context.colors.ledAmber, size: 10, mode: LedMode.pulse),
  );
}

/// Legend heading the entries of a menu; not an entry itself.
class MenuLegend extends StatelessWidget {
  const MenuLegend(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
    child: Text(
      label.toUpperCase(),
      style: context.legend.copyWith(fontSize: 9.5),
    ),
  );
}

/// Square light of a checkable menu entry, lit when [checked].
class ChoiceLight extends StatelessWidget {
  const ChoiceLight({super.key, required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: Motion.fast,
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: checked ? c.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: checked ? c.accent : c.muted),
        boxShadow: [
          if (checked)
            BoxShadow(color: c.accent.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
    );
  }
}

/// Button label hidden behind a breathing light while [busy], keeping the
/// button size.
class BusyLabel extends StatelessWidget {
  const BusyLabel(this.label, {super.key, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Opacity(opacity: busy ? 0 : 1, child: Text(label)),
      if (busy) Led(context.colors.ledAmber, size: 8, mode: LedMode.pulse),
    ],
  );
}

/// Upper-case legend heading a section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: context.legend);
}

/// Runs [change] of a project file, after a confirmation when REAPER is
/// running (SPEC §5.7); failures are reported in a snackbar.
Future<bool> runProjectChange(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() change,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (await ref.read(reaperRunningProvider)()) {
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.reaperOpenTitle),
        content: Text(l10n.reaperOpenHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.continueAnyway),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }
  try {
    await change();
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(l10n, error))),
    );
    return false;
  }
}

/// Opens [version] of [title] in REAPER; problems are reported in a
/// snackbar.
Future<void> openVersionInReaper(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (!await ref.read(reaperActionsProvider).openVersion(title, version)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.reaperNotFound)));
    }
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(l10n, error))),
    );
  }
}

/// Text shown when an action fails with [error].
String failureMessage(AppLocalizations l10n, Object error) =>
    error is ProjectEncodingException
    ? l10n.projectEncodingFailed
    : l10n.actionFailed('$error');
