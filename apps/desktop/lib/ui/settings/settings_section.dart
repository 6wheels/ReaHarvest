import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';

/// Small uppercase title of a section of a settings page.
class SettingsSection extends StatelessWidget {
  const SettingsSection(this.title, {super.key, this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : Space.l, bottom: Space.m),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: context.colors.muted, letterSpacing: Tracking.wide),
    ),
  );
}
