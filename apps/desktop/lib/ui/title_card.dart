import 'package:flutter/material.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' as domain show Title;

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
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
class TitleCard extends StatefulWidget {
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
  State<TitleCard> createState() => _TitleCardState();
}

class _TitleCardState extends State<TitleCard> {
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
    final levels = [
      for (final v in parentLevels(t)) levelValueLabel(l10n, v).toUpperCase(),
    ].join(labelSeparator);
    final bpm = tempoOf(t);
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
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text(
                          levels,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.legendSmall,
                        ),
                      ),
                      const SizedBox(width: Space.s),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: Alignment.topRight,
                                child: TitleActions(
                                  t,
                                  visible: _hovered || widget.selected,
                                  onAurora: true,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                titleName(t),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: light ? c.text : Tone.white,
                                      height: Leading.tight,
                                    ),
                              ),
                            ],
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
                        if (bpm != null) _Readout('BPM', '$bpm'),
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
