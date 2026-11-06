import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

/// Opens the settings as a popup over the blurred application (SPEC §5.2).
Future<void> showSettings(BuildContext context) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: AppLocalizations.of(context).close,
  barrierColor: Colors.transparent,
  transitionDuration: Motion.medium,
  pageBuilder: (_, _, _) => const _SettingsPanel(),
  transitionBuilder: (context, animation, _, child) {
    final t = CurvedAnimation(
      parent: animation,
      curve: Motion.curve,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: t,
              builder: (context, _) => BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 16 * t.value,
                  sigmaY: 16 * t.value,
                ),
                child: ColoredBox(
                  color: context.colors.scrim.withValues(alpha: 0.45 * t.value),
                ),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(t),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(t),
              child: child,
            ),
          ),
        ),
      ],
    );
  },
);

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
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
              mainAxisSize: MainAxisSize.min,
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
                Padding(
                  padding: const EdgeInsets.only(right: Space.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.appearance.toUpperCase(),
                        style: text.labelSmall?.copyWith(
                          color: c.muted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: Space.m),
                      _Row(
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
                      _Row(
                        label: l10n.textSize,
                        child: Row(
                          children: [
                            Text('A', style: text.bodySmall),
                            Expanded(
                              child: Slider(
                                value: settings.textScale,
                                min: 0.85,
                                max: 1.3,
                                divisions: 9,
                                label: '${(settings.textScale * 100).round()} %',
                                onChanged: (v) => notifier.change(
                                  (a) => a.copyWith(textScale: v),
                                ),
                              ),
                            ),
                            Text('A', style: text.titleLarge),
                          ],
                        ),
                      ),
                      _Row(
                        label: l10n.language,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: AppSettings.systemLanguage,
                              label: Text(l10n.languageSystem),
                            ),
                            // Language names are shown in their own language.
                            const ButtonSegment(
                              value: 'en',
                              label: Text('English'),
                            ),
                            const ButtonSegment(
                              value: 'fr',
                              label: Text('Français'),
                            ),
                          ],
                          selected: {settings.language},
                          onSelectionChanged: (s) => notifier.change(
                            (a) => a.copyWith(language: s.first),
                          ),
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.m),
    child: Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ],
    ),
  );
}
