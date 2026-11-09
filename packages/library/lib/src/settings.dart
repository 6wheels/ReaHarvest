import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Local member identity, created on first launch and used in all modes as
/// version owner (SPEC §5.1).
final class LocalIdentity {
  const LocalIdentity(this.memberId, this.displayName);

  final MemberId memberId;
  final String displayName;

  LocalIdentity withDisplayName(String name) => LocalIdentity(memberId, name);

  Map<String, Object?> toJson() => {
    'memberId': memberId,
    'displayName': displayName,
  };

  static LocalIdentity fromJson(Map<String, Object?> json) => LocalIdentity(
    MemberId(json['memberId'] as String),
    json['displayName'] as String,
  );
}

/// A library configured on this machine (SPEC §5.1). Mode and layout live in
/// the library's `.library.json`.
final class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.displayName,
    required this.workspaceRoot,
    this.repositoryRoot,
    this.templatesFolder,
  });

  final LibraryId id;
  final String displayName;
  final String workspaceRoot;

  /// Repository root (cloud and collab modes only).
  final String? repositoryRoot;

  /// Templates folder specific to this library.
  final String? templatesFolder;

  /// Folder holding `.library.json`.
  String get libraryRoot => repositoryRoot ?? workspaceRoot;

  List<String> get roots => [workspaceRoot, ?repositoryRoot];

  Map<String, Object?> toJson() => {
    'libraryId': id,
    'displayName': displayName,
    'workspaceRoot': workspaceRoot,
    'repositoryRoot': ?repositoryRoot,
    'templatesFolder': ?templatesFolder,
  };

  static LibraryEntry fromJson(Map<String, Object?> json) => LibraryEntry(
    id: LibraryId(json['libraryId'] as String),
    displayName: json['displayName'] as String,
    workspaceRoot: json['workspaceRoot'] as String,
    repositoryRoot: json['repositoryRoot'] as String?,
    templatesFolder: json['templatesFolder'] as String?,
  );
}

/// How the titles are displayed (SPEC §5.2).
enum DisplayMode { cards, list, tree }

/// Combinable title filters (SPEC §5.2). An empty set does not filter.
final class TitleFilter {
  const TitleFilter({
    this.tags = const {},
    this.libraries = const {},
    this.modes = const {},
    this.statuses = const {},
    this.owners = const {},
    this.missingPlugins = false,
    this.toAdopt = false,
  });

  /// Accepted values, by tag key (e.g. `artist`).
  final Map<String, Set<String>> tags;
  final Set<LibraryId> libraries;
  final Set<LibraryMode> modes;

  /// Accepted title status keys.
  final Set<String> statuses;

  /// Accepted version owners: a title matches if one of its versions does.
  final Set<MemberId> owners;

  /// Only titles with a version using a plugin missing on this machine.
  final bool missingPlugins;

  /// Only titles with a version to adopt (no metadata, SPEC §4.2).
  final bool toAdopt;

  bool get isEmpty =>
      tags.values.every((v) => v.isEmpty) &&
      libraries.isEmpty &&
      modes.isEmpty &&
      statuses.isEmpty &&
      owners.isEmpty &&
      !missingPlugins &&
      !toAdopt;

  /// Copy accepting [values] for the tag [key] (empty: no tag filter).
  TitleFilter withTag(String key, Set<String> values) => copyWith(
    tags: {
      for (final e in tags.entries)
        if (e.key != key) e.key: e.value,
      if (values.isNotEmpty) key: values,
    },
  );

  TitleFilter copyWith({
    Map<String, Set<String>>? tags,
    Set<LibraryId>? libraries,
    Set<LibraryMode>? modes,
    Set<String>? statuses,
    Set<MemberId>? owners,
    bool? missingPlugins,
    bool? toAdopt,
  }) => TitleFilter(
    tags: tags ?? this.tags,
    libraries: libraries ?? this.libraries,
    modes: modes ?? this.modes,
    statuses: statuses ?? this.statuses,
    owners: owners ?? this.owners,
    missingPlugins: missingPlugins ?? this.missingPlugins,
    toAdopt: toAdopt ?? this.toAdopt,
  );

  Map<String, Object?> toJson() => {
    if (tags.isNotEmpty)
      'tags': {for (final e in tags.entries) e.key: e.value.toList()},
    if (libraries.isNotEmpty) 'libraries': libraries.toList(),
    if (modes.isNotEmpty) 'modes': [for (final m in modes) m.name],
    if (statuses.isNotEmpty) 'statuses': statuses.toList(),
    if (owners.isNotEmpty) 'owners': owners.toList(),
    if (missingPlugins) 'missingPlugins': true,
    if (toAdopt) 'toAdopt': true,
  };

