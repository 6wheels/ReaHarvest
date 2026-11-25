import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import '../path_row.dart';
import 'settings_section.dart';

/// Size of the licenses page.
const _width = 700.0;
const _height = 460.0;

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
        Padding(
          padding: const EdgeInsets.only(bottom: Space.l),
          child: Text(
            'ReaHarvest',
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontWeight: Weights.bold),
          ),
        ),
        FormRow(label: l10n.applicationVersion, child: const Text(appVersion)),
        FormRow(
          label: l10n.licenses,
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => _showLicenses(context),
              child: Text(l10n.showLicenses),
            ),
          ),
        ),
      ],
    );
  }
}

/// Licenses in a popup smaller than the settings one; Escape closes it. The
/// package pages stay inside it (own navigator).
Future<void> _showLicenses(BuildContext context) => showGlassDialog<void>(
  context,
  (context) => Dialog(
    clipBehavior: Clip.antiAlias,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: SizedBox(
          width: _width,
          height: _height,
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const LicensePage(
                applicationName: 'ReaHarvest',
                applicationVersion: appVersion,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
