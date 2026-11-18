import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../path_row.dart';
import 'settings_section.dart';

/// Application version, kept in step with `pubspec.yaml`.
const appVersion = '0.1.0';

/// About page: version and licenses.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(l10n.about, first: true),
        FormRow(label: l10n.applicationVersion, child: const Text(appVersion)),
        FormRow(
          label: l10n.licenses,
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'ReaHarvest',
                applicationVersion: appVersion,
              ),
              child: Text(l10n.showLicenses),
            ),
          ),
        ),
      ],
    );
  }
}
