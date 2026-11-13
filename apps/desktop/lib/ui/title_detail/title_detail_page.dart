import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../over_library.dart';
import '../versions/new_version_dialog.dart';
import '../versions/trash_view.dart';
import 'title_header.dart';
import 'version_list_item.dart';
import 'version_pane.dart';

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

  /// Trash tab shown instead of the versions.
  var _trash = false;

  void _select(String fileName) => setState(() => _selected = fileName);

  Future<void> _newVersion(Title title, Version? selected) async {
    final name = await showNewVersionDialog(context, title, selected);
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
            Header(title, selected),
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                child: Row(
                  children: [
                    _Tab(
                      l10n.versions,
                      selected: !_trash,
                      onTap: () => setState(() => _trash = false),
                    ),
                    _Tab(
                      l10n.trash,
                      selected: _trash,
                      onTap: () => setState(() => _trash = true),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, color: c.border),
            if (title != null && _trash) Expanded(child: TrashView(title)),
            if (title != null && !_trash)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: ListView(
                        padding: const EdgeInsets.all(Space.m),
                        children: [
                          if (!freeTree)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.s),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.add_rounded, size: 18),
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
                    VerticalDivider(width: 1, color: c.border),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Motion.fast,
                        child: selected == null
                            ? const SizedBox()
                            : VersionPane(
                                title,
                                selected,
                                onSelect: _select,
                                onNewVersion: () =>
                                    _newVersion(title, selected),
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

/// Tab of the title detail (versions, trash).
class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
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
              width: 2,
              color: selected ? c.accent : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: selected ? null : c.muted),
        ),
      ),
    );
  }
}
