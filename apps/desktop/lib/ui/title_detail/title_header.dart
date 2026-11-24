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
import 'title_tags.dart';

/// Title name with its first parent level (e.g. the artist) on the same
/// line, the other levels (e.g. the album) and the library below; stats of
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
    final levels = t == null
        ? const <String>[]
        : [for (final v in parentLevels(t)) levelValueLabel(l10n, v)];
    final below = t == null
        ? ''
        : [...levels.skip(1), ?libraryName(ref, t)].join(' · ');
    final leaf = levels.isEmpty ? '' : levels.first.toUpperCase();
    final v = version;
    final toAdopt = t == null ? 0 : ref.watch(toAdoptCountsProvider)[t.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.xl, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (t != null) ...[
                Container(
                  width: Sizes.avatar,
                  height: Sizes.avatar,
                  padding: const EdgeInsets.all(Space.xxs),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.s),
                    border: Border.all(color: c.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    child: CustomPaint(
                      painter: AuroraPainter(
                        AuroraPalette.of(
                          t.id,
                          light:
                              Theme.of(context).brightness == Brightness.light,
                        ),
                        phase: 0,
                      ),
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
                                fontWeight: Weights.bold,
                              ),
                            ),
                            if (levels.isNotEmpty)
                              TextSpan(
                                text: '$labelSeparator$leaf',
                                style: context.legend.copyWith(
                                  fontSize: context.type.caption.fontSize,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (below.isNotEmpty)
                        Text(
                          below.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.legend,
                        ),
                      TitleTags(t, key: ValueKey(t.id)),
                      if (toAdopt > 0)
                        Row(
                          children: [
                            Icon(
                              Icons.help_outline_rounded,
                              size: IconSize.m,
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
                  _Stat(l10n.statFx, v.plugins.length.toString()),
                  _Stat(
                    l10n.statMissing,
                    versionAlerts(ref, t, v).missing.length.toString(),
                  ),
                ],
              ],
            ],
          ),
          if (t != null) ...[
            const SizedBox(height: Space.m),
            StatusTrail(t.status, large: true),
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
    return Padding(
      padding: const EdgeInsets.only(left: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value ?? '—',
            style: context.readout.copyWith(
              fontSize: context.type.title.fontSize,
              fontWeight: Weights.medium,
              color: context.colors.text,
            ),
          ),
          Text(label.toUpperCase(), style: context.legend),
        ],
      ),
    );
  }
}
