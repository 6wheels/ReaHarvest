import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'l10n/app_localizations.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'ui/first_run_wizard.dart';
import 'ui/library_page.dart';

class ReaHarvestApp extends ConsumerWidget {
  const ReaHarvestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (settings.theme) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      },
      themeAnimationDuration: Motion.medium,
      // System language when null; English when it is not supported (first
      // supported locale).
      locale: settings.language == AppSettings.systemLanguage
          ? null
          : Locale(settings.language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(settings.textScale)),
        child: child!,
      ),
      home: AnimatedSwitcher(
        duration: Motion.slow,
        child: ref.watch(wizardActiveProvider)
            ? const FirstRunWizard()
            : const LibraryPage(),
      ),
    );
  }
}
