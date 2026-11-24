// Specimens of the style tokens, for the UI showcase: the type scale, the
// alpha levels, the icon sizes and the accents of both themes side by side.
// Nothing here tells two things apart by hue alone: every swatch carries its
// name, its hex code, its luminance and its contrast ratios.
import 'package:flutter/material.dart';
import 'package:reaharvest_library/reaharvest_library.dart'
    show AccentPreference;

import 'theme/app_theme.dart';
import 'ui/widgets.dart';

/// Name of each text style of the type scale, with its style.
List<(String, TextStyle)> _scale(AppText type) => [
  ('micro', type.micro),
  ('small', type.small),
  ('caption', type.caption),
  ('body', type.body),
  ('item', type.item),
  ('title', type.title),
  ('legend', type.legend),
  ('legendSmall', type.legendSmall),
  ('readout', type.readout),
  ('readoutSmall', type.readoutSmall),
];

/// Every named text style, with its name and its size.
class TypeScaleSpecimen extends StatelessWidget {
  const TypeScaleSpecimen({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (name, style) in _scale(context.type))
        Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  '$name  ${style.fontSize}',
                  style: context.type.readoutSmall,
                ),
              ),
              Expanded(
                child: Text(
                  'Mix 0123 Slow Tide',
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// The alpha levels over the surface, each with its name and its value.
class AlphaSpecimen extends StatelessWidget {
  const AlphaSpecimen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const levels = [
      ('faint', Alpha.faint),
      ('tint', Alpha.tint),
      ('soft', Alpha.soft),
      ('medium', Alpha.medium),
      ('strong', Alpha.strong),
      ('dense', Alpha.dense),
    ];
    return Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final (name, level) in levels)
          Container(
            width: 96,
            padding: const EdgeInsets.all(Space.s),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: level),
              borderRadius: BorderRadius.circular(Radii.s),
              border: Border.all(
                color: c.accent.withValues(alpha: Alpha.medium),
              ),
            ),
            child: Text(
              '$name\n$level',
              style: context.type.readoutSmall.copyWith(
                color: _readable(
                  Color.alphaBlend(
                    c.accent.withValues(alpha: level),
                    c.background,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The icon sizes, each with its name and its value.
class IconSizeSpecimen extends StatelessWidget {
  const IconSizeSpecimen({super.key});

  @override
  Widget build(BuildContext context) {
    const sizes = [
      ('xs', IconSize.xs),
      ('s', IconSize.s),
      ('m', IconSize.m),
      ('l', IconSize.l),
      ('xl', IconSize.xl),
      ('hero', IconSize.hero),
    ];
    return Wrap(
      spacing: Space.m,
      runSpacing: Space.s,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final (name, size) in sizes)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, size: size),
              Text('$name $size', style: context.type.readoutSmall),
            ],
          ),
      ],
    );
  }
}

/// The text color of the two themes with the higher contrast over [fill]:
/// the label of a swatch stays readable at any alpha.
Color _readable(Color fill) {
  final (dark, light) = (AppColors.dark.text, AppColors.light.text);
  return _contrast(dark, fill) >= _contrast(light, fill) ? dark : light;
}

/// Contrast ratio of two colors (WCAG).
double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color color) {
  final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16);
  return '#${rgb.toUpperCase().padLeft(6, '0')}';
}

String _name(AccentPreference p) => p.name.toUpperCase();

/// Minimum contrast of a component (a light, a border) over its background
/// and of text over it (WCAG AA).
const _minComponent = 3.0;
const _minText = 4.5;

/// The 6 accents on both themes: for each one, the name, the hex code, the
/// luminance and the contrast ratios, then real components, lit and unlit,
/// so that they differ by luminance, shape and glow, never by hue alone.
class AccentMatrix extends StatelessWidget {
  const AccentMatrix({super.key});

  /// Rank of [p] among the accents by luminance, 1 the darkest.
  static int _rank(AccentPreference p, Brightness brightness) {
    final lum = {
      for (final a in AccentPreference.values)
        a: Accents.of(a, brightness).computeLuminance(),
    };
    final sorted = AccentPreference.values.toList()
      ..sort((a, b) => lum[a]!.compareTo(lum[b]!));
    return sorted.indexOf(p) + 1;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final p in AccentPreference.values)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Wrap(
            spacing: Space.m,
            runSpacing: Space.m,
            children: [for (final b in Brightness.values) _AccentCell(p, b)],
          ),
        ),
    ],
  );
}

class _AccentCell extends StatelessWidget {
  const _AccentCell(this.preference, this.brightness);

  final AccentPreference preference;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final theme = buildTheme(brightness, accent: preference);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final c = context.colors;
          final type = context.type;
          final accent = c.accent;
          final onBackground = _contrast(accent, c.background);
          final onSurface = _contrast(accent, c.surface);
          String verdict(double ratio, double min) =>
              '${ratio.toStringAsFixed(1)}:1 ${ratio >= min ? 'PASS' : 'FAIL'}';
          Widget line(String text) => Text(text, style: type.readoutSmall);
          return Container(
            width: 460,
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(Radii.s),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_name(preference)} — ${brightness.name.toUpperCase()}',
                  style: type.legend.copyWith(color: c.text),
                ),
                const SizedBox(height: Space.xs),
                line(
                  '${_hex(accent)}   luminance '
                  '${accent.computeLuminance().toStringAsFixed(3)}',
                ),
                line(
                  'rank ${AccentMatrix._rank(preference, brightness)}/6 '
                  'darkest to lightest',
                ),
                line('vs background ${verdict(onBackground, _minComponent)}'),
                line('vs surface (text) ${verdict(onSurface, _minText)}'),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Key')),
                    Pill('Status', color: accent),
                    Led(accent),
                    Led(accent, lit: false),
                    const ChoiceLight(checked: true),
                    const ChoiceLight(checked: false),
                    _Row(selected: true),
                    _Row(selected: false),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A selected and an unselected row: the selection shows by the fill, the
/// bar and the border, not by the accent hue.
class _Row extends StatelessWidget {
  const _Row({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 110,
      padding: const EdgeInsets.all(Space.s),
      decoration: BoxDecoration(
        color: selected ? c.accent.withValues(alpha: Alpha.faint) : c.surface,
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(
          color: selected ? c.accent.withValues(alpha: Alpha.medium) : c.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: Space.xxs,
            height: Space.m,
            color: selected ? c.accent : c.muted,
          ),
          const SizedBox(width: Space.s),
          Text(selected ? 'SELECTED' : 'IDLE', style: context.legend),
        ],
      ),
    );
  }
}
