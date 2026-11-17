import 'package:flutter/material.dart' hide Title;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'widgets.dart';

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
        child: Pill(statusLabel(l10n, status), color: warningColor),
      );
    }

    final done = current == steps.length - 1;
    final next = widget.onDark
        ? Colors.white.withValues(alpha: 0.22)
        : c.border;
    final nextLabel = widget.onDark ? Colors.white70 : c.muted;
    Color colorOf(int i) => i < current || done
        ? c.ledGreen
        : i == current
        ? c.ledAmber
        : next;
    Color labelColorOf(int i) => i <= current || done ? colorOf(i) : nextLabel;
    final thickness = widget.large ? 6.0 : 4.0;
    final gap = widget.large ? 4.0 : 2.0;
    final base = context.legend.copyWith(fontSize: widget.large ? 10.5 : 9);
    TextStyle styleOf(int i) => base.copyWith(
      color: labelColorOf(i),
      fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
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
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: [
                        if (i == current && !done)
                          BoxShadow(
                            color: colorOf(i).withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: widget.large ? 6 : 3),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final segment = (width - gap * (steps.length - 1)) / steps.length;
              // The current label starts where its segment starts, like the
              // revealed one, and is pushed back at the end of the trail.
              double currentLeft() {
                final text = TextPainter(
                  text: TextSpan(
                    text: labelOf(steps[current]),
                    style: styleOf(current),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                final left = current * (segment + gap);
                final max = width - text.width;
                text.dispose();
                return left.clamp(0.0, max < 0 ? 0.0 : max);
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
                          child: fade(
                            _hovered,
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
                      left: currentLeft(),
                      top: 0,
                      child: fade(
                        !_hovered,
                        Text(
                          labelOf(steps[current]),
                          maxLines: 1,
                          softWrap: false,
                          style: styleOf(current),
                        ),
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
