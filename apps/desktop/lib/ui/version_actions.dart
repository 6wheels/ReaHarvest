import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'widgets.dart';

/// Version management of the title detail (SPEC §5.4): creation, rename,
/// status, deletion, trash and purge.

/// File size in B, KB, MB or GB.
String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

/// [name] with the `.RPP` extension when it has none.
String withProjectExtension(String name) {
  final trimmed = name.trim();
  return isProjectFile(trimmed) ? trimmed : '$trimmed.RPP';
}

/// Why [name] cannot be the file name of a version of [title] (other than
/// its version [current]); null when it can.
String? versionNameError(
  AppLocalizations l10n,
  Title title,
  String name, {
  String? current,
}) {
  final file = withProjectExtension(name);
  if (!isValidFolderName(file) ||
      p.posix.basenameWithoutExtension(file).trim().isEmpty) {
    return l10n.invalidVersionName;
  }
  final lower = file.toLowerCase();
  final taken = title.versions.any(
    (v) => v.fileName != current && v.fileName.toLowerCase() == lower,
  );
  return taken ? l10n.versionNameTaken : null;
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String content,
  required String action,
  String? cancel,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancel ?? l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
}

void _fail(ScaffoldMessengerState messenger, AppLocalizations l10n, Object e) =>
    messenger.showSnackBar(SnackBar(content: Text(failureMessage(l10n, e))));

/// Source of a new version.
enum _Source { blank, template, duplicate }

/// Asks for a new version of [title] (blank, from a template, or a copy of
/// [selected]) and creates it. Returns its file name, null when cancelled.
Future<String?> showNewVersionDialog(
  BuildContext context,
  Title title,
  Version? selected,
) => showDialog<String>(
  context: context,
  builder: (_) => _NewVersionDialog(title, selected),
);

class _NewVersionDialog extends ConsumerStatefulWidget {
  const _NewVersionDialog(this.title, this.selected);

  final Title title;
  final Version? selected;

  @override
  ConsumerState<_NewVersionDialog> createState() => _NewVersionDialogState();
}

class _NewVersionDialogState extends ConsumerState<_NewVersionDialog> {
  final _label = TextEditingController();
  late final _name = TextEditingController(text: _suggested);
  var _source = _Source.blank;
  String? _template;

  /// The file name follows the label until edited by hand.
  var _nameEdited = false;

  /// The label is required: its error shows once it has been typed in.
  var _labelEdited = false;
  var _busy = false;

  String get _suggested =>
      suggestedVersionName(titleName(widget.title), _label.text);

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    if (versionNameError(l10n, widget.title, _name.text) != null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final name = await ref
          .read(libraryServiceProvider)
          .addVersion(
            widget.title,
            withProjectExtension(_name.text),
            _label.text,
            source: _source == _Source.duplicate ? widget.selected : null,
            template: _source == _Source.template ? _template : null,
          );
      navigator.pop(name);
    } on Object catch (e) {
      _fail(messenger, l10n, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final templates =
        ref.watch(projectTemplatesProvider(widget.title.libraryId)).value ??
        const <String>[];
    // Shown only when written: the library declares the local member.
    final owner =
        ref.read(libraryServiceProvider).localOwner(widget.title.libraryId) ==
            null
        ? null
        : ref.watch(settingsProvider.select((s) => s.identity.displayName));
    final selected = widget.selected;
    final error = versionNameError(l10n, widget.title, _name.text);
    final labelMissing = _label.text.trim().isEmpty;
    final ready =
        !_busy &&
        error == null &&
        !labelMissing &&
        (_source != _Source.template || _template != null);
    Widget source(_Source value, String label, {String? hint, bool? enabled}) =>
        RadioListTile<_Source>(
          value: value,
          dense: true,
          contentPadding: EdgeInsets.zero,
          enabled: enabled ?? true,
          title: Text(label),
          subtitle: hint == null ? null : Text(hint),
        );
    return AlertDialog(
      title: Text(l10n.newVersion),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<_Source>(
              groupValue: _source,
              onChanged: (v) => setState(() => _source = v ?? _source),
              child: Column(
                children: [
                  source(
                    _Source.blank,
                    l10n.versionSourceBlank,
                    hint: l10n.versionSourceBlankHint,
                  ),
                  source(
                    _Source.template,
                    l10n.versionSourceTemplate,
                    hint: templates.isEmpty ? l10n.noTemplate : null,
                    enabled: templates.isNotEmpty,
                  ),
                  if (selected != null)
                    source(
                      _Source.duplicate,
                      l10n.versionSourceDuplicate(
                        p.posix.withoutExtension(selected.fileName),
                      ),
                    ),
                ],
              ),
            ),
            if (_source == _Source.template)
              DropdownButtonFormField<String>(
                initialValue: _template,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.versionSourceTemplate,
                  isDense: true,
                ),
                items: [
                  for (final t in templates)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        p.basenameWithoutExtension(t),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _template = v),
              ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _label,
              autofocus: true,
              onChanged: (_) => setState(() {
                _labelEdited = true;
                if (!_nameEdited) _name.text = _suggested;
              }),
              decoration: InputDecoration(
                labelText: l10n.versionLabel,
                errorText: _labelEdited && labelMissing
                    ? l10n.labelRequired
                    : null,
                isDense: true,
              ),
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() => _nameEdited = true),
              onSubmitted: (_) => ready ? _create() : null,
              decoration: InputDecoration(
                labelText: l10n.fileName,
                errorText: error,
                isDense: true,
              ),
            ),
            if (owner != null) ...[
              const SizedBox(height: Space.s),
              Text(
                l10n.filterValue(l10n.filterOwner, owner),
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: ready ? _create : null,
          child: BusyLabel(l10n.create, busy: _busy),
        ),
      ],
    );
  }
}

