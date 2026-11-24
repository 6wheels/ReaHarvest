import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../widgets.dart';

/// Side of the color square of a figure, height of the bar of the shares.
const _swatch = 12.0;
const _barHeight = 14.0;

/// Figures of a title (SPEC §5.2): size on disk, total and per part, as a
/// stacked bar with its legend, then the versions, the trash and the
/// assets. Taken from the index, never from the files.
class FiguresView extends ConsumerWidget {
  const FiguresView(this.title, {super.key});

  final Title title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final figures = ref.watch(titleFiguresProvider(title));
    final total = figures.total;
    final colors = {
      FigurePart.projects: c.accent,
      FigurePart.media: c.ledGreen,
      FigurePart.renders: c.ledAmber,
      FigurePart.assets: c.ledRed,
      FigurePart.history: c.text,
      FigurePart.trash: c.muted,
      FigurePart.other: c.border,
    };
    final parts = [
      for (final part in FigurePart.values)
        if (figures.sizes[part]! > 0) part,
    ];
    String legendText(FigurePart part) {
      final size = figures.sizes[part]!;
      final percent = total == 0 ? '' : ' · ${(100 * size / total).round()} %';
      return '${_label(l10n, part)} · ${formatSize(size)}$percent';
    }

    return ListView(
      padding: const EdgeInsets.all(Space.xl),
      children: [
        SectionLabel(l10n.figures),
        const SizedBox(height: Space.s),
        Text(
          '${l10n.figuresTotal} · ${formatSize(total)}',
          style: text.titleMedium,
        ),
        const SizedBox(height: Space.s),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.xs),
          child: SizedBox(
            height: _barHeight,
            child: Row(
              children: [
                if (parts.isEmpty) Expanded(child: ColoredBox(color: c.border)),
                for (final part in parts)
                  Expanded(
                    flex: figures.sizes[part]!,
                    child: ColoredBox(color: colors[part]!),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        Wrap(
          spacing: Space.l,
          runSpacing: Space.s,
          children: [
            for (final part in FigurePart.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: _swatch,
                    height: _swatch,
                    color: colors[part],
                  ),
                  const SizedBox(width: Space.s),
                  Text(legendText(part), style: text.bodySmall),
                ],
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        for (final line in [
          '${l10n.figuresVersions(figures.versions)} · '
              '${l10n.figuresAdopted(figures.adopted)} · '
              '${l10n.figuresNotAdopted(figures.notAdopted)}',
          l10n.figuresBackups(figures.backups),
          l10n.figuresTrashedVersions(figures.trashedVersions),
          l10n.figuresAssetFiles(figures.assets),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(line, style: text.bodyMedium),
          ),
      ],
    );
  }

  static String _label(AppLocalizations l10n, FigurePart part) =>
      switch (part) {
        FigurePart.projects => l10n.sizeProject,
        FigurePart.media => l10n.sizeMedia,
        FigurePart.renders => l10n.sizeRenders,
        FigurePart.assets => l10n.figuresAssets,
        FigurePart.history => l10n.sizeHistory,
        FigurePart.trash => l10n.figuresTrash,
        FigurePart.other => l10n.sizeOther,
      };
}
