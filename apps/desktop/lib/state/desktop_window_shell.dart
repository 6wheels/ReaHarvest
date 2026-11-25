// coverage:ignore-file
import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import '../logs.dart';
import 'window_behavior.dart';

/// [WindowShell] of the real window and notification area (window_manager,
/// tray_manager). Linux needs an appindicator library for the tray icon.
class DesktopWindowShell
    with WindowListener, TrayListener
    implements WindowShell {
  DesktopWindowShell(this._behavior, this._startup);

  final WindowBehavior Function() _behavior;

  /// Steps of startup: the window shown is marked when it is seen.
  final StepTimes _startup;
  TrayLabels? _labels;
  final _shown = Completer<void>();

  /// Completes once the window is shown: at once when it already is, else
  /// when the runner shows it with its first frame (Windows).
  Future<void> get shown => _shown.future;

  void _showed() {
    if (_shown.isCompleted) return;
    _startup.mark('window shown');
    _shown.complete();
  }

  /// Takes the close button over: the window closes through the behavior.
  Future<void> start() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    if (await windowManager.isVisible()) _showed();
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'show') _showed();
  }

  @override
  void onWindowClose() => _behavior().closeRequested();

  @override
  void onTrayIconMouseDown() => _behavior().open();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) => switch (menuItem.key) {
    'open' => _behavior().open(),
    _ => _behavior().quit(),
  };

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> hide() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  @override
  Future<void> show() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> destroy() async {
    // Each step of quit, logged just before the window is closed: the
    // rest of the quit time is spent outside Dart.
    final quit = StepTimes('Quit');
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
    quit.mark('tray removed');
    // Closed like by the close button, no longer prevented: the window and
    // the engine are destroyed inside the message loop. `destroy()` ends
    // the loop first; the engine then failed (0xC000041D) after seconds.
    await windowManager.setPreventClose(false);
    quit.mark('close allowed');
    Logger('app').info(quit.line);
    await windowManager.close();
  }

  @override
  Future<void> setTray(TrayLabels? labels) async {
    if (labels == null) {
      if (_labels != null) await trayManager.destroy();
      _labels = null;
      return;
    }
    if (_labels == null) {
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/tray/tray_icon.ico'
            : 'assets/brand/reaharvest-1024.png',
      );
    }
    _labels = labels;
    await trayManager.setToolTip('ReaHarvest');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: labels.open),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: labels.quit),
        ],
      ),
    );
  }
}
