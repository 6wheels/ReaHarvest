import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/pickers.dart';
import '../state/providers.dart';
import '../state/reaper.dart';
import '../theme/app_theme.dart';
import 'path_row.dart';

/// REAPER paths (configured or default) and the peaks preference check
/// (SPEC §5.1).
class ReaperSettings extends ConsumerWidget {
  const ReaperSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final pickers = ref.read(pickersProvider);
    final executable = ref.watch(reaperExecutableProvider);
    final resources = ref.watch(reaperResourcesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PathRow(
          label: l10n.reaperExecutable,
          value: executable.value,
          placeholder: executable.isLoading ? '…' : l10n.notFound,
          onChoose: () async {
            final path = await pickers.reaperExecutable();
            if (path != null) {
              await notifier.change((s) => s.copyWith(reaperExecutable: path));
            }
          },
          onReset: settings.reaperExecutable == null
              ? null
              : () =>
                    notifier.change((s) => s.copyWith(reaperExecutable: null)),
        ),
        PathRow(
          label: l10n.reaperResources,
          value: resources,
          placeholder: l10n.notFound,
          onChoose: () async {
            final path = await pickers.folder(initial: resources);
            if (path != null) {
              await notifier.change((s) => s.copyWith(reaperResources: path));
            }
          },
          onReset: settings.reaperResources == null
              ? null
              : () => notifier.change((s) => s.copyWith(reaperResources: null)),
        ),
        PathRow(
          label: l10n.templatesFolder,
          value: ref.watch(templatesFolderProvider),
          placeholder: l10n.notFound,
          onChoose: () async {
            final path = await pickers.folder(
              initial: ref.read(templatesFolderProvider),
            );
            if (path != null) {
              await notifier.change((s) => s.copyWith(templatesFolder: path));
            }
          },
          onReset: settings.templatesFolder == null
              ? null
              : () => notifier.change((s) => s.copyWith(templatesFolder: null)),
        ),
        const PeaksWarning(),
      ],
    );
  }
}

/// Non-blocking warning when REAPER stores peak files next to the projects.
class PeaksWarning extends ConsumerWidget {
  const PeaksWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peaks = ref.watch(peaksPreferenceProvider).value;
    final c = context.colors;
    return AnimatedSize(
      duration: Motion.medium,
      curve: Motion.curve,
      child: peaks == null || peaks.isRecommended
          ? const SizedBox(width: double.infinity)
          : Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: c.accent),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).peaksWarning,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
