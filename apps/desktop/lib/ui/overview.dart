import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'title_detail.dart';
import 'widgets.dart';

/// Height of the overview dock.
const overviewHeight = 196.0;

/// Number of versions listed in the overview.
const _recentCount = 3;

/// Overview of a title, docked at the bottom of the library (SPEC §5.2):
/// crucial data only, the rest being in the title detail. Unpinned, it
/// floats over the titles with a blurred, translucent (acrylic)
/// background; pinned, it is opaque and the titles end above it.
class Overview extends ConsumerWidget {
  const Overview(this.id, {super.key});

  final NodeId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final pinned = ref.watch(
      navigationProvider.select((n) => n.overviewPinned),
    );
    final title = ref
        .watch(titlesProvider)
        .where((t) => t.id == id)
        .firstOrNull;
    final radius = BorderRadius.circular(18);

    final Widget body = Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Expanded(flex: 2, child: _Identity(title)),
            const SizedBox(width: Space.l),
            Expanded(flex: 3, child: _Recent(title)),
          ] else
            const Spacer(),
          Column(
            children: [
              IconButton(
                tooltip: l10n.close,
                onPressed: ref.read(overviewProvider.notifier).close,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
              IconButton(
                tooltip: pinned ? l10n.unpin : l10n.pin,
                isSelected: pinned,
                onPressed: () => ref
                    .read(navigationProvider.notifier)
                    .setOverviewPinned(!pinned),
                icon: const Icon(Icons.push_pin_outlined, size: 20),
                selectedIcon: Icon(
                  Icons.push_pin_rounded,
                  size: 20,
                  color: c.accent,
                ),
              ),
              IconButton(
                tooltip: l10n.openDetail,
                onPressed: () => openTitleDetail(context, id),
                icon: const Icon(Icons.open_in_full_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: pinned ? 1 : 0.72),
        borderRadius: radius,
        border: Border.all(color: c.border),
      ),
      child: Material(type: MaterialType.transparency, child: body),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: pinned ? 0.10 : 0.25),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // A single blur, clipped to the panel; none when pinned since
      // nothing is behind it.
      child: ClipRRect(
        borderRadius: radius,
        child: pinned
            ? panel
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: panel,
              ),
      ),
    );
  }
}

/// Name, tags, figures, status and alerts.
class _Identity extends ConsumerWidget {
  const _Identity(this.title);

  final Title title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final subtitle = titleSubtitle(ref, l10n, title);
    final meta = [
      l10n.versionCount(title.versions.length),
      if (tempoOf(title) case final bpm?) l10n.bpm(bpm),
      shortDate(l10n, lastModified(title)),
    ].where((s) => s.isNotEmpty).join(' · ');
    final alerts = [
      for (final v in title.versions) versionAlerts(ref, title, v),
    ];
    final missing = {
      for (final a in alerts)
        for (final plugin in a.missing) plugin.name,
    }.length;
    final duplicated = alerts.where((a) => a.duplicates.isNotEmpty).length;
    final notAdopted = alerts.where((a) => a.notAdopted).length;
    void open() => openTitleDetail(context, title.id);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleName(title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge,
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: c.muted),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: c.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (title.status case final status?) ...[
                const SizedBox(width: Space.s),
                Pill(statusLabel(l10n, status), color: c.accent),
              ],
            ],
          ),
          if (missing > 0 || duplicated > 0 || notAdopted > 0)
            const SizedBox(height: Space.s),
          if (missing > 0)
            _Alert(
              Icons.extension_off_outlined,
              l10n.missingPluginCount(missing),
              color: warningColor,
              onTap: open,
            ),
          if (duplicated > 0)
            _Alert(
              Icons.content_copy_rounded,
              l10n.duplicateCount(duplicated),
              color: warningColor,
              onTap: open,
            ),
          if (notAdopted > 0)
            _Alert(
              Icons.help_outline_rounded,
              l10n.notAdoptedCount(notAdopted),
              color: c.muted,
              onTap: open,
            ),
        ],
      ),
    );
  }
}

/// Alert line of the overview, leading to the title detail.
class _Alert extends StatelessWidget {
  const _Alert(this.icon, this.label, {required this.color, this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Space.s),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 16, color: color),
        ],
      ),
    ),
  );
}

/// Most recent versions, side by side.
class _Recent extends StatelessWidget {
  const _Recent(this.title);

  final Title title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final versions = recentVersions(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel(l10n.recentVersions)),
            if (versions.length > _recentCount)
              TextButton(
                onPressed: () => openTitleDetail(context, title.id),
                child: Text(l10n.allVersions(versions.length)),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, v) in versions.take(_recentCount).indexed) ...[
                if (i > 0) const SizedBox(width: Space.s),
                Expanded(child: _RecentVersion(title, v)),
              ],
              // Keeps the tiles at the same width with fewer versions.
              for (var i = versions.length; i < _recentCount; i++) ...[
                const SizedBox(width: Space.s),
                const Spacer(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentVersion extends ConsumerWidget {
  const _RecentVersion(this.title, this.version);

  final Title title;
  final Version version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.xs),
      decoration: BoxDecoration(
        color: c.raised.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.posix.withoutExtension(version.fileName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Flexible(
                    child: Text(
                      versionDetails(ref, l10n, version),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.openInReaper,
            onPressed: () => openVersionInReaper(context, ref, title, version),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