  static TitleFilter fromJson(Map<String, Object?> json) {
    Set<String> strings(Object? list) => {...?(list as List?)?.cast<String>()};
    final modes = LibraryMode.values.asNameMap();
    return TitleFilter(
      tags: {
        for (final e in ((json['tags'] as Map?) ?? const {}).entries)
          e.key as String: strings(e.value),
      },
      libraries: {for (final id in strings(json['libraries'])) LibraryId(id)},
      modes: {for (final m in strings(json['modes'])) ?modes[m]},
      statuses: strings(json['statuses']),
      owners: {for (final id in strings(json['owners'])) MemberId(id)},
      missingPlugins: json['missingPlugins'] == true,
      toAdopt: json['toAdopt'] == true,
    );
  }
}

/// A named search and filter combination (SPEC §5.2).
final class SavedView {
  const SavedView({
    required this.name,
    this.query = '',
    this.filter = const TitleFilter(),
  });

  final String name;
  final String query;
  final TitleFilter filter;

  Map<String, Object?> toJson() => {
    'name': name,
    'query': query,
    'filter': filter.toJson(),
  };

  static SavedView fromJson(Map<String, Object?> json) => SavedView(
    name: json['name'] as String,
    query: json['query'] as String? ?? '',
    filter: TitleFilter.fromJson((json['filter'] as Map? ?? const {}).cast()),
  );
}

/// Navigation state kept between sessions (SPEC §5.2).
final class NavigationSettings {
  const NavigationSettings({
    this.displayMode = DisplayMode.cards,
    this.query = '',
    this.filter = const TitleFilter(),
    this.savedViews = const [],
    this.overviewPinned = false,
  });

  final DisplayMode displayMode;
  final String query;
  final TitleFilter filter;
  final List<SavedView> savedViews;

  /// Whether the side panel is docked beside the titles rather than
  /// floating over them.
  final bool overviewPinned;

  NavigationSettings copyWith({
    DisplayMode? displayMode,
    String? query,
    TitleFilter? filter,
    List<SavedView>? savedViews,
    bool? overviewPinned,
  }) => NavigationSettings(
    displayMode: displayMode ?? this.displayMode,
    query: query ?? this.query,
    filter: filter ?? this.filter,
    savedViews: savedViews ?? this.savedViews,
    overviewPinned: overviewPinned ?? this.overviewPinned,
  );

  Map<String, Object?> toJson() => {
    'displayMode': displayMode.name,
    'query': query,
    'filter': filter.toJson(),
    'savedViews': [for (final v in savedViews) v.toJson()],
    'overviewPinned': overviewPinned,
  };

  static NavigationSettings fromJson(Map<String, Object?> json) =>
      NavigationSettings(
        displayMode:
            DisplayMode.values.asNameMap()[json['displayMode']] ??
            DisplayMode.cards,
        query: json['query'] as String? ?? '',
        filter: TitleFilter.fromJson(
          (json['filter'] as Map? ?? const {}).cast(),
        ),
        savedViews: [
          for (final v in json['savedViews'] as List? ?? const [])
            SavedView.fromJson((v as Map).cast()),
        ],
        overviewPinned: json['overviewPinned'] as bool? ?? false,
      );
}

/// Light, dark or system theme (SPEC §7.1).
enum ThemePreference { system, light, dark }

/// Application settings (SPEC §5.1). Null paths mean "use the default".
final class AppSettings {
  AppSettings({
    required this.identity,
    List<LibraryEntry> libraries = const [],
    this.reaperExecutable,
    this.reaperResources,
    this.templatesFolder,
    this.theme = ThemePreference.system,
    this.textScale = 1.0,
    this.language = systemLanguage,
    this.navigation = const NavigationSettings(),
  }) : libraries = List.unmodifiable(libraries);

  /// [language] value meaning "follow the system language".
  static const systemLanguage = 'system';

  static const schemaVersion = 1;

  final LocalIdentity identity;
  final List<LibraryEntry> libraries;
  final String? reaperExecutable;
  final String? reaperResources;

  /// Project templates folder (default: `ProjectTemplates` in the REAPER
  /// resource folder).
  final String? templatesFolder;

  final ThemePreference theme;

  /// Font size factor (1.0 = default).
  final double textScale;

  /// UI language code (e.g. `en`), or [systemLanguage].
  final String language;

