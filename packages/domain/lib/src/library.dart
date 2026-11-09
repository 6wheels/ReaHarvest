import 'ids.dart';

/// Sharing level of a library (SPEC §3.0).
enum LibraryMode { local, cloud, collab }

/// Collab store implementation selected in `.library.json`.
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
  Layout(this.levels, {Map<String, String>? renderMetadata})
    : renderMetadata =
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

  static Layout projectOriented() =>
      Layout(const [LayoutLevel('artist'), LayoutLevel('title')]);

  static Layout film() => Layout(const [
    LayoutLevel('project'),
    LayoutLevel('chapter'),
    LayoutLevel('scene'),
  ]);

  final List<LayoutLevel> levels;

  /// Tag key -> render metadata field (e.g. `artist` -> `artist`).
  final Map<String, String> renderMetadata;

  LayoutLevel get leaf => levels.last;

  /// Tags of a title located at [folders] (relative to the library root),
  /// or null if the path does not match the layout depth.
  Map<String, String>? tagsOf(List<String> folders) {
    if (folders.length != levels.length) return null;
    return {for (var i = 0; i < levels.length; i++) levels[i].key: folders[i]};
  }

  Map<String, Object?> toJson() => {
    'levels': [for (final l in levels) l.toJson()],
    'renderMetadata': renderMetadata,
  };

  static Layout fromJson(Map<String, Object?> json) => Layout([
    for (final l in json['levels'] as List)
      LayoutLevel.fromJson((l as Map).cast()),
  ], renderMetadata: (json['renderMetadata'] as Map?)?.cast());
}

/// Known value of an intermediate layout level, with the known values of the
/// next level below it (SPEC §3.1). The leaf level is never listed.
final class KnownValue {
  const KnownValue(this.value, [this.children = const []]);

  final String value;
  final List<KnownValue> children;

  @override
  bool operator ==(Object other) =>
      other is KnownValue &&
      other.value == value &&
      _sameValues(other.children, children);

  @override
  int get hashCode => Object.hash(value, Object.hashAll(children));

  @override
  String toString() =>
      children.isEmpty ? value : '$value(${children.join(', ')})';

  Map<String, Object?> toJson() => {
    'value': value,
    if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
  };

  static KnownValue fromJson(Map<String, Object?> json) => KnownValue(
    json['value'] as String,
    knownValuesFromJson(json['children'] as List?),
  );
}

List<KnownValue> knownValuesFromJson(List<Object?>? json) => [
  for (final v in json ?? const []) KnownValue.fromJson((v as Map).cast()),
];

bool _sameValues(List<KnownValue> a, List<KnownValue> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Why known values are incomplete for a layout (SPEC §3.1).
enum KnownValuesProblem {
  /// No value for the first intermediate level.
  empty,

  /// A value of a non-last intermediate level has no child.
  missingChild,

  /// A value is too deep for the layout (below the last intermediate level).
  tooDeep,

  /// Two values with the same name under the same parent.
  duplicate,
}

/// Known values of the intermediate levels of a layout, as a tree.
extension KnownValues on List<KnownValue> {
  /// First problem of these values for a layout of [depth] levels (leaf
  /// included), or null if they are complete. A layout without intermediate
  /// level takes no value.
  KnownValuesProblem? problemFor(int depth) {
    final intermediate = depth - 1;
    if (intermediate == 0) return isEmpty ? null : KnownValuesProblem.tooDeep;
    if (isEmpty) return KnownValuesProblem.empty;
    KnownValuesProblem? check(List<KnownValue> values, int level) {
      if (values.map((v) => v.value).toSet().length != values.length) {
        return KnownValuesProblem.duplicate;
      }
      for (final v in values) {
        final last = level == intermediate;
        if (last && v.children.isNotEmpty) return KnownValuesProblem.tooDeep;
        if (!last && v.children.isEmpty) return KnownValuesProblem.missingChild;
        if (check(v.children, level + 1) case final problem?) return problem;
      }
      return null;
    }

    return check(this, 1);
  }

  /// Whether the folders [path] (one value per level, from the top) are
  /// known; `_Unassigned` is always known, even when not declared (with
  /// no known value below it then).
  bool knows(List<String> path) {
    var values = this;
    for (final name in path) {
      final found = values.where((v) => v.value == name).firstOrNull;
      if (found == null && name != Layout.unassigned) return false;
      values = found?.children ?? const [];
    }
    return true;
  }

  /// Paths (one value per level, from the top) of the known values named
  /// [name], at any level.
  List<List<String>> pathsOf(String name) => [
    for (final v in this) ...[
      if (v.value == name) [v.value],
      for (final rest in v.children.pathsOf(name)) [v.value, ...rest],
    ],
  ];

  /// These values with the folders [path] (one value per level, from the
  /// top) added where missing.
  List<KnownValue> withPath(List<String> path) {
    if (path.isEmpty) return this;
    final [name, ...rest] = path;
    final found = any((v) => v.value == name);
    return [
      for (final v in this)
        v.value == name ? KnownValue(name, v.children.withPath(rest)) : v,
      if (!found) KnownValue(name, const <KnownValue>[].withPath(rest)),
    ];
  }

  List<Map<String, Object?>> toJson() => [for (final v in this) v.toJson()];
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

/// Library description, as stored in `.library.json` (SPEC §6.5).
final class Library {
  Library({
    required this.id,
    required this.mode,
    required this.layout,
    this.collab,
    this.knownValues = const [],
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

  /// Known values of the intermediate levels (SPEC §3.1); empty while not
  /// declared, the scan then recognizes levels by depth only.
  final List<KnownValue> knownValues;

  bool get isFreeTree => layout == null;

  /// This library with [knownValues] replaced.
  Library withKnownValues(List<KnownValue> knownValues) => Library(
    id: id,
    mode: mode,
    layout: layout,
    collab: collab,
    knownValues: knownValues,
  );

  Map<String, Object?> toJson() => {
    'libraryId': id,
    'schemaVersion': schemaVersion,
    'mode': mode.name,
    'layout': layout?.toJson(),
    if (knownValues.isNotEmpty) 'knownValues': knownValues.toJson(),
    'collab': ?collab?.toJson(),
  };

  static Library fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported .library.json schema: $version');
    }
    final layout = json['layout'] as Map?;
    final collab = json['collab'] as Map?;
    return Library(
      id: LibraryId(json['libraryId'] as String),
      mode: LibraryMode.values.byName(json['mode'] as String),
      layout: layout == null ? null : Layout.fromJson(layout.cast()),
      collab: collab == null ? null : CollabSettings.fromJson(collab.cast()),
      knownValues: knownValuesFromJson(json['knownValues'] as List?),
    );
  }
}
