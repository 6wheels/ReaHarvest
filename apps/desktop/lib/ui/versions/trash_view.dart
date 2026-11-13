import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../widgets.dart';
import 'version_ui_actions.dart';

/// Files in the trash of a title, with their permanent deletion (purge),
/// then the purge of the media no project uses any more (SPEC §5.4).
class TrashView extends ConsumerWidget {
  const TrashView(this.title, {super.key});

  final Title title;

  Future<void> _purge(
    BuildContext context,
    WidgetRef ref,
    List<StorageEntry> files,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirm(
      context,
      title: l10n.purgeTitle(files.length),
      content: l10n.purgeHint,
      action: l10n.deleteForever,
    );
    if (confirmed != true || !context.mounted) return;
    final service = ref.read(versionActionsProvider);
    final List<StorageEntry> unused;
    try {
      unused = await service.purge(title, [for (final f in files) f.path]);
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mediaUnreadable)));
      return;
    } on Object catch (e) {
      fail(messenger, l10n, e);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.trashPurged)));
    if (unused.isEmpty || !context.mounted) return;
    final size = unused.fold(0, (sum, e) => sum + e.size);
    final purgeMedia = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.unusedMediaTitle),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.unusedMediaHint(unused.length, formatSize(size))),
              const SizedBox(height: Space.s),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in unused)
                      Text(
                        '${p.posix.basename(e.path)} · ${formatSize(e.size)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.keep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteForever),
          ),
        ],
      ),
    );
    if (purgeMedia != true) return;
    try {
      await service.purgeUnusedMedia(title, [for (final e in unused) e.path]);
      messenger.showSnackBar(SnackBar(content: Text(l10n.mediaPurged)));
    } on Object catch (e) {
      fail(messenger, l10n, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final files = ref.watch(trashProvider(title.id)).value ?? const [];
    final format = DateFormat.yMMMd(l10n.localeName).add_Hm();
    if (files.isEmpty) {
      return Center(
        child: Text(
          l10n.trashEmpty,
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
      );
    }
    String name(StorageEntry e) {
      final relative = title.path.isEmpty
          ? e.path
          : p.posix.relative(e.path, from: title.path);
      return [
        for (final s in relative.split('/'))
          if (s.toLowerCase() != trashFolderName) s,
      ].join('/');
    }

    return ListView(
      padding: const EdgeInsets.all(Space.xl),
      children: [
        Row(
          children: [
            Expanded(
              child: SectionLabel(
                '${l10n.trash} · ${formatSize(files.fold(0, (s, e) => s + e.size))}',
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              onPressed: () => _purge(context, ref, files),
              label: Text(l10n.emptyTrash),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        for (final e in files)
          Row(
            children: [
              Icon(
                isProjectFile(e.path)
                    ? Icons.music_note_outlined
                    : Icons.insert_drive_file_outlined,
                size: 16,
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  name(e),
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              Text(
                '${formatSize(e.size)} · ${format.format(e.modified)}',
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
              IconButton(
                tooltip: l10n.deleteForever,
                onPressed: () => _purge(context, ref, [e]),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
      ],
    );
  }
}
