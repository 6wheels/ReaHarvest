import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../../l10n/app_localizations.dart';
import '../../state/tasks.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../kit/kit.dart';
import 'version_ui_actions.dart';

/// Entries in the trash of a title (version folders and assets), with
/// their permanent deletion (purge, SPEC §5.4).
class TrashView extends ConsumerWidget {
  const TrashView(this.title, {super.key});

  final Title title;

  Future<void> _purge(
    BuildContext context,
    WidgetRef ref,
    List<StorageEntry> files, {
    required String action,
  }) async {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.read(tasksProvider.notifier);
    final confirmed = await confirm(
      context,
      title: l10n.purgeTitle(files.length),
      content: l10n.purgeHint,
      action: action,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(versionActionsProvider).purge(title, [
        for (final f in files) f.path,
      ]);
      tasks.notify(l10n.trashPurged);
    } on Object catch (e) {
      fail(tasks, l10n, e);
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

    final trashSize = formatSize(files.fold(0, (s, e) => s + e.size));
    return ListView(
      padding: const EdgeInsets.all(Space.xl),
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel('${l10n.trash} · $trashSize')),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined, size: IconSize.l),
              onPressed: () =>
                  _purge(context, ref, files, action: l10n.emptyTrash),
              label: Text(l10n.emptyTrash),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        for (final e in files)
          Row(
            children: [
              Icon(
                e.isDirectory
                    ? Icons.folder_outlined
                    : isProjectFile(e.path)
                    ? Icons.music_note_outlined
                    : Icons.insert_drive_file_outlined,
                size: IconSize.m,
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
                onPressed: () =>
                    _purge(context, ref, [e], action: l10n.deleteForever),
                icon: const Icon(Icons.close_rounded, size: IconSize.l),
              ),
            ],
          ),
      ],
    );
  }
}
