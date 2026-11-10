import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Title;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'aurora.dart';
import 'labels.dart';
import 'status_trail.dart';
import 'version_actions.dart';
import 'widgets.dart';

/// Route of a page shown over the library (title detail, "To sort").
PageRouteBuilder<void> overLibraryRoute(WidgetBuilder builder) =>
    PageRouteBuilder<void>(
      transitionDuration: Motion.medium,
      reverseTransitionDuration: Motion.medium,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, animation, _, child) {
        final t = CurvedAnimation(parent: animation, curve: Motion.curve);
        return FadeTransition(
          opacity: t,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(t),
            child: child,
          ),
        );
      },
    );

/// Goes back from a page over the library with Escape or the mouse back
/// button.
class BackNavigation extends StatelessWidget {
  const BackNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    return Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) back();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): back},
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

/// Opens the detail page of title [id] over the library.
Future<void> openTitleDetail(BuildContext context, NodeId id) =>
    Navigator.of(context).push(overLibraryRoute((_) => TitleDetailPage(id)));

/// Problems of a version, shown in the overview and the detail.
typedef VersionAlerts = ({
  /// Plugins known to be missing on this machine.
  List<PluginRef> missing,

  /// Other versions sharing its version id (Save As copies).
  List<(Title, Version)> duplicates,

  /// Version without metadata in a layout library.
  bool notAdopted,
});

VersionAlerts versionAlerts(WidgetRef ref, Title title, Version version) {
  final freeTree =
      ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ?? true;
  final cache = ref.watch(pluginCacheProvider).value;
  final m = version.metadata;
  return (
    missing: cache == null
        ? const <PluginRef>[]
        : missingPlugins(cache, version),
    duplicates: m == null
        ? const <(Title, Version)>[]
        : [
            for (final d in ref.watch(duplicatesProvider)[m.id] ?? const [])
              if (d.$2 != version) d,
          ],
    notAdopted: !freeTree && m == null,
  );
}

/// Versions of [title], most recently modified first.
List<Version> recentVersions(Title title) =>
    [...title.versions]..sort((a, b) => b.modified.compareTo(a.modified));

/// Display name of the library of [title].
String? libraryName(WidgetRef ref, Title title) => ref
    .watch(settingsProvider.select((s) => s.libraries))
    .where((l) => l.id == title.libraryId)
    .firstOrNull
    ?.displayName;

/// Tag values and library of [title], joined.
String titleSubtitle(WidgetRef ref, AppLocalizations l10n, Title title) => [
  for (final v in parentTags(title)) tagValueLabel(l10n, v),
  ?libraryName(ref, title),
].join(' · ');

/// Label, owner, date and tempo of [version], joined.
String versionDetails(WidgetRef ref, AppLocalizations l10n, Version version) {
  final owners = ref.watch(ownerNamesProvider);
  final m = version.metadata;
  return [
    if (m != null && m.label.isNotEmpty) m.label,
    if (m != null) ownerName(owners, m.owner),
    shortDate(l10n, version.modified),
    if (version.tempo case final bpm?) l10n.bpm(bpm.round()),
  ].join(' · ');
}

/// Project length as `m:ss`, or `h:mm:ss` from one hour.
String formatLength(double seconds) {
  final d = Duration(milliseconds: (seconds * 1000).round());
  String two(int n) => n.toString().padLeft(2, '0');
  final s = two(d.inSeconds % 60);
  return d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:$s'
      : '${d.inMinutes}:$s';
}

/// Full detail of a title, over the library (SPEC §5.2): its versions on
/// the left, the selected version on the right. Back with the back
/// button, Escape or the mouse back button.
class TitleDetailPage extends ConsumerStatefulWidget {
  const TitleDetailPage(this.id, {super.key});

  final NodeId id;

  @override
  ConsumerState<TitleDetailPage> createState() => _TitleDetailPageState();
}

class _TitleDetailPageState extends ConsumerState<TitleDetailPage> {
  /// File name of the selected version; the latest one when null.
  String? _selected;

  /// Trash tab shown instead of the versions.
  var _trash = false;

  void _select(String fileName) => setState(() => _selected = fileName);

