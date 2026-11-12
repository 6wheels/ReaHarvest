import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../logs.dart';
import '../theme/app_theme.dart';

final _log = Logger('settings');

/// Loads the settings. When the file is unreadable or newer, runs a small
/// recovery application ([show]) until the user starts with new settings;
/// [quit] ends the process. Nothing is overwritten without that choice.
Future<AppSettings> loadSettingsOrRecover(
  SettingsFile file, {
  required void Function(Widget app) show,
  Future<void> Function(String folder) open = openFolder,
  void Function() quit = _exit,
}) async {
  while (true) {
    try {
      return await file.load();
    } on SettingsNewerException catch (e) {
      _log.severe('Settings written by a newer version', e);
      show(
        SettingsRecoveryApp(
          path: file.path,
          newer: true,
          onOpenFolder: () => open(p.dirname(file.path)),
          onQuit: quit,
        ),
      );
      // Only opening the folder or quitting is possible: wait for the quit.
      await Completer<void>().future;
    } on SettingsUnreadableException catch (e) {
      _log.severe('Settings unreadable', e);
      final choice = Completer<void>();
      show(
        SettingsRecoveryApp(
          path: file.path,
          newer: false,
          onStartNew: () async {
            final aside = await file.setAside();
            _log.warning('Settings kept aside as $aside, starting with new');
            choice.complete();
          },
          onOpenFolder: () => open(p.dirname(file.path)),
          onQuit: quit,
        ),
      );
      await choice.future;
    }
  }
}

// coverage:ignore-start
void _exit() => exit(0);
// coverage:ignore-end

/// Recovery screen shown instead of the application when `settings.json`
/// cannot be used (no settings are available: default theme, system
/// language).
class SettingsRecoveryApp extends StatelessWidget {
  const SettingsRecoveryApp({
    super.key,
    required this.path,
    required this.newer,
    required this.onOpenFolder,
    required this.onQuit,
    this.onStartNew,
  });

  final String path;

  /// Written by a newer version: nothing can be started over.
  final bool newer;
  final VoidCallback onOpenFolder;
  final VoidCallback onQuit;
  final Future<void> Function()? onStartNew;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      newer
                          ? l10n.settingsNewerTitle
                          : l10n.settingsUnreadableTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: Space.m),
                    SelectableText(
                      newer
                          ? l10n.settingsNewerBody(path)
                          : l10n.settingsUnreadableBody(path),
                    ),
                    const SizedBox(height: Space.l),
                    Wrap(
                      spacing: Space.s,
                      runSpacing: Space.s,
                      children: [
                        if (onStartNew case final startNew?)
                          FilledButton(
                            onPressed: startNew,
                            child: Text(l10n.settingsStartNew),
                          ),
                        OutlinedButton(
                          onPressed: onOpenFolder,
                          child: Text(l10n.settingsOpenFolder),
                        ),
                        OutlinedButton(
                          onPressed: onQuit,
                          child: Text(l10n.quit),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
