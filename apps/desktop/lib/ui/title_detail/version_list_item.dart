import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/navigation.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../labels.dart';
import '../widgets.dart';

class VersionItem extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final alerts = versionAlerts(ref, title, version);
    final owners = ref.watch(ownerNamesProvider);
    final m = version.metadata;
    final status = title.statusOf(version);
    // Free tree versions have no metadata: their file name is their label.
    // Adopted versions always have one (file name fallback, SPEC §4.2).
    final label = m == null
        ? alerts.notAdopted
              ? l10n.notAdopted
              : p.posix.withoutExtension(version.fileName)
        : m.label;
    // Generic labels: muted, the file name tells the versions apart.
    final generic = alerts.notAdopted;
    final details = [
      shortDate(l10n, version.modified),
      if (m?.owner case final owner?) owners[owner] ?? l10n.unknownOwner,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.m,
              vertical: Space.s,
            ),
            child: Row(
              children: [
                if (m != null || alerts.notAdopted) ...[
                  Icon(
                    m == null
                        ? Icons.help_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 18,
                    color: m == null ? c.muted : c.accent,
                  ),
                  const SizedBox(width: Space.s),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: generic ? c.muted : null,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          text: details,
                          children: [
                            if (generic)
                              TextSpan(
                                text: ' · ${version.fileName}',
                                style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: Space.s),
                  Pill(statusLabel(l10n, status), color: c.accent),
                ],
                if (alerts.missing.isNotEmpty ||
                    alerts.duplicates.isNotEmpty) ...[
                  const SizedBox(width: Space.s),
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: warningColor,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
