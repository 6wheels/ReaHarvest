import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/tasks.dart';
import '../../state/providers.dart';
import '../../state/reaper.dart';
import '../../state/report_paths.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../labels.dart';
import '../versions/edit_version_dialog.dart';
import '../versions/version_ui_actions.dart';
import '../widgets.dart';
import 'adopt_form.dart';
import 'history_view.dart';
import 'version_detail_view.dart';

/// Selected version: details, actions, missing plugins, duplicates and
/// history.
class VersionPane extends ConsumerWidget {
  const VersionPane(
    this.title,
    this.version, {
    super.key,
    required this.onSelect,
    required this.onDuplicate,
  });

  final Title title;
  final Version version;

  /// Selects the version of this file name (after a rename).
  final ValueChanged<String> onSelect;

  /// Opens the new version dialog, a copy of this version chosen.
  final VoidCallback onDuplicate;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final name = await showEditVersionDialog(context, ref, title, version);
    if (name != null) onSelect(name);
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.read(tasksProvider.notifier);
    try {
      await ref.read(versionActionsProvider).backup(title, version);
      tasks.notify(l10n.backupCreated);
    } on Object catch (e) {
      fail(tasks, l10n, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final alerts = versionAlerts(ref, title, version);
    final status = title.statusOf(version);
    final m = version.metadata;
    final freeTree =
        ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ??
        true;
    final hasHistory = !freeTree && m != null;
    final entry = ref
        .watch(settingsProvider.select((s) => s.libraries))
        .where((l) => l.id == title.libraryId)
        .firstOrNull;
    final reveal = ref.watch(fileRevealerProvider);
    return ListView(
      padding: const EdgeInsets.all(Space.xl),
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                alerts.notAdopted
                    ? version.fileName
                    : m == null
                    ? versionName(version)
                    : m.label,
                style: text.titleLarge?.copyWith(
                  fontStyle: alerts.notAdopted ? FontStyle.italic : null,
                ),
              ),
            ),
            if (alerts.notAdopted) ...[
              const SizedBox(width: Space.m),
              Pill(l10n.notAdopted, color: c.muted),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          versionDetails(
            ref,
            l10n,
            version,
            withLabel: false,
            withSize: version.folder != null,
          ),
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
        if (version.folder != null && version.sizes.isNotEmpty)
          Text(
            sizeBreakdown(l10n, version),
            style: text.bodySmall?.copyWith(color: c.muted),
          ),
        if (entry != null)
          Row(
            children: [
              Flexible(
                child: SelectableText(
                  versionPath(entry, title, version),
                  style: text.bodySmall?.copyWith(color: c.muted),
                ),
              ),
              if (reveal != null) ...[
                const SizedBox(width: Space.xs),
                IconButton(
                  tooltip: l10n.showInExplorer,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(Space.xs),
                  color: c.muted,
                  onPressed: () => reveal(versionPath(entry, title, version)),
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ],
            ],
          ),
        if (status != null || alerts.missing.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              if (status != null)
                Pill(statusLabel(l10n, status), color: c.accent),
              if (alerts.missing.isNotEmpty)
                Pill(
                  l10n.missingPluginCount(alerts.missing.length),
                  color: warningColor,
                ),
            ],
          ),
        ],
        if (alerts.notAdopted) ...[
          const SizedBox(height: Space.l),
          Adopt(title, version),
        ],
        const SizedBox(height: Space.m),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              icon: const ReaperIcon(),
              onPressed: () =>
                  openVersionInReaper(context, ref, title, version),
              label: Text(l10n.openInReaper),
            ),
            // Not wired yet: renders are played from phase 3 (SPEC §5).
            OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              onPressed: null,
              label: Text(l10n.playRender),
            ),
            if (hasHistory)
              OutlinedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                onPressed: () => _backup(context, ref),
                label: Text(l10n.createBackup),
              ),
            MenuAnchor(
              menuChildren: [
                if (!freeTree) ...[
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.copy_rounded),
                    onPressed: onDuplicate,
                    child: Text(l10n.duplicateVersion),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, ref),
                    child: Text(l10n.editVersion),
                  ),
                ],
                SubmenuButton(
                  leadingIcon: const Icon(Icons.flag_outlined),
                  menuChildren: [
                    for (final s in {...Title.defaultStatuses, ?status})
                      MenuItemButton(
                        trailingIcon: s == status
                            ? const Icon(Icons.check_rounded, size: 18)
                            : null,
                        onPressed: () => setVersionStatusFromUi(
                          context,
                          ref,
                          title,
                          version,
                          s,
                        ),
                        child: Text(statusLabel(l10n, s)),
                      ),
                    MenuItemButton(
                      onPressed: status == null
                          ? null
                          : () => setVersionStatusFromUi(
                              context,
                              ref,
                              title,
                              version,
                              null,
                            ),
                      child: Text(l10n.noStatus),
                    ),
                  ],
                  child: Text(l10n.changeStatus),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () =>
                      deleteVersionFromUi(context, ref, title, version),
                  child: Text(l10n.deleteVersion),
                ),
                if (!freeTree && versionFolderCount(title) > 1)
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.filter_1_rounded),
                    onPressed: () =>
                        keepOnlyVersionFromUi(context, ref, title, version),
                    child: Text(l10n.keepOnlyVersion),
                  ),
              ],
              builder: (context, controller, _) => IconButton(
                tooltip: l10n.moreActions,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ),
          ],
        ),
        if (alerts.missing.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel(l10n.filterMissingPlugins),
          const SizedBox(height: Space.xs),
          for (final plugin in alerts.missing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.extension_off_outlined,
                    size: 16,
                    color: warningColor,
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(plugin.name, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
        if (alerts.duplicates.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          Text(
            l10n.duplicateOf(
              [
                for (final (t, v) in alerts.duplicates)
                  t.id == title.id
                      ? v.fileName
                      : '${titleName(t)}/${v.fileName}',
              ].join(', '),
            ),
            style: text.bodyMedium?.copyWith(color: warningColor),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.call_split_rounded, size: 18),
              onPressed: () => runProjectChange(
                context,
                ref,
                () => ref
                    .read(versionActionsProvider)
                    .separateDuplicate(title, version),
              ),
              label: Text(l10n.separateDuplicate),
            ),
          ),
        ],
        if (entry != null) ...[
          const SizedBox(height: Space.l),
          VersionDetailView(versionPath(entry, title, version)),
        ],
        if (hasHistory) ...[
          const SizedBox(height: Space.l),
          SectionLabel(l10n.history),
          const SizedBox(height: Space.xs),
          History(title, version),
        ],
      ],
    );
  }
}
