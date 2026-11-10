import 'package:flutter/material.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' as domain show Title;

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../theme/app_theme.dart';
import 'aurora.dart';
import 'labels.dart';
import 'status_trail.dart';
import 'title_actions.dart';

/// Square title card, like a record sleeve (SPEC §5.2).
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
  Widget build(BuildContext context) {
    final t = widget.title;
    final l10n = AppLocalizations.of(context);
    final palette = AuroraPalette.of(t.id);
    final name = titleName(t);
    final subtitle = [for (final v in parentTags(t)) tagValueLabel(l10n, v)]
        .join(' · ');
    final meta = [
      l10n.versionCount(t.versions.length),
      if (widget.toAdopt > 0) l10n.toAdoptCount(widget.toAdopt),
      if (tempoOf(t) case final bpm?) l10n.bpm(bpm),
    ].join(' · ');
    final date = shortDate(l10n, lastModified(t));
    final metaStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white60,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() {
        _hovered = true;
        _phase += 1;
      }),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.025 : 1,
          duration: Motion.medium,
          curve: Motion.curve,
          child: AnimatedContainer(
            duration: Motion.medium,
            curve: Motion.curve,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.selected
                    ? context.colors.accent
                    : Colors.transparent,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.lights.first.withValues(
                    alpha: _hovered ? 0.30 : 0.0,
                  ),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.35 : 0.18),
                  blurRadius: _hovered ? 18 : 8,
                  offset: Offset(0, _hovered ? 8 : 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
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
                    padding: const EdgeInsets.all(Space.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: TitleActions(
                            t,
                            visible: _hovered || widget.selected,
                            onDark: true,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white, height: 1.2),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                        const SizedBox(height: Space.s),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                            const SizedBox(width: Space.s),
                            Text(date, style: metaStyle),
                          ],
                        ),
                        const SizedBox(height: Space.s),
                        StatusTrail(t.status, onDark: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
