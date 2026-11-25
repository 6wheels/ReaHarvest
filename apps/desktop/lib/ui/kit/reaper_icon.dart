import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';

/// REAPER logo, the icon of the actions opening a project in REAPER
/// (used with the permission of Cockos, see `assets/third_party/reaper`).
class ReaperIcon extends StatelessWidget {
  const ReaperIcon({super.key, this.size = IconSize.m});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/third_party/reaper/reaper.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
  );
}
