import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'glass_dialog.dart';
import 'settings/about_page.dart';
import 'settings/appearance_page.dart';
import 'settings/libraries_page.dart';
import 'settings/profile_page.dart';
import 'settings/system_page.dart';

/// Opens the settings as a popup over the blurred application (SPEC §5.2).
Future<void> showSettings(BuildContext context) =>
    showGlassDialog<void>(context, (_) => const _SettingsPanel());

/// One page of the settings, with its entry in the left menu.
enum _SettingsPage {
  appearance(Icons.palette_outlined),
  profile(Icons.person_outline_rounded),
  libraries(Icons.folder_copy_outlined),
  system(Icons.tune_rounded),
  about(Icons.info_outline_rounded);

  const _SettingsPage(this.icon);

  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
    appearance => l10n.appearance,
    profile => l10n.profile,
    libraries => l10n.libraries,
    system => l10n.pageSystem,
    about => l10n.about,
  };

  Widget get body => switch (this) {
    appearance => const AppearancePage(),
    profile => const ProfilePage(),
    libraries => const LibrariesPage(),
    system => const SystemPage(),
    about => const AboutPage(),
  };
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel();

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  // Kept while the popup is open.
  var _page = _SettingsPage.appearance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SizedBox(
        width: 820,
        height: 560,
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.m),
            side: BorderSide(color: c.border),
          ),
          elevation: 24,
          shadowColor: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.m,
              Space.s,
              Space.l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l10n.settings, style: text.titleLarge),
                    ),
                    IconButton(
                      tooltip: l10n.close,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Space.m),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 160,
                        child: Column(
                          children: [
                            for (final page in _SettingsPage.values)
                              _MenuEntry(
                                icon: page.icon,
                                label: page.label(l10n),
                                selected: page == _page,
                                onTap: () => setState(() => _page = page),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey(_page),
                          padding: const EdgeInsets.only(right: Space.m),
                          child: _page.body,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Entry of the left menu; the selected one is bold and has a bar, not only a
/// different color.
class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Material(
        color: selected ? c.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.s),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.s),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s,
              vertical: Space.s,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? c.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? c.accent : c.muted),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
