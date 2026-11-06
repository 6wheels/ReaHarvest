import 'ids.dart';

/// Sharing level of a library (SPEC §3.0).
enum LibraryMode { local, cloud, collab }

/// Collab store implementation selected in `_library.json`.
enum CollabStoreKind { journal, pocketbase }

/// One layout level: a folder level bound to a language-independent tag key
/// (a token, written `<key>`, SPEC §3.1).
final class LayoutLevel {
  const LayoutLevel(this.key, {this.labels = const {}});

  /// Technical tag key, in English (e.g. `artist`).
  final String key;

  /// Translations of a custom key (language code -> label). Empty for the
  /// keys of the provided templates, which the application translates.
  final Map<String, String> labels;

  /// Label of a custom key in [languageCode], falling back to English, then
  /// to the key itself.
  String label(String languageCode) =>
      labels[languageCode] ?? labels['en'] ?? key;

  Map<String, Object?> toJson() => {
    'key': key,
    if (labels.isNotEmpty) 'labels': labels,
  };

  static LayoutLevel fromJson(Map<String, Object?> json) => LayoutLevel(
    json['key'] as String,
    labels: (json['labels'] as Map?)?.cast() ?? const {},
  );
}

/// Ordered folder levels of a library; the last one is the leaf (title).
final class Layout {
  Layout(
    this.levels, {
    Map<String, String>? renderMetadata,
    this.frozen = false,
  }) : renderMetadata =
           renderMetadata ?? {for (final l in levels) l.key: l.key} {
    if (levels.isEmpty || levels.length > maxLevels) {
      throw ArgumentError('A layout has 1 to $maxLevels levels');
    }
    final keys = levels.map((l) => l.key).toSet();
    if (keys.length != levels.length || keys.any((k) => k.isEmpty)) {
      throw ArgumentError('Layout level keys must be unique and non-empty');
    }
  }

  static const maxLevels = 4;

  /// Reserved folder name for unassigned items on intermediate levels.
  static const unassigned = '_Unassigned';

  static Layout classic() => Layout(const [
    LayoutLevel('artist'),
    LayoutLevel('album'),
    LayoutLevel('title'),
  ]);

  static Layout projectOriented() => Layout(const [
    LayoutLevel('artist'),
    LayoutLevel('title'),
  ]);

  static Layout film() => Layout(const [
    LayoutLevel('project'),
    LayoutLevel('chapter'),
    LayoutLevel('scene'),
  ]);

  final List<LayoutLevel> levels;

  /// Tag key -> render metadata field (e.g. `artist` -> `artist`).
  final Map<String, String> renderMetadata;

  /// Frozen once the first title exists; changing it is a migration.
  final bool frozen;

  LayoutLevel get leaf => levels.last;

  Layout freeze() =>
      Layout(levels, renderMetadata: renderMetadata, frozen: true);

  /// Tags of a title located at [folders] (relative to the library root),
  /// or null if the path does not match the layout depth.
  Map<String, String>? tagsOf(List<String> folders) {
    if (folders.length != levels.length) return null;
    return {for (var i = 0; i < levels.length; i++) levels[i].key: folders[i]};
  }

  Map<String, Object?> toJson() => {
    'levels': [for (final l in levels) l.toJson()],
    'renderMetadata': renderMetadata,
    'frozen': frozen,
  };

  static Layout fromJson(Map<String, Object?> json) => Layout(
    [
      for (final l in json['levels'] as List)
        LayoutLevel.fromJson((l as Map).cast()),
    ],
    renderMetadata: (json['renderMetadata'] as Map?)?.cast(),
    frozen: json['frozen'] as bool? ?? false,
  );
}

/// Collab settings of a library (collab mode only).
final class CollabSettings {
  const CollabSettings({
    required this.groupId,
    this.store = CollabStoreKind.journal,
    this.backendUrl,
  });

  final GroupId groupId;
  final CollabStoreKind store;

  /// Backend URL (PocketBase store).
  final String? backendUrl;

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'store': store.name,
    'backendUrl': ?backendUrl,
  };

  static CollabSettings fromJson(Map<String, Object?> json) => CollabSettings(
    groupId: GroupId(json['groupId'] as String),
    store: CollabStoreKind.values.byName(json['store'] as String),
    backendUrl: json['backendUrl'] as String?,
  );
}

/// Library description, as stored in `_library.json` (SPEC §6.5).
final class Library {
  Library({
    required this.id,
    required this.mode,
    required this.layout,
    this.collab,
  }) {
    if (layout == null && mode != LibraryMode.local) {
      throw ArgumentError('Free tree is only allowed in local mode');
    }
    if ((mode == LibraryMode.collab) != (collab != null)) {
      throw ArgumentError('Collab settings are required in collab mode only');
    }
  }

  static const schemaVersion = 1;

  final LibraryId id;
  final LibraryMode mode;

  /// Folder layout; null means free tree (local mode only, SPEC §3.3).
  final Layout? layout;

  final CollabSettings? collab;

  bool get isFreeTree => layout == null;

  Map<String, Object?> toJson() => {
    'libraryId': id,
    'schemaVersion': schemaVersion,
    'mode': mode.name,
    'layout': layout?.toJson(),
    'collab': ?collab?.toJson(),
  };

  static Library fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported _library.json schema: $version');
    }
    final layout = json['layout'] as Map?;
    final collab = json['collab'] as Map?;
    return Library(
      id: LibraryId(json['libraryId'] as String),
      mode: LibraryMode.values.byName(json['mode'] as String),
      layout: layout == null ? null : Layout.fromJson(layout.cast()),
      collab: collab == null ? null : CollabSettings.fromJson(collab.cast()),
    );
  }
}
