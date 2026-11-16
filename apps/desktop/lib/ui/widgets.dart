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

  /// Width of the window lit while the progress is unknown.
  static const _window = 5;

  /// Color of the LED at [i] of [n] on the scale.
  Color _colorAt(int i, int n) {
    final position = i / (n - 1);
    return position < 0.7
        ? c.ledGreen
        : position < 0.9
        ? c.ledAmber
        : c.ledRed;
  }

  /// Light level of the LED at [i] of [n], from 0 (off) to 1.
  double _levelAt(int i, int n) {
    if (value case final v?) return i < (v * n).round() ? 1 : 0;
    final head = ((sweep?.value ?? 0) * (n + _window)).floor();
    final offset = head - i;
    if (offset < 0 || offset >= _window) return 0;
    return offset == 0 || offset == _window - 1 ? 0.45 : 1;
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
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(1));
      if (level > 0) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = color.withValues(alpha: 0.5 * level)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * level),
        );
      }
      // Brighter core, like the lens of a lit LED.
      final colors = level == 0
          ? [color.withValues(alpha: 0.14), color.withValues(alpha: 0.10)]
          : [
              Color.lerp(
                color,
                Colors.white,
                0.35 * level,
              )!.withValues(alpha: 0.4 + 0.6 * level),
              color.withValues(alpha: 0.35 + 0.65 * level),
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

/// Drop-down field: a text field look (same height as the fields and the
/// buttons) opening a console menu of [options] (value -> label), the
/// current one lit.
class Dropdown<T> extends StatelessWidget {
  const Dropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
  });

  final T? value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 2),
      menuChildren: [
        for (final MapEntry(:key, value: text) in options.entries)
          MenuItemButton(
            leadingIcon: ChoiceLight(checked: key == value),
            onPressed: () => onChanged(key),
            child: Text(text),
          ),
      ],
      builder: (context, controller, _) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: InputDecorator(
            isEmpty: value == null,
            isFocused: controller.isOpen,
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: Disclosure(
                controller.isOpen ? Disclosure.up : Disclosure.down,
                color: controller.isOpen ? c.accent : c.muted,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 0,
              ),
            ),
            child: Text(
              options[value] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}

/// REAPER logo, the icon of the actions opening a project in REAPER
/// (used with the permission of Cockos, see `assets/third_party/reaper`).
class ReaperIcon extends StatelessWidget {
  const ReaperIcon({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/third_party/reaper/reaper.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
  );
}

/// Small square action of a row or a card: an [icon] (an [Icon] or any
/// 16 px widget), lit on hover like every icon button (see the theme). Over
/// an aurora ([onAurora]) it sits on a frosted pad.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onAurora = false,
  });

  /// Size of the action, square (the icon button size of the theme).
  static const size = 28.0;

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool onAurora;

  @override
  Widget build(BuildContext context) {
    if (!onAurora) {
      return IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pad = dark ? Colors.black : Colors.white;
    final ink = dark ? Colors.white : context.colors.text;
    bool lit(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      // Same hover as elsewhere: the pad thickens, the icon brightens.
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => pad.withValues(
            alpha: (dark ? 0.35 : 0.6) + (lit(states) ? 0.2 : 0),
          ),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? ink.withValues(alpha: 0.45)
              : lit(states)
              ? ink
              : ink.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Opens the title detail: an expand icon.
class OpenDetailAction extends StatelessWidget {
  const OpenDetailAction({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.onAurora = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final bool onAurora;

  @override
  Widget build(BuildContext context) => IconAction(
    icon: const Icon(Icons.open_in_full_rounded),
    tooltip: tooltip,
    onPressed: onPressed,
    onAurora: onAurora,
  );
}

/// Small filled triangle telling whether something is open, turning to
/// its new direction: [right] then [down] for a fold, [down] then [up] for
/// a menu.
class Disclosure extends StatelessWidget {
  const Disclosure(this.turns, {super.key, this.size = 22, this.color});

  static const right = 0.0;
  static const down = 0.25;
  static const up = 0.75;

  /// Direction, in turns from pointing right.
  final double turns;
  final double size;

  /// Muted when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: turns,
    duration: Motion.fast,
    curve: Motion.curve,
    child: Icon(
      Icons.arrow_right_rounded,
      size: size,
      color: color ?? context.colors.muted,
    ),
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
