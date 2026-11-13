import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/navigation.dart';
import '../../theme/app_theme.dart';
import '../aurora.dart';
import '../formats.dart';
import '../labels.dart';
import '../status_trail.dart';

/// Title name with its first parent tag (e.g. the artist) on the same
/// line, the other tags (e.g. the album) and the library below; stats of
/// the selected [version] on the right; status trail across the width.
class Header extends ConsumerWidget {
  const Header(this.title, this.version, {super.key});

  final Title? title;
  final Version? version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final t = title;
    final tags = t == null
        ? const <String>[]
        : [for (final v in parentTags(t)) tagValueLabel(l10n, v)];
    final below = t == null
        ? ''
        : [...tags.skip(1), ?libraryName(ref, t)].join(' · ');
    final v = version;
    final toAdopt = t == null ? 0 : ref.watch(toAdoptCountsProvider)[t.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xl, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.back,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              if (t != null) ...[
                const SizedBox(width: Space.s),
                SizedBox.square(
                  dimension: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      painter: AuroraPainter(AuroraPalette.of(t.id), phase: 0),
                    ),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: titleName(t),
                              style: text.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (tags.isNotEmpty)
                              TextSpan(
                                text: '   ${tags.first}',
                                style: text.titleMedium?.copyWith(
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (below.isNotEmpty)
                        Text(
                          below,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: c.muted),
                        ),
                      if (toAdopt > 0)
                        Row(
                          children: [
                            Icon(
                              Icons.help_outline_rounded,
                              size: 16,
                              color: c.muted,
                            ),
                            const SizedBox(width: Space.xs),
                            Text(
                              l10n.notAdoptedCount(toAdopt),
                              style: text.bodySmall?.copyWith(color: c.muted),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (v != null) ...[
                  const SizedBox(width: Space.l),
                  _Stat(
                    l10n.statLength,
                    v.length == null ? null : formatLength(v.length!),
                  ),
                  _Stat('BPM', v.tempo?.round().toString()),
                  _Stat(l10n.statTracks, v.trackCount?.toString()),
                  _Stat(l10n.statItems, v.itemCount?.toString()),
                ],
              ],
            ],
          ),
          if (t != null) ...[
            const SizedBox(height: Space.m),
            Padding(
              padding: const EdgeInsets.only(left: 48 + Space.s),
              child: StatusTrail(t.status, large: true),
            ),
          ],
        ],
      ),
    );
  }
}

/// Figure of the header stats; a dash when unknown.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value ?? '—',
            style: text.titleLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: context.colors.muted,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
