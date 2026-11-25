import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../path_row.dart';
import 'settings_section.dart';

/// Profile page: the member of this installation.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(l10n.profile, first: true),
        FormRow(label: l10n.yourName, child: const _NameField()),
      ],
    );
  }
}

/// Display name of the local member, saved when editing ends.
class _NameField extends ConsumerStatefulWidget {
  const _NameField();

  @override
  ConsumerState<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends ConsumerState<_NameField> {
  late final _controller = TextEditingController(
    text: ref.read(settingsProvider).identity.displayName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    final identity = ref.read(settingsProvider).identity;
    if (name.isEmpty || name == identity.displayName) return;
    ref
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(identity: identity.withDisplayName(name)));
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) {
      if (!focused) _save();
    },
    child: TextField(
      controller: _controller,
      decoration: const InputDecoration(isDense: true),
      onSubmitted: (_) => _save(),
    ),
  );
}