  Future<void> _newVersion(Title title, Version? selected) async {
    final name = await showNewVersionDialog(context, title, selected);
    if (name != null) _select(name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = ref
        .watch(titlesProvider)
        .where((t) => t.id == widget.id)
        .firstOrNull;
    final versions = title == null ? const <Version>[] : recentVersions(title);
    final selected =
        versions.where((v) => v.fileName == _selected).firstOrNull ??
        versions.firstOrNull;
    final freeTree =
        title == null ||
        (ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ??
            true);
    final l10n = AppLocalizations.of(context);
    return BackNavigation(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(title, selected),
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m),
                child: Row(
                  children: [
                    _Tab(
                      l10n.versions,
                      selected: !_trash,
                      onTap: () => setState(() => _trash = false),
                    ),
                    _Tab(
                      l10n.trash,
                      selected: _trash,
                      onTap: () => setState(() => _trash = true),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, color: c.border),
            if (title != null && _trash) Expanded(child: TrashView(title)),
            if (title != null && !_trash)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: ListView(
                        padding: const EdgeInsets.all(Space.m),
                        children: [
                          if (!freeTree)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.s),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.add_rounded, size: 18),
                                onPressed: () => _newVersion(title, selected),
                                label: Text(l10n.newVersion),
                              ),
                            ),
                          for (final v in versions)
                            _VersionItem(
                              title,
                              v,
                              selected: v == selected,
                              onTap: () => _select(v.fileName),
                            ),
                        ],
                      ),
                    ),
                    VerticalDivider(width: 1, color: c.border),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Motion.fast,
                        child: selected == null
                            ? const SizedBox()
                            : _VersionPane(
                                title,
                                selected,
                                onSelect: _select,
                                onNewVersion: () =>
                                    _newVersion(title, selected),
                                key: ValueKey(selected.fileName),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tab of the title detail (versions, trash).
class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.m,
          vertical: Space.s,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? c.accent : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: selected ? null : c.muted),
        ),
      ),
    );
  }
}

/// Title name with its first parent tag (e.g. the artist) on the same
/// line, the other tags (e.g. the album) and the library below; stats of
/// the selected [version] on the right; status trail across the width.
class _Header extends ConsumerWidget {
  const _Header(this.title, this.version);

  final Title? title;
  final Version? version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final t = title;
    final tags = t == null
        ? const <String>[]
        : [for (final v in parentTags(t)) tagValueLabel(l10n, v)];
    final below = t == null
        ? ''
        : [...tags.skip(1), ?libraryName(ref, t)].join(' · ');
    final v = version;
    final toAdopt = t == null ? 0 : ref.watch(toAdoptCountsProvider)[t.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xl, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.back,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              if (t != null) ...[
                const SizedBox(width: Space.s),
                SizedBox.square(
                  dimension: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      painter: AuroraPainter(AuroraPalette.of(t.id), phase: 0),
                    ),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: titleName(t),
                              style: text.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (tags.isNotEmpty)
                              TextSpan(
                                text: '   ${tags.first}',
                                style: text.titleMedium?.copyWith(
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (below.isNotEmpty)
                        Text(
                          below,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: c.muted),
                        ),
                      if (toAdopt > 0)
                        Row(
                          children: [
                            Icon(
                              Icons.help_outline_rounded,
                              size: 16,
                              color: c.muted,
                            ),
                            const SizedBox(width: Space.xs),
                            Text(
                              l10n.notAdoptedCount(toAdopt),
                              style: text.bodySmall?.copyWith(color: c.muted),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (v != null) ...[
                  const SizedBox(width: Space.l),
                  _Stat(
                    l10n.statLength,
                    v.length == null ? null : formatLength(v.length!),
                  ),
                  _Stat('BPM', v.tempo?.round().toString()),
                  _Stat(l10n.statTracks, v.trackCount?.toString()),
                  _Stat(l10n.statItems, v.itemCount?.toString()),
                ],
              ],
            ],
          ),
          if (t != null) ...[
            const SizedBox(height: Space.m),
            Padding(
              padding: const EdgeInsets.only(left: 48 + Space.s),
              child: StatusTrail(t.status, large: true),
            ),
          ],
        ],
      ),
    );
  }
}

