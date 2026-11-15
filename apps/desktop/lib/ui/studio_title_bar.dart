import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

/// Height of the title bar.
const studioTitleBarHeight = 40.0;

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

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
        if (onBack != null) ...[
          SizedBox.square(
            dimension: 28,
            child: IconButton(
              tooltip: l10n.back,
              padding: EdgeInsets.zero,
              iconSize: 16,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(width: Space.s),
        ],
        Led(c.accent),
        const SizedBox(width: Space.s),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: 'REAHARVEST',
              style: TextStyle(color: c.text),
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
            child: drag(
              Padding(
                padding: EdgeInsets.only(
                  left: _isMacOS ? 76 : Space.s + Space.xs,
                  right: Space.s,
                ),
                child: Align(alignment: Alignment.centerLeft, child: brand),
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
                    width: 1,
                    indent: 10,
                    endIndent: 10,
                  ),
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
