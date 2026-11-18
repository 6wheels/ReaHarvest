import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../path_row.dart';
import '../reaper_settings.dart';
import 'settings_section.dart';

/// System page: REAPER and logs.
class SystemPage extends ConsumerWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSection('REAPER', first: true),
        const ReaperSettings(),
        SettingsSection(l10n.windowAndTray),
        const _WindowSettings(),
        SettingsSection(l10n.logs),
        FormRow(
          label: l10n.logFolder,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ref.watch(logFolderProvider),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: c.muted),
                ),
              ),
              const SizedBox(width: Space.s),
              OutlinedButton(
                onPressed: () =>
                    ref.read(openFolderProvider)(ref.read(logFolderProvider)),
                child: Text(l10n.openFolder),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// System tray and window behavior when a project opens (SPEC §5.1).
class _WindowSettings extends ConsumerWidget {
  const _WindowSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormRow(
          label: l10n.showInTray,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Switch(
              value: settings.showInTray,
              onChanged: (v) =>
                  notifier.change((s) => s.copyWith(showInTray: v)),
            ),
          ),
        ),
        FormRow(
          label: l10n.onProjectOpen,
          child: SegmentedButton<ProjectOpenAction>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ProjectOpenAction.nothing,
                label: Text(l10n.onOpenNothing),
              ),
              ButtonSegment(
                value: ProjectOpenAction.minimize,
                label: Text(l10n.onOpenMinimize),
              ),
              ButtonSegment(
                value: ProjectOpenAction.close,
                label: Text(
                  settings.showInTray ? l10n.onOpenToTray : l10n.onOpenClose,
                ),
              ),
            ],
            selected: {settings.onProjectOpen},
            onSelectionChanged: (s) =>
                notifier.change((a) => a.copyWith(onProjectOpen: s.first)),
          ),
        ),
      ],
    );
  }
}
