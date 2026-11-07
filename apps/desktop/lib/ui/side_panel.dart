import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../state/reaper.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'layout_labels.dart';

/// Width of the side panel.
const sidePanelWidth = 380.0;

/// Right side panel: title detail, "To sort" or "To adopt" (SPEC §5.2).
class SidePanel extends ConsumerWidget {
  const SidePanel(this.content, {super.key});

  final PanelContent content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final (String heading, Widget body) = switch (content) {
      TitlePanel(:final title) => switch (_find(ref, title)) {
        final t? => (titleName(t), _TitleDetail(t)),
        null => ('', const SizedBox()),
      },
      ToSortPanel() => (l10n.toSort, const _ToSort()),
      ToAdoptPanel() => (l10n.toAdopt, const _ToAdopt()),
    };
    return Material(
      color: c.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.m,
                Space.s,
                Space.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: ref.read(panelProvider.notifier).close,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  static Title? _find(WidgetRef ref, NodeId id) =>
      ref.watch(titlesProvider).where((t) => t.id == id).firstOrNull;
}

class _TitleDetail extends ConsumerWidget {
  const _TitleDetail(this.title);

  final Title title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final libraryName = ref
        .watch(settingsProvider.select((s) => s.libraries))
        .where((l) => l.id == title.libraryId)
        .firstOrNull
        ?.displayName;
    final subtitle = [
      for (final v in parentTags(title)) tagValueLabel(l10n, v),
      ?libraryName,
    ].join(' · ');
    final versions = [...title.versions]
      ..sort((a, b) => b.modified.compareTo(a.modified));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
      children: [
        if (subtitle.isNotEmpty)
          Text(subtitle, style: text.bodyMedium?.copyWith(color: c.muted)),
        if (title.status case final status?) ...[
          const SizedBox(height: Space.s),
          Align(
            alignment: Alignment.centerLeft,
            child: _Badge(statusLabel(l10n, status), color: c.accent),
          ),
        ],
        const SizedBox(height: Space.l),
        _SectionLabel(l10n.versions),
        for (final v in versions) _VersionTile(title, v),
      ],
    );
  }
}

class _VersionTile extends ConsumerWidget {
  const _VersionTile(this.title, this.version);

  final Title title;
  final Version version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final identity = ref.watch(settingsProvider.select((s) => s.identity));
    final freeTree =
        ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ??
        true;
    final cache = ref.watch(pluginCacheProvider).value;
    final missing = cache == null
        ? const <PluginRef>[]
        : missingPlugins(cache, version);
    final m = version.metadata;
    final duplicates = m == null
        ? const <(Title, Version)>[]
        : [
            for (final d in ref.watch(duplicatesProvider)[m.id] ?? const [])
              if (d.$2 != version) d,
          ];
    final status = title.statusOf(version);
    final details = [
      if (m != null && m.label.isNotEmpty) m.label,
      if (m != null) ownerName(identity, m.owner),
      shortDate(l10n, version.modified),
      if (version.tempo case final bpm?) l10n.bpm(bpm.round()),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.posix.withoutExtension(version.fileName),
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(details, style: text.bodySmall?.copyWith(color: c.muted)),
          if (status != null || missing.isNotEmpty || (!freeTree && m == null))
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  if (status != null)
                    _Badge(statusLabel(l10n, status), color: c.accent),
                  if (!freeTree && m == null)
                    _Badge(l10n.notAdopted, color: c.muted),
                  if (missing.isNotEmpty)
                    Tooltip(
                      message: missing.map((p) => p.name).join('\n'),
                      child: _Badge(
                        l10n.missingPluginCount(missing.length),
                        color: _warning,
                      ),
                    ),
                ],
              ),
            ),
          if (duplicates.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text(
              l10n.duplicateOf(
                [
                  for (final (t, v) in duplicates)
                    t.id == title.id
                        ? v.fileName
                        : '${titleName(t)}/${v.fileName}',
                ].join(', '),
              ),
              style: text.bodySmall?.copyWith(color: _warning),
            ),
            TextButton.icon(
              icon: const Icon(Icons.call_split_rounded, size: 18),
              onPressed: () => runProjectChange(
                context,
                ref,
                () => ref
                    .read(libraryServiceProvider)
                    .separateDuplicate(title, version),
              ),
              label: Text(l10n.separateDuplicate),
            ),
          ],
        ],
      ),
    );
  }
}

const _warning = Color(0xFFE5A04D);

class _ToSort extends ConsumerWidget {
  const _ToSort();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final items = ref.watch(toSortProvider);
    final names = {
      for (final l in ref.watch(settingsProvider.select((s) => s.libraries)))
        l.id: l.displayName,
    };
    final multiple = {for (final i in items) i.library}.length > 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
      children: [
        Text(l10n.toSortHint, style: text.bodyMedium?.copyWith(color: c.muted)),
        const SizedBox(height: Space.s),
        for (final item in items)
          _Item(
            title: p.posix.basename(item.path),
            subtitle: [
              if (multiple) ?names[item.library],
              p.posix.dirname(item.path),
            ].where((s) => s != '.').join(' · '),
            child: isProjectFile(item.path)
                ? Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => showSortDialog(
                        context,
                        library: item.library,
                        path: item.path,
                      ),
                      child: Text(l10n.sortAction),
                    ),
                  )
                : Text(
                    l10n.toSortFolderHint,
                    style: text.bodySmall?.copyWith(color: c.muted),
                  ),
          ),
      ],
    );
  }
}

