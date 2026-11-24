import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../../l10n/app_localizations.dart';
import '../../state/library_catalog.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../glass_dialog.dart';
import '../known_values_editor.dart';
import '../library_form.dart';
import '../members_editor.dart';
import 'settings_section.dart';

/// Width of the dialog.
const _width = 560.0;

/// Libraries page: configured libraries, with removal and addition.
class LibrariesPage extends StatelessWidget {
  const LibrariesPage({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsSection(AppLocalizations.of(context).libraries, first: true),
      const _Libraries(),
    ],
  );
}

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
                  OutlinedButton(
                    onPressed: () => showKnownValues(context, library, layout),
                    child: Text(l10n.knownValues),
                  ),
                OutlinedButton(
                  onPressed: () => showMembers(context, library),
                  child: Text(l10n.members),
                ),
                OutlinedButton(
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
    final confirmed = await showGlassDialog<bool>(
      context,
      (context) => AlertDialog(
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
      await ref.read(libraryCatalogProvider).remove(library.id);
    }
  }

  Future<void> _add(BuildContext context) =>
      showGlassDialog<void>(context, (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.addLibrary),
          content: SizedBox(
            width: _width,
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
      });
}
