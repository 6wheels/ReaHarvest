// coverage:ignore-file
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'window_behavior.dart';

/// [WindowShell] of the real window and notification area (window_manager,
/// tray_manager). Linux needs an appindicator library for the tray icon.
class DesktopWindowShell
    with WindowListener, TrayListener
    implements WindowShell {
  DesktopWindowShell(this._behavior);

  final WindowBehavior Function() _behavior;
  TrayLabels? _labels;

  /// Takes the close button over: the window closes through the behavior.
  Future<void> start() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
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
    await trayManager.destroy();
    await windowManager.destroy();
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