/// Figure of the header stats; a dash when unknown.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value ?? '—',
            style: text.titleLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: context.colors.muted,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionItem extends ConsumerWidget {
  const _VersionItem(
    this.title,
    this.version, {
    required this.selected,
    required this.onTap,
  });

  final Title title;
  final Version version;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final alerts = versionAlerts(ref, title, version);
    final owners = ref.watch(ownerNamesProvider);
    final m = version.metadata;
    final status = title.statusOf(version);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.m,
              vertical: Space.s,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.posix.withoutExtension(version.fileName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          shortDate(l10n, version.modified),
                          if (m != null && m.label.isNotEmpty) m.label,
                          if (m != null) ownerName(owners, m.owner),
                          if (status != null) statusLabel(l10n, status),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                if (alerts.missing.isNotEmpty || alerts.duplicates.isNotEmpty)
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: warningColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adoption of a version without metadata: label and owner (chosen among
/// the declared members, if any, else the local member), written into the
/// project (SPEC §4.2).
class _Adopt extends ConsumerStatefulWidget {
  const _Adopt(this.title, this.version);

  final Title title;
  final Version version;

  @override
  ConsumerState<_Adopt> createState() => _AdoptState();
}

class _AdoptState extends ConsumerState<_Adopt> {
  final _label = TextEditingController();

  /// Owner picked among the declared members; null for the default.
  MemberId? _picked;

  List<Member> get _members =>
      ref.watch(indexedLibrariesProvider)[widget.title.libraryId]?.members ??
      const [];

  /// Owner written on adoption: the picked member, else the local member if
  /// declared (or none is), else the first declared member.
  MemberId get _owner {
    final local = ref.watch(
      settingsProvider.select((s) => s.identity.memberId),
    );
    final members = _members;
    return _picked ??
        (members.isEmpty || members.any((m) => m.id == local)
            ? local
            : members.first.id);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _adopt() => runProjectChange(
    context,
    ref,
    () => ref
        .read(libraryServiceProvider)
        .adopt(widget.title, widget.version, _label.text, owner: _owner),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final members = _members;
    final owner = _owner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.toAdoptHint,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.colors.muted),
        ),
        const SizedBox(height: Space.s),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _label,
                  onSubmitted: (_) => _adopt(),
                  decoration: InputDecoration(
                    labelText: l10n.versionLabel,
                    helperText: members.isEmpty
                        ? l10n.filterValue(
                            l10n.filterOwner,
                            ownerName(ref.watch(ownerNamesProvider), owner),
                          )
                        : null,
                    isDense: true,
                  ),
                ),
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(width: Space.s),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<MemberId>(
                    initialValue: owner,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: l10n.filterOwner,
                      isDense: true,
                    ),
                    items: [
                      for (final m in members)
                        DropdownMenuItem(value: m.id, child: Text(m.name)),
                    ],
                    onChanged: (id) => setState(() => _picked = id),
                  ),
                ),
              ],
              const SizedBox(width: Space.s),
              FilledButton(onPressed: _adopt, child: Text(l10n.adopt)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Selected version: details, actions, missing plugins, duplicates and
/// history.
class _VersionPane extends ConsumerWidget {
  const _VersionPane(
    this.title,
    this.version, {
    super.key,
    required this.onSelect,
    required this.onNewVersion,
  });

  final Title title;
  final Version version;

  /// Selects the version of this file name (after a rename).
  final ValueChanged<String> onSelect;

  /// Opens the new version dialog, this version offered as source.
  final VoidCallback onNewVersion;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final name = await showEditVersionDialog(context, ref, title, version);
    if (name != null) onSelect(name);
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(libraryServiceProvider).backup(title, version);
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupCreated)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.actionFailed('$error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final alerts = versionAlerts(ref, title, version);
    final status = title.statusOf(version);
    final m = version.metadata;
    final freeTree =
        ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ??
        true;
    final hasHistory = !freeTree && m != null;
    return ListView(
      padding: const EdgeInsets.all(Space.xl),
      children: [
        Text(
          p.posix.withoutExtension(version.fileName),
          style: text.titleLarge,
        ),
        const SizedBox(height: 2),
        Text(
          versionDetails(ref, l10n, version),
          style: text.bodyMedium?.copyWith(color: c.muted),
        ),
        if (status != null ||
            alerts.notAdopted ||
            alerts.missing.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              if (status != null)
                Pill(statusLabel(l10n, status), color: c.accent),
              if (alerts.notAdopted) Pill(l10n.notAdopted, color: c.muted),
              if (alerts.missing.isNotEmpty)
                Pill(
                  l10n.missingPluginCount(alerts.missing.length),
                  color: warningColor,
                ),
            ],
          ),
        ],
        if (alerts.notAdopted) ...[
          const SizedBox(height: Space.l),
          _Adopt(title, version),
        ],
        const SizedBox(height: Space.m),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              onPressed: () =>
                  openVersionInReaper(context, ref, title, version),
              label: Text(l10n.openInReaper),
            ),
            if (hasHistory)
              OutlinedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                onPressed: () => _backup(context, ref),
                label: Text(l10n.createBackup),
              ),
            MenuAnchor(
              menuChildren: [
                if (!freeTree) ...[
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.copy_rounded),
                    onPressed: onNewVersion,
                    child: Text(l10n.duplicateVersion),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, ref),
                    child: Text(l10n.editVersion),
                  ),
                ],
                SubmenuButton(
                  leadingIcon: const Icon(Icons.flag_outlined),
                  menuChildren: [
                    for (final s in {...Title.defaultStatuses, ?status})
                      MenuItemButton(
                        trailingIcon: s == status
                            ? const Icon(Icons.check_rounded, size: 18)
                            : null,
                        onPressed: () => setVersionStatusFromUi(
                          context,
                          ref,
                          title,
                          version,
                          s,
                        ),
                        child: Text(statusLabel(l10n, s)),
                      ),
                    MenuItemButton(
                      onPressed: status == null
                          ? null
                          : () => setVersionStatusFromUi(
                              context,
                              ref,
                              title,
                              version,
                              null,
                            ),
                      child: Text(l10n.noStatus),
                    ),
                  ],
                  child: Text(l10n.changeStatus),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () =>
                      deleteVersionFromUi(context, ref, title, version),
                  child: Text(l10n.deleteVersion),
                ),
              ],
              builder: (context, controller, _) => IconButton(
                tooltip: l10n.moreActions,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ),
          ],
        ),
        if (alerts.missing.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel(l10n.filterMissingPlugins),
          const SizedBox(height: Space.xs),
          for (final plugin in alerts.missing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.extension_off_outlined,
                    size: 16,
                    color: warningColor,
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(plugin.name, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
        if (alerts.duplicates.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          Text(
            l10n.duplicateOf(
              [
                for (final (t, v) in alerts.duplicates)
                  t.id == title.id
                      ? v.fileName
                      : '${titleName(t)}/${v.fileName}',
              ].join(', '),
            ),
            style: text.bodyMedium?.copyWith(color: warningColor),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
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
          ),
        ],
        if (hasHistory) ...[
          const SizedBox(height: Space.l),
          SectionLabel(l10n.history),
          const SizedBox(height: Space.xs),
          _History(title, version, m.id),
        ],
      ],
    );
  }
}

