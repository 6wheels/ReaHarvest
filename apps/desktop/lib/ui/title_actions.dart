import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'formats.dart';
import 'title_detail/title_detail_page.dart';
import 'widgets.dart';

/// Version opened by the quick "Open in REAPER" button: the latest one of
/// member [me], else the latest one; null without versions.
Version? quickVersion(Title title, MemberId me) {
  final versions = recentVersions(title);
  return versions.where((v) => v.metadata?.owner == me).firstOrNull ??
      versions.firstOrNull;
}

/// Opens the [quickVersion] of [title] in REAPER. In `collab` mode, a
/// version of another member is opened after a confirmation; a version
/// without owner is not.
Future<void> openLatestInReaper(
  BuildContext context,
  WidgetRef ref,
  Title title,
) async {
  final l10n = AppLocalizations.of(context);
  final identity = ref.read(settingsProvider).identity;
  final version = quickVersion(title, identity.memberId);
  if (version == null) return;
  final mode = ref.read(indexedLibrariesProvider)[title.libraryId]?.mode;
  final owner = version.metadata?.owner;
  if (mode == LibraryMode.collab &&
      owner != null &&
      owner != identity.memberId) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.notYourVersionTitle),
        content: Text(
          l10n.notYourVersionHint(
            versionName(version),
            ref.read(ownerNamesProvider)[owner] ?? l10n.unknownOwner,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.openAnyway),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }
  if (!context.mounted) return;
  await openVersionInReaper(context, ref, title, version);
}

/// Width taken by [TitleActions].
const titleActionsWidth = 4 * (IconAction.size + 4);

/// Quick actions of a title, on its card or row: open its latest version
/// in REAPER, open its detail, and a menu of other actions. Shown on hover
/// or selection, and while the menu is open.
class TitleActions extends ConsumerStatefulWidget {
  const TitleActions(
    this.title, {
    super.key,
    required this.visible,
    this.onAurora = false,
  });

  final Title title;
  final bool visible;

  /// Drawn over the aurora of a card.
  final bool onAurora;

  @override
  ConsumerState<TitleActions> createState() => _TitleActionsState();
}

class _TitleActionsState extends ConsumerState<TitleActions> {
  var _menuOpen = false;

  /// First enabled entry of the menu, focused on opening so that Escape
  /// closes it.
  final _first = FocusNode();

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = widget.visible || _menuOpen;
    final t = widget.title;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.fast,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.versions.isNotEmpty) ...[
              _gap,
              IconAction(
                icon: const ReaperIcon(),
                tooltip: l10n.openInReaper,
                onAurora: widget.onAurora,
                onPressed: () => openLatestInReaper(context, ref, t),
              ),
              _gap,
              // Not wired yet: renders are played from phase 3 (SPEC §5).
              IconAction(
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: l10n.playRender,
                onAurora: widget.onAurora,
                onPressed: null,
              ),
            ],
            _gap,
            OpenDetailAction(
              tooltip: l10n.openDetail,
              onAurora: widget.onAurora,
              onPressed: () => openTitleDetail(context, t.id),
            ),
            _gap,
            MenuAnchor(
              onOpen: () {
                setState(() => _menuOpen = true);
                focusMenuEntry(_first);
              },
              onClose: () => setState(() => _menuOpen = false),
              // Not wired yet (#51 and following).
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.add_rounded),
                  child: Text(l10n.newVersion),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.bookmark_add_outlined),
                  child: Text(l10n.createBackup),
                ),
                SubmenuButton(
                  focusNode: _first,
                  leadingIcon: const Icon(Icons.flag_outlined),
                  menuChildren: [
                    for (final s in Title.defaultStatuses)
                      MenuItemButton(child: Text(statusLabel(l10n, s))),
                  ],
                  child: Text(l10n.changeStatus),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.folder_open_outlined),
                  child: Text(l10n.showInExplorer),
                ),
              ],
              builder: (context, controller, _) => IconAction(
                icon: const Icon(Icons.more_horiz_rounded),
                tooltip: l10n.moreActions,
                onAurora: widget.onAurora,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Space between two actions.
const _gap = SizedBox(width: 4);
