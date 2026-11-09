import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'providers.dart';
import 'reaper.dart';

/// Search, filters, display mode and saved views, kept between sessions
/// (SPEC §5.2).
class NavigationNotifier extends Notifier<NavigationSettings> {
  Timer? _saveQuery;

  @override
  NavigationSettings build() {
    ref.onDispose(() => _saveQuery?.cancel());
    return ref.read(settingsProvider).navigation;
  }

  /// Sets the search query; saved once typing pauses.
  void setQuery(String query) {
    if (query == state.query) return;
    state = state.copyWith(query: query);
    _saveQuery?.cancel();
    _saveQuery = Timer(const Duration(milliseconds: 600), _save);
  }

  void setFilter(TitleFilter filter) => _set(state.copyWith(filter: filter));

  void setDisplayMode(DisplayMode mode) =>
      _set(state.copyWith(displayMode: mode));

  /// Saves the current search and filters as [name], replacing a view of
  /// the same name.
  void saveView(String name) => _set(
    state.copyWith(
      savedViews: [
        ...state.savedViews.where((v) => v.name != name),
        SavedView(name: name, query: state.query, filter: state.filter),
      ],
    ),
  );

  void deleteView(String name) => _set(
    state.copyWith(
      savedViews: [...state.savedViews.where((v) => v.name != name)],
    ),
  );

  /// Docks the overview below the titles, or lets it float over them.
  void setOverviewPinned(bool pinned) =>
      _set(state.copyWith(overviewPinned: pinned));

  void applyView(SavedView view) =>
      _set(state.copyWith(query: view.query, filter: view.filter));

  void _set(NavigationSettings value) {
    state = value;
    _save();
  }

  void _save() {
    _saveQuery?.cancel();
    final navigation = state;
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .change((s) => s.copyWith(navigation: navigation)),
    );
  }
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavigationSettings>(
      NavigationNotifier.new,
    );

/// Plugins known to REAPER on this machine; null when the caches cannot be
/// read.
final pluginCacheProvider = FutureProvider<PluginCache?>((ref) async {
  final resources = ref.watch(reaperResourcesProvider);
  if (resources == null) return null;
  try {
    return await PluginCache.load(resources);
  } on Object {
    return null;
  }
});

/// Plugins of [version] known to be missing on this machine.
List<PluginRef> missingPlugins(PluginCache cache, Version version) => [
  for (final p in version.plugins)
    if (cache.status(
          RppPlugin(kind: p.kind, name: p.name, identifier: p.identifier),
        ) ==
        PluginStatus.missing)
      p,
];

/// Titles having a version that uses a missing plugin (empty until the
/// plugin caches are read).
final titlesMissingPluginsProvider = Provider<Set<NodeId>>((ref) {
  final cache = ref.watch(pluginCacheProvider).value;
  if (cache == null) return const {};
  return {
    for (final t in ref.watch(titlesProvider))
      if (t.versions.any((v) => missingPlugins(cache, v).isNotEmpty)) t.id,
  };
});

/// Display name of a version owner: the local member's name, else a short
/// id (members arrive with the collab mode).
String ownerName(LocalIdentity identity, MemberId owner) =>
    owner == identity.memberId
    ? identity.displayName
    : owner.substring(0, owner.length < 8 ? owner.length : 8);

/// Tempo of the latest version that has one; null when unknown.
int? tempoOf(Title t) {
  final dated = [...t.versions.where((v) => v.tempo != null)]
    ..sort((a, b) => b.modified.compareTo(a.modified));
  return dated.firstOrNull?.tempo?.round();
}

/// Modification date of the latest version; null without versions.
DateTime? lastModified(Title t) => t.versions.isEmpty
    ? null
    : t.versions.map((v) => v.modified).reduce((a, b) => a.isAfter(b) ? a : b);

/// Values a filter can take, from all the titles (SPEC §5.2).
typedef FilterOptions = ({
  /// Non-leaf layout levels and their values, by tag key.
  List<({LayoutLevel level, List<String> values})> tags,
  List<LibraryEntry> libraries,
  List<LibraryMode> modes,
  List<String> statuses,
  List<MemberId> owners,
  bool missingPlugins,
  bool toAdopt,
});

