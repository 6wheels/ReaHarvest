import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' as domain show Title;

import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'aurora.dart';

/// Square title card, like a record sleeve (SPEC §5.2).
class TitleCard extends StatefulWidget {
  const TitleCard(this.view, {super.key});

  final TitleView view;

  @override
  State<TitleCard> createState() => _TitleCardState();
}

class _TitleCardState extends State<TitleCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.view.title;
    final l10n = AppLocalizations.of(context);
    final palette = AuroraPalette.of(t.id);
    final name = t.tags['title'] ?? t.path.split('/').last;
    final subtitle = [
      for (final e in t.tags.entries)
        if (e.key != 'title' && e.value.isNotEmpty) e.value,
    ].join(' · ');
    final meta = [
      l10n.versionCount(t.versions.length),
      if (widget.view.bpm case final bpm?) l10n.bpm(bpm),
    ].join(' · ');
    final date = switch (_lastModified(t)) {
      // Short date: "Oct 28" this year, "Oct 2025" before.
      final d? when d.year == DateTime.now().year => DateFormat.MMMd(
        l10n.localeName,
      ).format(d),
      final d? => DateFormat.yMMM(l10n.localeName).format(d),
      null => '',
    };
    final metaStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white60,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.025 : 1,
        duration: Motion.medium,
        curve: Motion.curve,
        child: AnimatedContainer(
          duration: Motion.medium,
          curve: Motion.curve,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
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
                    tween: Tween(end: _hovered ? 1 : 0),
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
                      if (widget.view.status case final status?)
                        _StatusBadge(_statusLabel(l10n, status)),
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static DateTime? _lastModified(domain.Title t) => t.versions.isEmpty
      ? null
      : t.versions.map((v) => v.modified).reduce((a, b) => a.isAfter(b) ? a : b);

  static String _statusLabel(AppLocalizations l10n, String status) =>
      switch (status) {
        'idea' => l10n.statusIdea,
        'writing' => l10n.statusWriting,
        'recording' => l10n.statusRecording,
        'mixing' => l10n.statusMixing,
        'done' => l10n.statusDone,
        _ => status,
      };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
    ),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    ),
  );
}