class _ToAdopt extends ConsumerWidget {
  const _ToAdopt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
      children: [
        Text(
          l10n.toAdoptHint,
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.s),
        for (final (t, v) in ref.watch(toAdoptProvider))
          _AdoptItem(
            key: ValueKey('${t.id}/${v.fileName}'),
            title: t,
            version: v,
          ),
      ],
    );
  }
}

class _AdoptItem extends ConsumerStatefulWidget {
  const _AdoptItem({super.key, required this.title, required this.version});

  final Title title;
  final Version version;

  @override
  ConsumerState<_AdoptItem> createState() => _AdoptItemState();
}

class _AdoptItemState extends ConsumerState<_AdoptItem> {
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final owner = ref.watch(
      settingsProvider.select((s) => s.identity.displayName),
    );
    final t = widget.title;
    void adopt() => runProjectChange(
      context,
      ref,
      () => ref
          .read(libraryServiceProvider)
          .adopt(t, widget.version, _label.text),
    );
    return _Item(
      title: p.posix.withoutExtension(widget.version.fileName),
      subtitle: [
        ...parentTags(t),
        titleName(t),
      ].map((v) => tagValueLabel(l10n, v)).join(' · '),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _label,
              onSubmitted: (_) => adopt(),
              decoration: InputDecoration(
                labelText: l10n.versionLabel,
                helperText: l10n.filterValue(l10n.filterOwner, owner),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: Space.s),
          FilledButton(onPressed: adopt, child: Text(l10n.adopt)),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: text.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: Space.s),
          child,
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: context.colors.muted, letterSpacing: 1.2),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}

/// Runs [change] of a project file, after a confirmation when REAPER is
/// running (SPEC §5.7); failures are reported in a snackbar.
Future<bool> runProjectChange(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() change,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (await ref.read(reaperRunningProvider)()) {
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.reaperOpenTitle),
        content: Text(l10n.reaperOpenHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.continueAnyway),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }
  try {
    await change();
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.actionFailed('$error'))),
    );
    return false;
  }
}

/// Guided move of the misplaced project [path] into a title of [library]
/// ("To sort", SPEC §5.2).
Future<void> showSortDialog(
  BuildContext context, {
  required LibraryId library,
  required String path,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SortDialog(library: library, path: path),
);

class _SortDialog extends ConsumerStatefulWidget {
  const _SortDialog({required this.library, required this.path});

  final LibraryId library;
  final String path;

  @override
  ConsumerState<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends ConsumerState<_SortDialog> {
  late final Layout _layout;
  late final List<TextEditingController> _values;

  @override
  void initState() {
    super.initState();
    _layout = ref.read(indexedLibrariesProvider)[widget.library]!.layout!;
    // Prefilled from the current folders, and the file name for the title.
    final folders = p.posix.dirname(widget.path).split('/')
      ..removeWhere((s) => s == '.');
    final levels = _layout.levels.length;
    _values = [
      for (var i = 0; i < levels; i++)
        TextEditingController(
          text: i == levels - 1
              ? p.posix.basenameWithoutExtension(widget.path)
              : (i < folders.length ? folders[i] : Layout.unassigned),
        ),
    ];
  }

  @override
  void dispose() {
    for (final c in _values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => _values.every((c) => isValidFolderName(c.text.trim()));

  /// Existing values of level [i] under the values typed above it.
  List<String> _options(int i) {
    final above = [for (final c in _values.take(i)) c.text.trim()];
    final keys = [for (final l in _layout.levels) l.key];
    return {
      for (final t in ref.read(titlesProvider))
        if (t.libraryId == widget.library &&
            [for (var j = 0; j < i; j++) t.tags[keys[j]]].join('/') ==
                above.join('/'))
          ?t.tags[keys[i]],
    }.toList()..sort();
  }

  Future<void> _move() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    MoveReport? report;
    final done = await runProjectChange(context, ref, () async {
      report = await ref.read(libraryServiceProvider).moveToTitle(
        widget.library,
        widget.path,
        [for (final c in _values) c.text.trim()],
      );
    });
    if (!done) return;
    navigator.pop();
    final r = report!;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          [
            l10n.sortDone,
            if (r.missing.isNotEmpty) l10n.sortMissingMedia(r.missing.length),
            if (r.external.isNotEmpty)
              l10n.sortExternalMedia(r.external.length),
          ].join(' '),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return AlertDialog(
      title: Text(l10n.sortTitle(p.posix.basename(widget.path))),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.sortHint,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: c.muted),
            ),
            for (final (i, level) in _layout.levels.indexed) ...[
              const SizedBox(height: Space.m),
              _LevelField(
                label: layoutLevelLabel(l10n, level),
                controller: _values[i],
                options: () => _options(i),
                error: isValidFolderName(_values[i].text.trim())
                    ? null
                    : l10n.invalidFolderName,
                onChanged: () => setState(() {}),
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
          onPressed: _valid ? _move : null,
          child: Text(l10n.sortConfirm),
        ),
      ],
    );
  }
}

/// Text field of one layout level, with autocompletion on existing values.
class _LevelField extends StatefulWidget {
  const _LevelField({
    required this.label,
    required this.controller,
    required this.options,
    required this.error,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final List<String> Function() options;
  final String? error;
  final VoidCallback onChanged;

  @override
  State<_LevelField> createState() => _LevelFieldState();
}

class _LevelFieldState extends State<_LevelField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsBuilder: (value) {
      final typed = value.text.trim().toLowerCase();
      return widget.options().where((o) => o.toLowerCase().contains(typed));
    },
    onSelected: (_) => widget.onChanged(),
    fieldViewBuilder: (context, controller, focusNode, _) => TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.error,
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: context.colors.raised,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 420),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final o in options)
                ListTile(
                  dense: true,
                  title: Text(o),
                  onTap: () => onSelected(o),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