/// Backup points of a version: open and restore (SPEC §5.4).
class _History extends ConsumerWidget {
  const _History(this.title, this.version, this.id);

  final Title title;
  final Version version;
  final VersionId id;

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    Backup backup,
    String date,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreTitle),
        content: Text(l10n.restoreHint(date)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final done = await runProjectChange(
      context,
      ref,
      () => ref.read(libraryServiceProvider).restore(title, version, backup),
    );
    if (done) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestored)));
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Backup backup) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await ref
          .read(libraryServiceProvider)
          .openBackup(title, backup);
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.reaperNotFound)));
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.actionFailed('$error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final backups =
        ref.watch(historyProvider(title.id)).value?[id] ?? const <Backup>[];
    final format = DateFormat.yMMMd(l10n.localeName).add_Hm();
    if (backups.isEmpty) {
      return Text(
        l10n.noBackups,
        style: text.bodyMedium?.copyWith(color: c.muted),
      );
    }
    return Column(
      children: [
        for (final b in backups)
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 16),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(format.format(b.created), style: text.bodyMedium),
              ),
              IconButton(
                tooltip: l10n.openInReaper,
                onPressed: () => _open(context, ref, b),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
              ),
              TextButton(
                onPressed: () =>
                    _restore(context, ref, b, format.format(b.created)),
                child: Text(l10n.restore),
              ),
            ],
          ),
      ],
    );
  }
}
