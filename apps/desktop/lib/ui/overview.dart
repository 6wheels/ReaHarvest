import 'dart:math' show min;
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
import 'formats.dart';
import 'title_detail/title_detail_page.dart';
import 'widgets.dart';

/// Height of the overview dock.
const overviewHeight = 196.0;

/// Margin between the overview and the bottom of the library.
const overviewBottom = Space.l;

/// Bottom padding of a library view (cards, list, tree): while the
/// overview is open, the last titles can scroll above it.
double libraryBottomPadding({required bool overviewOpen}) =>
    overviewOpen ? overviewHeight + overviewBottom + Space.m : Space.xl;

/// Scrolls the title of [context], just selected, into view: above the
/// overview when the overview hides its bottom, down when its top is
/// scrolled out. Its scroll view must reach the bottom of the library.
void revealSelectedTitle(BuildContext context) {
  final item = context.findRenderObject();
  final scrollable = Scrollable.maybeOf(context);
  final viewport = scrollable?.context.findRenderObject();
  if (item is! RenderBox || !item.attached || viewport is! RenderBox) return;
  final top = item.localToGlobal(Offset.zero, ancestor: viewport).dy;
  final bottom = top + item.size.height;
  final visible =
      viewport.size.height - overviewHeight - overviewBottom - Space.m;
  final position = scrollable!.position;
  final double delta;
  if (top < Space.m) {
    delta = top - Space.m;
  } else if (bottom > visible) {
    // The top stays visible when the title is taller than the room left.
    delta = min(bottom - visible, top - Space.m);
  } else {
    return;
  }
  position.animateTo(
    (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ),
    duration: Motion.medium,
    curve: Motion.curve,
  );
}

/// Number of versions listed in the overview.
const _recentCount = 4;

/// Width of the recent versions.
const _recentWidth = 460.0;

/// Overview of a title, docked at the bottom of the library (SPEC §5.2):
/// crucial data only, the rest being in the title detail. It floats over
/// the titles with a blurred, translucent (acrylic) background.
class Overview extends ConsumerWidget {
  const Overview(this.id, {super.key});

  final NodeId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final title = ref
        .watch(titlesProvider)
        .where((t) => t.id == id)
        .firstOrNull;
    final radius = BorderRadius.circular(Radii.m);

    // Same margin around the content, a little more on the left; the
    // actions sit in the corner, with a small margin.
    const margin = Space.s + Space.xs;
    final Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, margin, 0, margin),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) ...[
                  Expanded(child: _Identity(title)),
                  const SizedBox(width: Space.l),
                  SizedBox(width: _recentWidth, child: _Recent(title)),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ),
        // Close about level with the heading of the versions, detail with
        // their first line.
        Padding(
          padding: const EdgeInsets.all(Space.xs),
          child: Column(
            spacing: Space.xs + 1,
            children: [
              IconAction(
                icon: const Icon(Icons.close_rounded),
                tooltip: l10n.close,
                onPressed: ref.read(overviewProvider.notifier).close,
              ),
              OpenDetailAction(
                tooltip: l10n.openDetail,
                onPressed: () => openTitleDetail(context, id),
              ),
            ],
          ),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // A single blur, clipped to the panel.
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.6),
              borderRadius: radius,
              border: Border.all(color: c.border),
            ),
            child: Material(type: MaterialType.transparency, child: body),
          ),
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
    // Artist and album as on the cards.
    final tags = [
      for (final v in parentTags(title)) tagValueLabel(l10n, v).toUpperCase(),
    ].join(labelSeparator);
    final library = libraryName(ref, title);
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  titleName(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge,
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(width: Space.s),
                Flexible(
                  child: Text(
                    tags,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.legend.copyWith(fontSize: 9.5),
                  ),
                ),
              ],
            ],
          ),
          if (library != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SectionLabel(library),
            ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Flexible(
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.readout,
                ),
              ),
              if (leadStatus(title) case final status?) ...[
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
    borderRadius: BorderRadius.circular(Radii.xs),
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
          Disclosure(Disclosure.right, size: 20, color: color),
        ],
      ),
    ),
  );
}

