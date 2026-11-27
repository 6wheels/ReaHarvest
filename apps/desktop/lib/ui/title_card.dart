import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' as domain show Title;

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'aurora.dart';
import 'kit/kit.dart';
import 'labels.dart';
import 'overview.dart';
import 'status_trail.dart';
import 'title_actions.dart';

/// Height of the bar of the actions of a card.
const _barHeight = 28.0;

/// Square title card, like a rack module (SPEC §5.2).
class TitleCard extends ConsumerStatefulWidget {
  const TitleCard(
    this.title, {
    super.key,
    this.selected = false,
    this.toAdopt = 0,
    this.onTap,
  });

  final domain.Title title;

  /// Number of versions to adopt, hidden when none.
  final int toAdopt;

  /// Whether the title is shown in the overview.
  final bool selected;

  final VoidCallback? onTap;

  @override
  ConsumerState<TitleCard> createState() => _TitleCardState();
}

class _TitleCardState extends ConsumerState<TitleCard> {
  var _hovered = false;

  /// Aurora drift: moves forward on each hover, never back.
  var _phase = 0.0;

  @override
  void didUpdateWidget(TitleCard old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) revealSelectedTitle(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final palette = AuroraPalette.of(t.id, light: light);
    final levels = [for (final v in parentLevels(t)) levelValueLabel(l10n, v)]
        .join(labelSeparator);
    final bpm = tempoOf(t);
    final sampleRate = latestSampleRate(t);
    final figures = [
      if (bpm != null) l10n.bpm(bpm),
      if (sampleRate != null) sampleRateLabel(sampleRate),
    ].join(labelSeparator);
    final ink = light ? c.text : Tone.white;
    final showTags = ref.watch(settingsProvider.select((s) => s.showTags));
    final date = shortDate(l10n, lastModified(t));
    final frame = widget.selected
        ? c.accent
        : _hovered
        ? c.muted.withValues(alpha: Alpha.strong)
        : c.border;

    return MouseRegion(
      onEnter: (_) => setState(() {
        _hovered = true;
        _phase += 1;
      }),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        // Rack module: a header strip, the aurora as an inset screen, the
        // readouts and the status lights below.
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.s),
            border: Border.all(color: frame),
            boxShadow: [
              if (widget.selected)
                BoxShadow(
                  color: c.accent.withValues(alpha: Alpha.tint),
                  blurRadius: Blur.m,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _barHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  child: Row(
                    children: [
                      Led(c.accent, lit: widget.selected, size: IconSize.ledS),
                      const Spacer(),
                      Text(date, style: context.type.readoutSmall),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: _phase),
                            duration: Motion.slow * 2,
                            curve: Curves.easeInOut,
                            builder: (_, phase, _) => CustomPaint(
                              painter: AuroraPainter(palette, phase: phase),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(Space.md),
                          child: _AuroraText(
                            name: titleName(t),
                            levels: levels,
                            figures: figures,
                            ink: ink,
                            actions: TitleActions(
                              t,
                              visible: _hovered || widget.selected,
                              onAurora: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  Space.s,
                  Space.md,
                  Space.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _Readout(l10n.versionsUnit, '${t.versions.length}'),
                        Expanded(
                          child: Text(
                            widget.toAdopt > 0
                                ? l10n
                                      .toAdoptCount(widget.toAdopt)
                                      .toUpperCase()
                                : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: context.type.legendSmall.copyWith(
                              color: c.ledAmber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showTags && t.tags.isNotEmpty) ...[
                      const SizedBox(height: Space.s),
                      TagLine(t.tags),
                    ],
                    const SizedBox(height: Space.s),
                    StatusTrail(t.status),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figure with its unit, like a console readout: `VER 12`.
class _Readout extends StatelessWidget {
  const _Readout(this.unit, this.value);

  final String unit;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Space.m),
    child: Text.rich(
      TextSpan(
        text: '$unit ',
        style: context.type.legendSmall,
        children: [
          TextSpan(
            text: value,
            style: context.readout.copyWith(
              color: context.colors.text,
              fontWeight: Weights.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Text over the aurora of a card: the title on one line, centered vertically
/// on its own, the levels (artist, album…) below it, the actions at the top
/// right and the figures at the bottom right. The levels are dropped when the
/// card is too small for them; every line is cut by an ellipsis.
class _AuroraText extends StatelessWidget {
  const _AuroraText({
    required this.name,
    required this.levels,
    required this.figures,
    required this.ink,
    required this.actions,
  });

  final String name;
  final String levels;
  final String figures;
  final Color ink;
  final Widget actions;

  static double _lineHeight(
    BuildContext context,
    TextStyle style,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final nameStyle = text.titleLarge!.copyWith(
      color: ink,
      height: Leading.tight,
    );
    final levelsStyle = text.bodyMedium!.copyWith(color: ink);
    final figuresStyle = context.type.readoutSmall.copyWith(color: ink);
    final scaler = MediaQuery.textScalerOf(context);
    final nameHeight = _lineHeight(context, nameStyle, scaler);
    final levelsHeight = _lineHeight(context, levelsStyle, scaler);
    final rowHeight = _lineHeight(context, figuresStyle, scaler);
    return Stack(
      children: [
        // The title alone is centered in the aurora; the levels go below it,
        // and are dropped when they would reach the figures.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final levelsTop = (height + nameHeight) / 2;
              final withLevels =
                  levels.isNotEmpty &&
                  levelsTop + levelsHeight <= height - rowHeight;
              return ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (height - nameHeight) / 2,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
                    if (withLevels)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: levelsTop,
                        child: Text(
                          levels,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: levelsStyle,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Align(alignment: Alignment.topRight, child: actions),
        if (figures.isNotEmpty)
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              figures,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: figuresStyle,
            ),
          ),
      ],
    );
  }
}
