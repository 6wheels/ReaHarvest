import 'package:flutter/material.dart' hide Title;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'kit/kit.dart';
import 'labels.dart';

/// Thickness of the bars of the trail, large and small.
const _barLarge = 6.0;
const _barSmall = 4.0;

/// Progress of a title through the statuses (SPEC §5.9), as a row of
/// lights: one segment per status, passed ones green, the current one
/// amber and glowing, the next ones off.
/// Only the current status shows its label, free to run under the
/// neighbouring segments; hovering reveals every label under its segment.
/// The last status ("done") reached shows the whole trail green.
class StatusTrail extends StatefulWidget {
  const StatusTrail(
    this.status, {
    super.key,
    this.large = false,
    this.onDark = false,
  });

  /// Title status key; null when the title has none (all grey).
  final String? status;

  /// Thicker segments and bigger labels (title detail header).
  final bool large;

  /// Drawn over the aurora of a card.
  final bool onDark;

  @override
  State<StatusTrail> createState() => _StatusTrailState();
}

class _StatusTrailState extends State<StatusTrail> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    const steps = Title.defaultStatuses;
    final status = widget.status;
    final current = status == null ? -1 : steps.indexOf(status);

    // A custom status is not on the trail: shown as a plain label.
    if (status != null && current < 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Pill(statusLabel(l10n, status), color: context.colors.ledAmber),
      );
    }

    final done = current == steps.length - 1;
    final next = widget.onDark
        ? Tone.white.withValues(alpha: Alpha.soft)
        : c.border;
    final nextLabel = widget.onDark
        ? Tone.white.withValues(alpha: Alpha.strong)
        : c.muted;
    Color colorOf(int i) => i < current || done
        ? c.ledGreen
        : i == current
        ? c.ledAmber
        : next;
    Color labelColorOf(int i) => i <= current || done ? colorOf(i) : nextLabel;
    final thickness = widget.large ? _barLarge : _barSmall;
    final gap = widget.large ? Space.xs : Space.xxs;
    final base = widget.large ? context.legend : context.type.legendSmall;
    TextStyle styleOf(int i) => base.copyWith(
      color: labelColorOf(i),
      fontWeight: i == current ? Weights.bold : Weights.medium,
    );
    String labelOf(String step) => statusLabel(l10n, step).toUpperCase();

    // Labels only fade: any move would make them jump on hover.
    Widget fade(bool visible, Widget child) => AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: Motion.medium,
      curve: Motion.curve,
      child: child,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final i in Iterable.generate(steps.length)) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: AnimatedContainer(
                    duration: Motion.medium,
                    curve: Motion.curve,
                    height: thickness,
                    decoration: BoxDecoration(
                      color: colorOf(i),
                      borderRadius: BorderRadius.circular(Radii.xs),
                      boxShadow: [
                        if (i == current && !done)
                          BoxShadow(
                            color: colorOf(i).withValues(alpha: Alpha.strong),
                            blurRadius: Blur.s,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: widget.large ? Space.sm : Space.xxs),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final segment = (width - gap * (steps.length - 1)) / steps.length;
              // The extent of the current label: it starts where its segment
              // starts, like the revealed one, and is pushed back at the end
              // of the trail.
              var left = 0.0;
              var labelWidth = 0.0;
              if (current >= 0) {
                final text = TextPainter(
                  text: TextSpan(
                    text: labelOf(steps[current]),
                    style: styleOf(current),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                labelWidth = text.width;
                text.dispose();
                final max = width - labelWidth;
                left = (current * (segment + gap)).clamp(
                  0.0,
                  max < 0 ? 0.0 : max,
                );
              }

              // Whether the label of segment [i] stays clear of the current
              // one.
              bool clear(int i) {
                final start = i * (segment + gap);
                return i != current &&
                    (start + segment <= left || start >= left + labelWidth);
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Every label under its segment, revealed on hover.
                  Row(
                    children: [
                      for (final (i, step) in steps.indexed) ...[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(
                          // The current label is the one below: it stays
                          // as it is, so that hovering never dims it, and
                          // no label is revealed under it.
                          child: fade(
                            _hovered && clear(i),
                            Text(
                              labelOf(step),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: styleOf(i),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // The current label alone, not clipped to its segment.
                  if (current >= 0)
                    Positioned(
                      left: left,
                      top: 0,
                      child: Text(
                        labelOf(steps[current]),
                        maxLines: 1,
                        softWrap: false,
                        style: styleOf(current),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
