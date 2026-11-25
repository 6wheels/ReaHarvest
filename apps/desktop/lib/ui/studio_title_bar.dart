import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'kit/kit.dart';

/// Height of the title bar.
const studioTitleBarHeight = 40.0;

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool get _isWindows =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Title bar drawn by the application (the system one is hidden), at the
/// top of every page: brand and location on the left, an optional [center]
/// control (search), [trailing] actions and the window buttons. Empty
/// parts move the window.
class StudioTitleBar extends StatelessWidget {
  const StudioTitleBar({
    super.key,
    this.location,
    this.onBack,
    this.center,
    this.trailing,
  });

  /// Where the user is, after the brand (`REAHARVEST // TO SORT`).
  final String? location;

  /// Shows a back button before the brand.
  final VoidCallback? onBack;

  final Widget? center;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    Widget drag(Widget child) =>
        _isDesktop ? DragToMoveArea(child: child) : child;

    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Led(c.accent),
        const SizedBox(width: Space.s),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: 'REAHARVEST',
              style: AppText.color(c.text),
              children: [
                if (location case final location?)
                  TextSpan(text: '$labelSeparator${location.toUpperCase()}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.legend,
          ),
        ),
      ],
    );

    return Container(
      height: studioTitleBarHeight,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: _isMacOS ? 76 : Space.s + Space.xs,
              ),
              child: Row(
                children: [
                  // Outside the move area: a click goes back at once,
                  // without waiting for a double click.
                  if (onBack != null) ...[
                    SizedBox.square(
                      dimension: 28,
                      child: IconButton(
                        tooltip: l10n.back,
                        padding: EdgeInsets.zero,
                        iconSize: IconSize.m,
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                  ],
                  Expanded(
                    child: drag(
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: brand,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ?center,
          Expanded(
            child: Row(
              children: [
                Expanded(child: drag(const SizedBox.expand())),
                if (trailing != null) ...[
                  trailing!,
                  const SizedBox(width: Space.xs),
                ],
                if (_isDesktop && !_isMacOS) ...[
                  VerticalDivider(
                    color: c.border,
                    width: Sizes.hairline,
                    indent: Space.md,
                    endIndent: Space.md,
                  ),
                  // Console buttons on Windows, the system look elsewhere.
                  if (_isWindows)
                    const _ConsoleWindowButtons()
                  else
                    _WindowButtons(Theme.of(context).brightness),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons(this.brightness);

  final Brightness brightness;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      WindowCaptionButton.minimize(
        brightness: brightness,
        onPressed: windowManager.minimize,
      ),
      WindowCaptionButton.maximize(
        brightness: brightness,
        onPressed: () async => await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize(),
      ),
      WindowCaptionButton.close(
        brightness: brightness,
        onPressed: windowManager.close,
      ),
    ],
  );
}

/// Window buttons drawn in the style of the application (Windows): glyphs
/// glowing on hover, the close one a red key.
class _ConsoleWindowButtons extends StatefulWidget {
  const _ConsoleWindowButtons();

  @override
  State<_ConsoleWindowButtons> createState() => _ConsoleWindowButtonsState();
}

class _ConsoleWindowButtonsState extends State<_ConsoleWindowButtons>
    with WindowListener {
  var _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((m) {
      if (mounted) setState(() => _maximized = m);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: Icons.remove_rounded,
          tooltip: l10n.minimizeWindow,
          onPressed: windowManager.minimize,
        ),
        _CaptionButton(
          icon: _maximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          iconSize: _maximized ? 12 : 14,
          tooltip: _maximized ? l10n.restoreWindow : l10n.maximizeWindow,
          onPressed: _maximized
              ? windowManager.unmaximize
              : windowManager.maximize,
        ),
        _CaptionButton(
          icon: Icons.close_rounded,
          tooltip: l10n.close,
          onPressed: windowManager.close,
          danger: true,
        ),
      ],
    );
  }
}

/// One window button: the height of the title bar, no cap, a muted glyph
/// glowing on hover like the other icon buttons; [danger] turns it into a
/// red key on hover (close). Its tooltip waits longer than the others: the
/// window buttons are well known.
class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 15,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool danger;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: Motion.tooltip,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      style: (danger ? closeKeyStyle(context) : glowButtonStyle(context)).merge(
        IconButton.styleFrom(
          fixedSize: const Size(Sizes.windowButton, studioTitleBarHeight),
          iconSize: iconSize,
        ).merge(Theme.of(context).iconButtonTheme.style),
      ),
    ),
  );
}
