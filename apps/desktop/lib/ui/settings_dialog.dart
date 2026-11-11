import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'known_values_editor.dart';
import 'library_form.dart';
import 'members_editor.dart';
import 'path_row.dart';
import 'reaper_settings.dart';

/// Opens the settings as a popup over the blurred application (SPEC §5.2).
Future<void> showSettings(BuildContext context) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: AppLocalizations.of(context).close,
  barrierColor: Colors.transparent,
  transitionDuration: Motion.medium,
  pageBuilder: (_, _, _) => const _SettingsPanel(),
  transitionBuilder: (context, animation, _, child) {
    final t = CurvedAnimation(
      parent: animation,
      curve: Motion.curve,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: t,
              builder: (context, _) => BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 16 * t.value,
                  sigmaY: 16 * t.value,
                ),
                child: ColoredBox(
                  color: context.colors.scrim.withValues(alpha: 0.45 * t.value),
                ),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(t),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(t),
              child: child,
            ),
          ),
        ),
      ],
    );
  },
);

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: c.border),
          ),
          elevation: 24,
          shadowColor: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.m,
              Space.s,
              Space.l,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l10n.settings, style: text.titleLarge),
                    ),
                    IconButton(
                      tooltip: l10n.close,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Space.m),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: Space.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Section(l10n.appearance, first: true),
                        FormRow(
                          label: l10n.theme,
                          child: SegmentedButton<ThemePreference>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: ThemePreference.system,
                                label: Text(l10n.themeSystem),
                              ),
                              ButtonSegment(
                                value: ThemePreference.light,
                                label: Text(l10n.themeLight),
                              ),
                              ButtonSegment(
                                value: ThemePreference.dark,
                                label: Text(l10n.themeDark),
                              ),
                            ],
                            selected: {settings.theme},
                            onSelectionChanged: (s) => notifier.change(
                              (a) => a.copyWith(theme: s.first),
                            ),
                          ),
                        ),
                        FormRow(
                          label: l10n.textSize,
                          child: Row(
                            children: [
                              Text('A', style: text.bodySmall),
                              Expanded(
                                child: Slider(
                                  value: settings.textScale,
                                  min: 0.85,
                                  max: 1.3,
                                  divisions: 9,
                                  label:
                                      '${(settings.textScale * 100).round()} %',
                                  onChanged: (v) => notifier.change(
                                    (a) => a.copyWith(textScale: v),
                                  ),
                                ),
                              ),
                              Text('A', style: text.titleLarge),
                            ],
                          ),
                        ),
                        FormRow(
                          label: l10n.language,
                          child: SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: AppSettings.systemLanguage,
                                label: Text(l10n.languageSystem),
                              ),
                              // Language names are shown in their own language.
                              const ButtonSegment(
                                value: 'en',
                                label: Text('English'),
                              ),
                              const ButtonSegment(
                                value: 'fr',
                                label: Text('Français'),
                              ),
                            ],
                            selected: {settings.language},
                            onSelectionChanged: (s) => notifier.change(
                              (a) => a.copyWith(language: s.first),
                            ),
                          ),
                        ),
                        _Section(l10n.profile),
                        FormRow(
                          label: l10n.yourName,
                          child: const _NameField(),
                        ),
                        _Section(l10n.libraries),
                        const _Libraries(),
                        const _Section('REAPER'),
                        const ReaperSettings(),
                        _Section(l10n.logs),
                        FormRow(
                          label: l10n.logFolder,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ref.watch(logFolderProvider),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(
                                    color: c.muted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Space.s),
                              TextButton(
                                onPressed: () => ref.read(openFolderProvider)(
                                  ref.read(logFolderProvider),
                                ),
                                child: Text(l10n.openFolder),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : Space.l, bottom: Space.m),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: context.colors.muted, letterSpacing: 1.2),
    ),
  );
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

/// Configured libraries, with removal and addition.
class _Libraries extends ConsumerWidget {
  const _Libraries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final libraries = ref.watch(settingsProvider.select((s) => s.libraries));
    final indexed = ref.watch(indexedLibrariesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (libraries.isEmpty)
          Text(
            l10n.noLibrary,
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
        for (final library in libraries)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(library.displayName, style: text.bodyLarge),
                      Text(
                        library.libraryRoot,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                // Known values of the intermediate levels (SPEC §3.1).
                if (indexed[library.id]?.layout case final layout?
                    when layout.levels.length > 1)
                  TextButton(
                    onPressed: () => showKnownValues(context, library, layout),
                    child: Text(l10n.knownValues),
                  ),
                TextButton(
                  onPressed: () => showMembers(context, library),
                  child: Text(l10n.members),
                ),
                TextButton(
                  onPressed: () => _confirmRemoval(context, ref, library),
                  child: Text(l10n.removeLibrary),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.s),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.addLibrary),
          onPressed: () => _add(context),
        ),
      ],
    );
  }

  Future<void> _confirmRemoval(
    BuildContext context,
    WidgetRef ref,
    LibraryEntry library,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeLibraryTitle(library.displayName)),
        content: Text(l10n.removeLibraryHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.removeLibrary),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(libraryServiceProvider).remove(library.id);
    }
  }

  Future<void> _add(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.addLibrary),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: LibraryForm(
              submitLabel: l10n.addLibrary,
              // The report of the scan is already open over this dialog:
              // close this dialog, not the top route.
              onAdded: () =>
                  Navigator.of(context).removeRoute(ModalRoute.of(context)!),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      );
    },
  );
}
