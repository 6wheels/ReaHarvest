import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'tasks.dart';

/// The window and the tray icon of the operating system (SPEC §5.1);
/// replaced by a fake in tests.
abstract interface class WindowShell {
  Future<void> minimize();

  /// Hides the window: only the tray icon is left.
  Future<void> hide();

  /// Shows the window again and gives it the focus.
  Future<void> show();

  /// Ends the application.
  Future<void> destroy();

  /// Shows (or hides, when [labels] is null) the tray icon, with its menu.
  Future<void> setTray(TrayLabels? labels);
}

/// Texts of the tray menu.
typedef TrayLabels = ({String open, String quit});

final windowShellProvider = Provider<WindowShell>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Asks whether to quit while [tasks] run or wait; true to cancel them and
/// quit. Overridden in main() by the dialog.
final quitConfirmerProvider =
    Provider<Future<bool> Function(List<BackgroundTask> tasks)>(
      (ref) => throw UnimplementedError('Overridden in main()'),
    );

/// What closing the window, the tray menu and the opening of a project do
/// (SPEC §5.1, §5.7).
class WindowBehavior {
  WindowBehavior(this.ref);

  final Ref ref;

  WindowShell get _shell => ref.read(windowShellProvider);

  /// Starts to keep the tray icon in line with the settings.
  void start() {
    ref.listen(
      settingsProvider.select((s) => (s.showInTray, s.language)),
      (_, _) => _syncTray(),
      fireImmediately: true,
    );
  }

  Future<void> _syncTray() {
    final settings = ref.read(settingsProvider);
    if (!settings.showInTray) return _shell.setTray(null);
    final code = settings.language == AppSettings.systemLanguage
        ? PlatformDispatcher.instance.locale.languageCode
        : settings.language;
    final l10n = lookupAppLocalizations(
      AppLocalizations.supportedLocales.any((l) => l.languageCode == code)
          ? Locale(code)
          : AppLocalizations.supportedLocales.first,
    );
    return _shell.setTray((open: l10n.trayOpen, quit: l10n.quit));
  }

  /// The window is asked to close: hidden to the tray, or the application
  /// quits.
  Future<void> closeRequested() => ref.read(settingsProvider).showInTray
      ? _shell.hide()
      : quit();

  /// Tray menu "Open ReaHarvest".
  Future<void> open() => _shell.show();

  /// Quits, after asking when tasks run or wait.
  Future<void> quit() async {
    final tasks = _active;
    if (tasks.isNotEmpty) {
      // Quit from the tray: the question needs the window.
      await _shell.show();
      if (!await ref.read(quitConfirmerProvider)(tasks)) return;
      final notifier = ref.read(tasksProvider.notifier);
      for (final t in tasks) {
        notifier.cancel(t.id);
      }
    }
    await _shell.destroy();
  }

  /// A project was opened in REAPER: applies the window option. "Close"
  /// minimizes instead while a task runs.
  Future<void> projectOpened() {
    final settings = ref.read(settingsProvider);
    return switch (settings.onProjectOpen) {
      ProjectOpenAction.nothing => Future.value(),
      ProjectOpenAction.minimize => _shell.minimize(),
      ProjectOpenAction.close when _active.isNotEmpty => _shell.minimize(),
      ProjectOpenAction.close => closeRequested(),
    };
  }

  List<BackgroundTask> get _active => [
    for (final t in ref.read(tasksProvider))
      if (t.isRunning || t.isQueued) t,
  ];
}

final windowBehaviorProvider = Provider<WindowBehavior>(WindowBehavior.new);