  final NavigationSettings navigation;

  /// Copy with the given values. Paths are kept when omitted and reset to
  /// the default when passed as null.
  AppSettings copyWith({
    LocalIdentity? identity,
    List<LibraryEntry>? libraries,
    Object? reaperExecutable = _keep,
    Object? reaperResources = _keep,
    Object? templatesFolder = _keep,
    ThemePreference? theme,
    double? textScale,
    String? language,
    NavigationSettings? navigation,
  }) => AppSettings(
    identity: identity ?? this.identity,
    libraries: libraries ?? this.libraries,
    reaperExecutable: _path(reaperExecutable, this.reaperExecutable),
    reaperResources: _path(reaperResources, this.reaperResources),
    templatesFolder: _path(templatesFolder, this.templatesFolder),
    theme: theme ?? this.theme,
    textScale: textScale ?? this.textScale,
    language: language ?? this.language,
    navigation: navigation ?? this.navigation,
  );

  static const _keep = Object();

  static String? _path(Object? value, String? current) =>
      identical(value, _keep) ? current : value as String?;

  /// Adds [entry]. Throws [ArgumentError] if the id is already configured or
  /// if one of its folders is, contains or is inside a folder of another
  /// library (SPEC §3.0).
  AppSettings addLibrary(LibraryEntry entry) {
    if (libraries.any((l) => l.id == entry.id)) {
      throw ArgumentError('Library ${entry.id} is already configured');
    }
    for (final other in libraries) {
      for (final a in entry.roots) {
        for (final b in other.roots) {
          if (p.equals(a, b) || p.isWithin(a, b) || p.isWithin(b, a)) {
            throw ArgumentError(
              'Folder $a overlaps library "${other.displayName}" ($b)',
            );
          }
        }
      }
    }
    return copyWith(libraries: [...libraries, entry]);
  }

  AppSettings removeLibrary(LibraryId id) {
    // A removed library is dropped from the filter and the saved views.
    TitleFilter without(TitleFilter f) =>
        f.copyWith(libraries: {...f.libraries}..remove(id));
    return copyWith(
      libraries: [...libraries.where((l) => l.id != id)],
      navigation: navigation.copyWith(
        filter: without(navigation.filter),
        savedViews: [
          for (final v in navigation.savedViews)
            SavedView(name: v.name, query: v.query, filter: without(v.filter)),
        ],
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'identity': identity.toJson(),
    'libraries': [for (final l in libraries) l.toJson()],
    'reaperExecutable': ?reaperExecutable,
    'reaperResources': ?reaperResources,
    'templatesFolder': ?templatesFolder,
    'theme': theme.name,
    'textScale': textScale,
    'language': language,
    'navigation': navigation.toJson(),
  };

  static AppSettings fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported settings schema: $version');
    }
    return AppSettings(
      identity: LocalIdentity.fromJson((json['identity'] as Map).cast()),
      libraries: [
        for (final l in json['libraries'] as List)
          LibraryEntry.fromJson((l as Map).cast()),
      ],
      reaperExecutable: json['reaperExecutable'] as String?,
      reaperResources: json['reaperResources'] as String?,
      templatesFolder: json['templatesFolder'] as String?,
      theme:
          ThemePreference.values.asNameMap()[json['theme']] ??
          ThemePreference.system,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      language: json['language'] as String? ?? systemLanguage,
      navigation: NavigationSettings.fromJson(
        (json['navigation'] as Map? ?? const {}).cast(),
      ),
    );
  }
}

/// Persists [AppSettings] as JSON in [path] (app support folder, provided by
/// the app).
final class SettingsFile {
  const SettingsFile(this.path);

  final String path;

  /// Loads the settings. On first launch (no file), creates them with a new
  /// local identity named after the OS user, and saves them.
  Future<AppSettings> load() async {
    final file = File(path);
    if (await file.exists()) {
      return AppSettings.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast(),
      );
    }
    final settings = AppSettings(
      identity: LocalIdentity(MemberId.generate(), _osUserName()),
    );
    await save(settings);
    return settings;
  }

  /// Saves [settings] atomically (temporary file, then rename).
  Future<void> save(AppSettings settings) async {
    final text = const JsonEncoder.withIndent('  ').convert(settings.toJson());
    await File(path).parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString('$text\n', flush: true);
    await tmp.rename(path);
  }

  static String _osUserName() {
    final env = Platform.environment;
    final name = env['USERNAME'] ?? env['USER'] ?? '';
    return name.isEmpty ? 'Me' : name;
  }
}