final filterOptionsProvider = Provider<FilterOptions>((ref) {
  final titles = ref.watch(titlesProvider);
  final libraries = ref.watch(indexedLibrariesProvider);
  final levels = <String, LayoutLevel>{};
  for (final l in libraries.values) {
    // Free tree libraries have no layout, hence no level filters.
    final layoutLevels = l.layout?.levels ?? const <LayoutLevel>[];
    if (layoutLevels.isEmpty) continue;
    for (final level in layoutLevels.take(layoutLevels.length - 1)) {
      levels.putIfAbsent(level.key, () => level);
    }
  }
  final usedLibraries = {for (final t in titles) t.libraryId};
  final statuses = {for (final t in titles) ?t.status};
  return (
    tags: [
      for (final level in levels.values)
        (
          level: level,
          values: ({for (final t in titles) ?t.tags[level.key]}.toList()
            ..sort(_compareText)),
        ),
    ],
    libraries: [
      for (final e in ref.watch(settingsProvider.select((s) => s.libraries)))
        if (usedLibraries.contains(e.id)) e,
    ],
    modes: [
      for (final m in LibraryMode.values)
        if (usedLibraries.any((id) => libraries[id]?.mode == m)) m,
    ],
    statuses: [
      ...Title.defaultStatuses.where(statuses.contains),
      ...(statuses.difference(Title.defaultStatuses.toSet()).toList()..sort()),
    ],
    owners: ({
      for (final t in titles)
        for (final v in t.versions) ?v.metadata?.owner,
    }.toList()..sort()),
    missingPlugins: ref.watch(titlesMissingPluginsProvider).isNotEmpty,
    toAdopt: ref.watch(toAdoptProvider).isNotEmpty,
  );
});

int _compareText(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

/// Whether [t] passes [filter].
bool matchesFilter(
  TitleFilter filter,
  Title t, {
  required Library? library,
  required bool missingPlugins,
  required bool toAdopt,
}) =>
    filter.tags.entries.every(
      (e) => e.value.isEmpty || e.value.contains(t.tags[e.key]),
    ) &&
    (filter.libraries.isEmpty || filter.libraries.contains(t.libraryId)) &&
    (filter.modes.isEmpty || filter.modes.contains(library?.mode)) &&
    (filter.statuses.isEmpty || filter.statuses.contains(t.status)) &&
    (filter.owners.isEmpty ||
        t.versions.any((v) => filter.owners.contains(v.metadata?.owner))) &&
    (!filter.missingPlugins || missingPlugins) &&
    (!filter.toAdopt || toAdopt);

final _titleSearchProvider = Provider<TitleSearch>((ref) {
  final identity = ref.watch(settingsProvider.select((s) => s.identity));
  return TitleSearch(
    ref.watch(titlesProvider),
    memberNames: {identity.memberId: identity.displayName},
  );
});

/// Titles matching the search query and the filters, best first.
final visibleTitlesProvider = Provider<List<Title>>((ref) {
  final navigation = ref.watch(navigationProvider);
  final libraries = ref.watch(indexedLibrariesProvider);
  final missing = ref.watch(titlesMissingPluginsProvider);
  final toAdopt = {for (final (t, _) in ref.watch(toAdoptProvider)) t.id};
  return [
    for (final t in ref.watch(_titleSearchProvider).search(navigation.query))
      if (matchesFilter(
        navigation.filter,
        t,
        library: libraries[t.libraryId],
        missingPlugins: missing.contains(t.id),
        toAdopt: toAdopt.contains(t.id),
      ))
        t,
  ];
});

/// Issues of all libraries ("To sort", SPEC §5.2, §5.8 step 3): `.RPP`
/// files and folders outside the layout, duplicated version identifiers,
/// unreadable files and orphan node files (#54); sorted by library, kind
/// then path.
final issuesProvider = Provider<List<LibraryIssue>>((ref) {
  ref.watch(indexRevisionProvider);
  return ref.watch(localIndexProvider).issues();
});

/// Versions without metadata in layout libraries ("To adopt", SPEC §4.2).
final toAdoptProvider = Provider<List<(Title, Version)>>((ref) {
  final libraries = ref.watch(indexedLibrariesProvider);
  return [
    for (final t in ref.watch(titlesProvider))
      if (libraries[t.libraryId]?.isFreeTree == false)
        for (final v in t.versions)
          if (!v.isAdopted) (t, v),
  ];
});

/// Versions sharing a version id (Save As duplicates, SPEC §4.2).
final duplicatesProvider = Provider<Map<VersionId, List<(Title, Version)>>>(
  (ref) => duplicateVersions(ref.watch(titlesProvider)),
);

/// Title shown in the overview (SPEC §5.2); null when closed.
class OverviewNotifier extends Notifier<NodeId?> {
  @override
  NodeId? build() => null;

  /// Shows the overview of [title], or closes it if it already shows it.
  void toggle(NodeId title) => state = state == title ? null : title;

  void show(NodeId title) => state = title;

  void close() => state = null;
}

final overviewProvider = NotifierProvider<OverviewNotifier, NodeId?>(
  OverviewNotifier.new,
);
