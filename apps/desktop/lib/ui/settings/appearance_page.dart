import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import '../path_row.dart';
import 'settings_section.dart';

/// Appearance page: theme, accent, text size and language.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(l10n.appearance, first: true),
        FormRow(
          label: l10n.theme,
          child: SegmentedButton<ThemePreference>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ThemePreference.system,
                label: Text(l10n.themeSystem),
              ),
              ButtonSegment(
                value: ThemePreference.light,
                label: Text(l10n.themeLight),
              ),
              ButtonSegment(
                value: ThemePreference.dark,
                label: Text(l10n.themeDark),
              ),
            ],
            selected: {settings.theme},
            onSelectionChanged: (s) =>
                notifier.change((a) => a.copyWith(theme: s.first)),
          ),
        ),
        FormRow(
          label: l10n.accentColor,
          child: SegmentedButton<AccentPreference>(
            showSelectedIcon: false,
            // Swatches only, named by their tooltip.
            segments: [
              for (final (value, label) in [
                (AccentPreference.neutral, l10n.accentNeutral),
                (AccentPreference.orange, l10n.accentOrange),
                (AccentPreference.yellow, l10n.accentYellow),
                (AccentPreference.teal, l10n.accentTeal),
                (AccentPreference.blue, l10n.accentBlue),
                (AccentPreference.violet, l10n.accentViolet),
              ])
                ButtonSegment(
                  value: value,
                  tooltip: label,
                  label: _Swatch(
                    Accents.of(value, Theme.of(context).brightness),
                  ),
                ),
            ],
            selected: {settings.accent},
            onSelectionChanged: (s) =>
                notifier.change((a) => a.copyWith(accent: s.first)),
          ),
        ),
        FormRow(
          label: l10n.textSize,
          child: Row(
            children: [
              Text('A', style: text.bodySmall),
              const SizedBox(width: Space.m),
              Expanded(
                child: Slider(
                  value: settings.textScale,
                  min: AppSettings.minTextScale,
                  max: AppSettings.maxTextScale,
                  divisions: 15,
                  label: '${(settings.textScale * 100).round()} %',
                  onChanged: (v) =>
                      notifier.change((a) => a.copyWith(textScale: v)),
                ),
              ),
              const SizedBox(width: Space.m),
              Text('A', style: text.titleLarge),
            ],
          ),
        ),
        FormRow(
          label: l10n.language,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AppSettings.systemLanguage,
                label: Text(l10n.languageSystem),
              ),
              // Language names are shown in their own language.
              const ButtonSegment(value: 'en', label: Text('English')),
              const ButtonSegment(value: 'fr', label: Text('Français')),
            ],
            selected: {settings.language},
            onSelectionChanged: (s) =>
                notifier.change((a) => a.copyWith(language: s.first)),
          ),
        ),
        FormRow(
          label: l10n.showTags,
          child: LightSwitch(
            value: settings.showTags,
            onChanged: (v) => notifier.change((a) => a.copyWith(showTags: v)),
          ),
        ),
      ],
    );
  }
}

/// Side of the square of an accent color.
const _swatch = 12.0;

/// Small square of an accent color.
class _Swatch extends StatelessWidget {
  const _Swatch(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: _swatch,
    height: _swatch,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Radii.xs),
      border: Border.all(color: context.colors.border),
    ),
  );
}