/// Asks for a new file name and label of [version] of [title] and applies
/// them. A rename waits for the REAPER warning (SPEC §5.7); a label, stored
/// outside the project, does not (SPEC §4.2). Returns its file name, null
/// when cancelled or failed.
Future<String?> showEditVersionDialog(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final values = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _EditVersionDialog(title, version),
  );
  if (values == null || !context.mounted) return null;
  final (name, label) = values;
  if (name == version.fileName && label == (version.metadata?.label ?? '')) {
    return null;
  }
  Future<String> edit() => ref
      .read(libraryServiceProvider)
      .editVersion(title, version, fileName: name, label: label);
  if (name != version.fileName) {
    String? result;
    await runProjectChange(context, ref, () async => result = await edit());
    return result;
  }
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    return await edit();
  } on Object catch (e) {
    _fail(messenger, l10n, e);
    return null;
  }
}

class _EditVersionDialog extends StatefulWidget {
  const _EditVersionDialog(this.title, this.version);

  final Title title;
  final Version version;

  @override
  State<_EditVersionDialog> createState() => _EditVersionDialogState();
}

class _EditVersionDialogState extends State<_EditVersionDialog> {
  late final _name = TextEditingController(text: widget.version.fileName);
  late final _label = TextEditingController(
    text: widget.version.metadata?.label ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    super.dispose();
  }

  String? _error(AppLocalizations l10n) => versionNameError(
    l10n,
    widget.title,
    _name.text,
    current: widget.version.fileName,
  );

  /// An adopted version keeps a label (SPEC §4.2).
  bool get _labelMissing =>
      widget.version.isAdopted && _label.text.trim().isEmpty;

  void _save() {
    if (_error(AppLocalizations.of(context)) != null || _labelMissing) return;
    Navigator.of(context)
        .pop((withProjectExtension(_name.text), _label.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adopted = widget.version.isAdopted;
    final error = _error(l10n);
    return AlertDialog(
      title: Text(l10n.editVersionTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: l10n.fileName,
                errorText: error,
                isDense: true,
              ),
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _label,
              enabled: adopted,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: l10n.versionLabel,
                helperText: adopted ? null : l10n.labelNeedsAdoption,
                errorText: _labelMissing ? l10n.labelRequired : null,
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: error == null && !_labelMissing ? _save : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Sets the [status] of [version] of [title]; failures in a snackbar.
Future<void> setVersionStatusFromUi(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
  String? status,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(libraryServiceProvider).setStatusOf(title, version, status);
  } on Object catch (e) {
    _fail(messenger, l10n, e);
  }
}

/// Moves [version] of [title] to the trash, after confirmation and the
/// REAPER warning.
Future<void> deleteVersionFromUi(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await _confirm(
    context,
    title: l10n.deleteVersionTitle(p.posix.withoutExtension(version.fileName)),
    content: l10n.deleteVersionHint,
    action: l10n.deleteVersion,
  );
  if (confirmed != true || !context.mounted) return;
  final done = await runProjectChange(
    context,
    ref,
    () => ref.read(libraryServiceProvider).trashVersion(title, version),
  );
  if (done) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.versionDeleted)));
  }
}

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
    final confirmed = await _confirm(
      context,
      title: l10n.purgeTitle(files.length),
      content: l10n.purgeHint,
      action: l10n.deleteForever,
    );
    if (confirmed != true || !context.mounted) return;
    final service = ref.read(libraryServiceProvider);
    final List<StorageEntry> unused;
    try {
      unused = await service.purge(title, [for (final f in files) f.path]);
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mediaUnreadable)));
      return;
    } on Object catch (e) {
      _fail(messenger, l10n, e);
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
      _fail(messenger, l10n, e);
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
