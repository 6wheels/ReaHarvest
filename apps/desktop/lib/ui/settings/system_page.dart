import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
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
        // Full-width rows: these labels are too long for the label column.
        CheckRow(
          value: settings.showInTray,
          label: l10n.showInTray,
          onChanged: (v) => notifier.change((s) => s.copyWith(showInTray: v)),
        ),
        const SizedBox(height: Space.m),
        SectionLabel(l10n.onProjectOpen),
        const SizedBox(height: Space.s),
        Column(
          spacing: Space.xs,
          children: [
            for (final (action, label) in [
              (ProjectOpenAction.nothing, l10n.onOpenNothing),
              (ProjectOpenAction.minimize, l10n.onOpenMinimize),
              (
                ProjectOpenAction.close,
                settings.showInTray ? l10n.onOpenToTray : l10n.onOpenClose,
              ),
            ])
              ChoiceRow(
                selected: settings.onProjectOpen == action,
                label: label,
                onTap: () =>
                    notifier.change((a) => a.copyWith(onProjectOpen: action)),
              ),
          ],
        ),
        const SizedBox(height: Space.m),
      ],
    );
  }
}
