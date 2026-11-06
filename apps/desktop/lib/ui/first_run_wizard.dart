import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'library_form.dart';
import 'reaper_settings.dart';

/// Whether the first-run wizard is shown: on start without any library,
/// until it is finished or postponed.
class WizardActive extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).libraries.isEmpty;

  void close() => state = false;
}

final wizardActiveProvider = NotifierProvider<WizardActive, bool>(
  WizardActive.new,
);

/// First-run wizard (SPEC §5.1): member identity, first library, REAPER.
class FirstRunWizard extends ConsumerStatefulWidget {
  const FirstRunWizard({super.key});

  @override
  ConsumerState<FirstRunWizard> createState() => _FirstRunWizardState();
}

class _FirstRunWizardState extends ConsumerState<FirstRunWizard> {
  static const _steps = 3;

  late final _name = TextEditingController(
    text: ref.read(settingsProvider).identity.displayName,
  );
  var _step = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _close() => ref.read(wizardActiveProvider.notifier).close();

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      await ref
          .read(settingsProvider.notifier)
          .change(
            (s) => s.copyWith(identity: s.identity.withDisplayName(name)),
          );
    }
    setState(() => _step = 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    final (title, hint, body, actions) = switch (_step) {
      0 => (
        l10n.welcomeTitle,
        l10n.welcomeHint,
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.yourName,
            helperText: l10n.yourNameHint,
          ),
          onSubmitted: (_) => _saveName(),
        ),
        [
          TextButton(onPressed: _close, child: Text(l10n.later)),
          FilledButton(onPressed: _saveName, child: Text(l10n.continueAction)),
        ],
      ),
      1 => (
        l10n.libraryStepTitle,
        l10n.libraryStepHint,
        LibraryForm(
          submitLabel: l10n.createLibrary,
          onAdded: () => setState(() => _step = 2),
        ),
        [
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: Text(l10n.back),
          ),
        ],
      ),
      _ => (
        'REAPER',
        l10n.reaperStepHint,
        const ReaperSettings(),
        [FilledButton(onPressed: _close, child: Text(l10n.finish))],
      ),
    };

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: AnimatedSwitcher(
              duration: Motion.medium,
              switchInCurve: Motion.curve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0.03, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(_step),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.stepOf(_step + 1, _steps).toUpperCase(),
                    style: text.labelSmall?.copyWith(
                      color: c.muted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: Space.s),
                  Text(title, style: text.headlineSmall),
                  const SizedBox(height: Space.s),
                  Text(hint, style: text.bodyLarge?.copyWith(color: c.muted)),
                  const SizedBox(height: Space.l),
                  body,
                  const SizedBox(height: Space.l),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: Space.s,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
