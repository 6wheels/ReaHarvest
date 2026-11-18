import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
