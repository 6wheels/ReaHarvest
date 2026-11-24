import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/navigation.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../labels.dart';
import '../widgets.dart';

/// Version of the title detail list, like a rack strip: a light lit when
/// the version is adopted (off when not), its label and readouts, its
/// status and alert. The selected strip has a lit edge.
class VersionItem extends ConsumerStatefulWidget {
  const VersionItem(
    this.title,
    this.version, {
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Title title;
  final Version version;
  final bool selected;
  final VoidCallback onTap;

  @override
  ConsumerState<VersionItem> createState() => _VersionItemState();
}

class _VersionItemState extends ConsumerState<VersionItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final VersionItem(:title, :version, :selected) = widget;
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final alerts = versionAlerts(ref, title, version);
    final owners = ref.watch(ownerNamesProvider);
    final m = version.metadata;
    final status = title.statusOf(version);
    // Free tree versions have no metadata: their file name is their label.
    // Adopted versions always have one (file name fallback, SPEC §4.2).
    final label = m == null
        ? alerts.notAdopted
              ? l10n.notAdopted
              : versionName(version)
        : m.label;
    // Generic labels: muted, the file name tells the versions apart.
    final generic = alerts.notAdopted;
    final details = [
      shortDate(l10n, version.modified),
      if (m?.owner case final owner?) owners[owner] ?? l10n.unknownOwner,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          decoration: BoxDecoration(
            color: selected
                ? c.accent.withValues(alpha: Alpha.faint)
                : c.surface,
            borderRadius: BorderRadius.circular(Radii.s),
            border: Border.all(
              color: selected
                  ? c.accent.withValues(alpha: Alpha.medium)
                  : _hovered
                  ? c.muted.withValues(alpha: Alpha.strong)
                  : c.border,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.s),
              onTap: widget.onTap,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Lit edge of the selected strip only.
                    AnimatedContainer(
                      duration: Motion.fast,
                      width: Sizes.bar,
                      margin: const EdgeInsets.symmetric(vertical: Space.sm),
                      color: selected ? c.accent : Colors.transparent,
                    ),
                    const SizedBox(width: Space.md),
                    if (m != null || alerts.notAdopted) ...[
                      Center(
                        child: m == null
                            ? Tooltip(
                                message: l10n.notAdopted,
                                child: Led(c.accent, lit: false),
                              )
                            : Led(c.accent),
                      ),
                      const SizedBox(width: Space.md),
                    ],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.type.item.copyWith(
                                color: generic ? c.muted : null,
                              ),
                            ),
                            const SizedBox(height: Space.xxs),
                            Text.rich(
                              TextSpan(
                                text: details,
                                children: [
                                  if (generic)
                                    TextSpan(
                                      text: ' · ${version.fileName}',
                                      style: AppText.italic,
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.type.readoutSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(width: Space.s),
                      Center(
                        child: Pill(statusLabel(l10n, status), color: c.accent),
                      ),
                    ],
                    if (alerts.missing.isNotEmpty ||
                        alerts.duplicates.isNotEmpty) ...[
                      const SizedBox(width: Space.s),
                      Center(
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: IconSize.l,
                          color: context.colors.ledAmber,
                        ),
                      ),
                    ],
                    const SizedBox(width: Space.m),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
