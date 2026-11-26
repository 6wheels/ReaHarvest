// coverage:ignore-file
import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../logs.dart';
import 'window_behavior.dart';

/// The tray icon, one file for every operating system.
const _trayIconAsset = 'assets/brand/reaharvest-1024.png';

/// [WindowShell] of the real window and notification area (window_manager,
/// tray_manager). On Linux the tray icon is a StatusNotifierItem: GNOME shows
/// it only with the AppIndicator extension.
class DesktopWindowShell implements WindowShell {
  DesktopWindowShell(this._window, this._behavior, this._startup);

  /// Null when the window was not found: the runner still shows it, with
  /// the system frame left to close it.
  final Window? _window;
  final WindowBehavior Function() _behavior;

  /// Steps of startup: the window shown is marked when it is seen.
  final StepTimes _startup;
  final _shown = Completer<void>();

  /// Whether the close button goes through the behavior; off to quit.
  var _preventClose = true;
  ListenerId? _windowListener;
  ListenerId? _createdListener;

  /// The tray icon and what it holds, kept while it is shown: an icon no
  /// longer referenced is removed.
  TrayIcon? _tray;
  Image? _icon;
  Menu? _menu;
  MenuItem? _open;
  MenuItem? _quit;

  /// Completes once the window is shown: at once when it already is, else
  /// when the runner shows it with its first frame (Windows).
  Future<void> get shown => _shown.future;

  void _showed() {
    if (_shown.isCompleted) return;
    _startup.mark('window shown');
    _shown.complete();
    final created = _createdListener;
    if (created != null) WindowManager.instance.removeListener(created);
    _createdListener = null;
  }

  /// Takes the close button over: the window closes through the behavior.
  Future<void> start() async {
    final window = _window;
    if (window == null) {
      _shown.complete();
      return;
    }
    _windowListener = window.addListener((event) {
      if (event is WindowCloseRequestedEvent && _preventClose) {
        event.request.cancel();
        _behavior().closeRequested();
      }
    });
    if (window.isVisible) {
      _showed();
      return;
    }
    // The first sight of a window is reported as its creation.
    final id = window.id;
    _createdListener = WindowManager.instance.addListener((event) {
      if (event is WindowCreatedEvent && event.windowId == id) _showed();
    });
  }

  @override
  Future<void> minimize() async => _window?.minimize();

  @override
  Future<void> hide() async {
    final window = _window;
    if (window == null) return;
    window.isVisibleInTaskbar = false;
    window.hide();
  }

  @override
  Future<void> show() async {
    final window = _window;
    if (window == null) return;
    window.isVisibleInTaskbar = true;
    if (window.isMinimized) window.restore();
    window.show();
    window.focus();
  }

  @override
  Future<void> destroy() async {
    // Each step of quit, logged just before the window is closed: the
    // rest of the quit time is spent outside Dart.
    final quit = StepTimes('Quit');
    final listener = _windowListener;
    if (listener != null) _window?.removeListener(listener);
    // The menu is left alive: quit may run inside the click of its item.
    _tray?.dispose();
    _tray = null;
    quit.mark('tray removed');
    // Closed like by the close button, no longer prevented: the window and
    // the engine are destroyed inside the message loop. Destroying the
    // window first ended the loop; the engine then failed (0xC000041D)
    // after seconds.
    _preventClose = false;
    quit.mark('close allowed');
    Logger('app').info(quit.line);
    final window = _window;
    // Without the window, nothing else ends the process.
    window == null ? exit(0) : window.close();
  }

  @override
  Future<void> setTray(TrayLabels? labels) async {
    if (labels == null) return _removeTray();
    if (_tray != null) {
      // The visible menu follows its items.
      _open!.label = labels.open;
      _quit!.label = labels.quit;
      return;
    }
    final icon = ImageAsset.fromAsset(_trayIconAsset);
    final tray = TrayIcon.create();
    final menu = Menu.create();
    final open = MenuItem.createWithLabelAndType(
      labels.open,
      MenuItemType.normal,
    );
    final quit = MenuItem.createWithLabelAndType(
      labels.quit,
      MenuItemType.normal,
    );
    _tray = tray;
    _icon = icon;
    _menu = menu;
    _open = open;
    _quit = quit;
    if (icon == null ||
        tray == null ||
        menu == null ||
        open == null ||
        quit == null) {
      // Best effort (SPEC §5.1): the application goes on without it.
      Logger('app').warning('The tray icon cannot be created');
      return _removeTray();
    }
    open.addListener((event) {
      if (event is MenuItemClickedEvent) _behavior().open();
    });
    quit.addListener((event) {
      if (event is MenuItemClickedEvent) _behavior().quit();
    });
    menu
      ..addItem(open)
      ..addSeparator()
      ..addItem(quit);
    // Left click opens the window (no click reaches the app on Linux); the
    // right click shows the menu, which Linux panels show themselves.
    tray
      ..icon = icon
      ..setTooltip('ReaHarvest')
      ..setContextMenu(menu)
      ..setContextMenuTrigger(ContextMenuTrigger.rightClicked)
      ..addListener((event) {
        if (event is TrayIconClickedEvent) _behavior().open();
      })
      ..setVisible(true);
  }

  void _removeTray() {
    _tray?.dispose();
    _icon?.dispose();
    _menu?.dispose();
    _open?.dispose();
    _quit?.dispose();
    _tray = null;
    _icon = null;
    _menu = null;
    _open = null;
    _quit = null;
  }
}
