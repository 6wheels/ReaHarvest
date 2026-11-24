import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../kit/kit.dart';
import '../labels.dart';
import '../over_library.dart';
import '../studio_title_bar.dart';
import '../versions/new_version_dialog.dart';
import '../versions/trash_view.dart';
import 'figures_view.dart';
import 'title_header.dart';
import 'version_list_item.dart';
import 'version_pane.dart';

/// Width of the column of the versions.
const _paneWidth = 300.0;

/// Opens the detail page of title [id] over the library.
Future<void> openTitleDetail(BuildContext context, NodeId id) =>
    Navigator.of(context).push(overLibraryRoute((_) => TitleDetailPage(id)));

/// Full detail of a title, over the library (SPEC §5.2): its versions on
/// the left, the selected version on the right. Back with the back
/// button, Escape or the mouse back button.
class TitleDetailPage extends ConsumerStatefulWidget {
  const TitleDetailPage(this.id, {super.key});

  final NodeId id;

  @override
  ConsumerState<TitleDetailPage> createState() => _TitleDetailPageState();
}

class _TitleDetailPageState extends ConsumerState<TitleDetailPage> {
  /// File name of the selected version; the latest one when null.
  String? _selected;

  /// Tab shown instead of the versions.
  var _tab = _DetailTab.versions;

  void _select(String fileName) => setState(() => _selected = fileName);

  Future<void> _newVersion(
    Title title,
    Version? selected, {
    bool duplicate = false,
  }) async {
    final name = await showNewVersionDialog(
      context,
      title,
      selected,
      duplicate: duplicate,
    );
    if (name != null) _select(name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = ref
        .watch(titlesProvider)
        .where((t) => t.id == widget.id)
        .firstOrNull;
    final versions = title == null ? const <Version>[] : recentVersions(title);
    final selected =
        versions.where((v) => v.fileName == _selected).firstOrNull ??
        versions.firstOrNull;
    final freeTree =
        title == null ||
        (ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ??
            true);
    final l10n = AppLocalizations.of(context);
    return BackNavigation(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StudioTitleBar(
              location: title == null ? null : titleName(title),
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Header(title, selected),
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                child: Row(
                  children: [
                    for (final (tab, label) in [
                      (_DetailTab.versions, l10n.versions),
                      (_DetailTab.trash, l10n.trash),
                      (_DetailTab.figures, l10n.figures),
                    ])
                      _Tab(
                        label,
                        selected: _tab == tab,
                        onTap: () => setState(() => _tab = tab),
                      ),
                  ],
                ),
              ),
            Divider(height: Sizes.hairline, color: c.border),
            if (title != null && _tab == _DetailTab.trash)
              Expanded(child: TrashView(title)),
            if (title != null && _tab == _DetailTab.figures)
              Expanded(child: FiguresView(title)),
            if (title != null && _tab == _DetailTab.versions)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _paneWidth,
                      child: ListView(
                        padding: const EdgeInsets.all(Space.m),
                        children: [
                          if (!freeTree)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.s),
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.add_rounded,
                                  size: IconSize.l,
                                ),
                                onPressed: () => _newVersion(title, selected),
                                label: Text(l10n.newVersion),
                              ),
                            ),
                          for (final v in versions)
                            VersionItem(
                              title,
                              v,
                              selected: v == selected,
                              onTap: () => _select(v.fileName),
                            ),
                        ],
                      ),
                    ),
                    VerticalDivider(width: Sizes.hairline, color: c.border),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Motion.fast,
                        child: selected == null
                            ? const SizedBox()
                            : VersionPane(
                                title,
                                selected,
                                onSelect: _select,
                                onDuplicate: () => _newVersion(
                                  title,
                                  selected,
                                  duplicate: true,
                                ),
                                key: ValueKey(selected.fileName),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _DetailTab { versions, trash, figures }

/// Tab of the title detail (versions, trash, figures).
class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableSurface(
      radius: 0,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.m,
          vertical: Space.s,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: Sizes.bar,
              color: selected ? c.accent : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: context.legend.copyWith(color: selected ? c.text : c.muted),
        ),
      ),
    );
  }
}