/// Most recent versions, one line each, the latest on top.
class _Recent extends StatelessWidget {
  const _Recent(this.title);

  final Title title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final versions = recentVersions(title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: IconAction.size,
          child: Row(
            children: [
              Expanded(child: SectionLabel(l10n.recentVersions)),
              if (versions.length > _recentCount)
                TextButton(
                  // Small, to fit the heading.
                  style: glowButtonStyle(context).merge(
                    TextButton.styleFrom(
                      minimumSize: const Size(0, 22),
                      padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    ),
                  ),
                  onPressed: () => openTitleDetail(context, title.id),
                  child: Text(l10n.allVersions(versions.length)),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.xs),
        for (final (i, v) in versions.take(_recentCount).indexed) ...[
          if (i > 0) const SizedBox(height: 3),
          _RecentVersion(title, v),
        ],
      ],
    );
  }
}

/// Most advanced status of the versions of [t] along the trail, else a
/// custom one, else the status of the title itself.
String? leadStatus(Title t) {
  const steps = Title.defaultStatuses;
  final statuses = [for (final v in t.versions) ?t.statusOf(v)];
  final known = statuses.where(steps.contains);
  if (known.isEmpty) return statuses.firstOrNull ?? t.status;
  return known.reduce((a, b) => steps.indexOf(a) >= steps.indexOf(b) ? a : b);
}

/// Line of a recent version: its label and owner, date and tempo, icons
/// of what needs attention, its status and its actions.
class _RecentVersion extends ConsumerWidget {
  const _RecentVersion(this.title, this.version);

  final Title title;
  final Version version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final m = version.metadata;
    final label = m?.label ?? '';
    final owner = switch (m?.owner) {
      final id? => ref.watch(ownerNamesProvider)[id] ?? l10n.unknownOwner,
      null => null,
    };
    final status = title.statusOf(version);
    final alerts = versionAlerts(ref, title, version);
    final readout = [
      shortDate(l10n, version.modified),
      if (version.tempo case final bpm?) l10n.bpm(bpm.round()),
    ].join(' · ');
    Widget alert(IconData icon, String tooltip, Color color) => Padding(
      padding: const EdgeInsets.only(left: Space.xs),
      child: Tooltip(
        message: tooltip,
        child: Icon(icon, size: 14, color: color),
      ),
    );
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: Space.s + 2, right: 1),
      decoration: BoxDecoration(
        color: c.raised.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  // The file name stands for a version without label.
                  label.isEmpty
                      ? TextSpan(
                          text: p.posix.withoutExtension(version.fileName),
                          style: TextStyle(color: c.muted),
                        )
                      : TextSpan(
                          text: label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                  if (owner != null)
                    TextSpan(
                      text: '  $owner',
                      style: TextStyle(color: c.muted),
                    ),
                  TextSpan(text: '   $readout', style: context.readout),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontSize: 12.5),
            ),
          ),
          if (alerts.missing.isNotEmpty)
            alert(
              Icons.extension_off_outlined,
              l10n.missingPluginCount(alerts.missing.length),
              warningColor,
            ),
          if (alerts.duplicates.isNotEmpty)
            alert(
              Icons.content_copy_rounded,
              l10n.duplicateCount(1),
              warningColor,
            ),
          if (alerts.notAdopted)
            alert(Icons.help_outline_rounded, l10n.notAdopted, c.muted),
          if (status != null) ...[
            const SizedBox(width: Space.s),
            Pill(statusLabel(l10n, status), color: c.accent),
          ],
          const SizedBox(width: Space.xs),
          IconAction(
            icon: const ReaperIcon(),
            tooltip: l10n.openInReaper,
            onPressed: () => openVersionInReaper(context, ref, title, version),
          ),
          // Not wired yet: renders are played from phase 3 (SPEC §5).
          IconAction(
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: l10n.playRender,
            onPressed: null,
          ),
        ],
      ),
    );
  }
}
