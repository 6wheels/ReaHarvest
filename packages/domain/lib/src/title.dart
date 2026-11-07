import 'ids.dart';

/// A title: leaf node folder holding `Media/`, assets and versions.
final class Title {
  const Title({
    required this.id,
    required this.libraryId,
    required this.path,
    required this.tags,
    this.versions = const [],
    this.status,
    this.versionStatuses = const {},
  });

  /// Default status list, from idea to done (SPEC §5.9). The list is
  /// configurable: any non-empty key is accepted.
  static const defaultStatuses = [
    'idea',
    'writing',
    'recording',
    'mixing',
    'done',
  ];

  final NodeId id;
  final LibraryId libraryId;

  /// Folder path relative to the library root, `/`-separated.
  final String path;

  /// Tags derived from the path (e.g. `artist`, `album`, `title`).
  final Map<String, String> tags;

  final List<Version> versions;

  /// Title status key (e.g. `mixing`); null when not set.
  final String? status;

  /// Status of each version, by [Version.key]. May hold keys of versions
  /// that no longer exist.
  final Map<String, String> versionStatuses;

  /// Status of [version]; null when not set.
  String? statusOf(Version version) => versionStatuses[version.key];
}

/// Versions sharing a version id (manual duplicates, e.g. *Save As*,
/// SPEC §4.2), by id. Each list holds at least two versions.
Map<VersionId, List<(Title, Version)>> duplicateVersions(
  Iterable<Title> titles,
) {
  final byId = <VersionId, List<(Title, Version)>>{};
  for (final t in titles) {
    for (final v in t.versions) {
      if (v.metadata case final m?) {
        byId.putIfAbsent(m.id, () => []).add((t, v));
      }
    }
  }
  return {
    for (final e in byId.entries)
      if (e.value.length > 1) e.key: e.value,
  };
}

/// Version metadata stored in the `.RPP` EXTSTATE section (SPEC §4.2).
final class VersionMetadata {
  const VersionMetadata({
    required this.id,
    required this.owner,
    this.label = '',
  });

  static const section = 'REAHARVEST';
  static const idKey = 'VERSIONID';
  static const ownerKey = 'OWNER';
  static const labelKey = 'LABEL';

  final VersionId id;
  final MemberId owner;
  final String label;

  /// EXTSTATE values; an empty value removes the key.
  Map<String, String> toExtState() => {
    idKey: id,
    ownerKey: owner,
    labelKey: label,
  };

  /// Reads an EXTSTATE section; null if the version is not adopted.
  static VersionMetadata? fromExtState(Map<String, String> values) {
    final upper = {
      for (final e in values.entries) e.key.toUpperCase(): e.value,
    };
    final id = upper[idKey];
    final owner = upper[ownerKey];
    if (id == null || id.isEmpty || owner == null || owner.isEmpty) return null;
    return VersionMetadata(
      id: VersionId(id),
      owner: MemberId(owner),
      label: upper[labelKey] ?? '',
    );
  }
}

/// A `.RPP` file in a title folder.
final class Version {
  const Version({
    required this.fileName,
    required this.modified,
    required this.size,
    this.metadata,
    this.tempo,
    this.plugins = const [],
  });

  /// File path relative to the title folder, `/`-separated: a plain file
  /// name in layout libraries, possibly nested in a free tree (SPEC §3.3).
  /// Free in layout libraries, not part of the identity.
  final String fileName;

  /// Version date (file modification time).
  final DateTime modified;

  final int size;

  /// Null when the file has no metadata yet ("To adopt" section).
  final VersionMetadata? metadata;

  /// Project tempo (BPM); null when unknown (e.g. free tree projects,
  /// which are never read, SPEC §3.3).
  final double? tempo;

  /// Plugins used by the project, deduplicated; empty when unknown.
  final List<PluginRef> plugins;

  bool get isAdopted => metadata != null;

  /// Version identity used for statuses: the version id, or [fileName] when
  /// the version has no metadata (free tree versions, SPEC §3.3).
  String get key => metadata?.id ?? fileName;
}

/// A plugin used by a version, as written in the `.RPP` (SPEC §5.3).
final class PluginRef {
  const PluginRef({
    required this.kind,
    required this.name,
    required this.identifier,
  });

  /// Format as written by REAPER (`VST3`, `VSTi`, `JS`, `CLAP`…).
  final String kind;

  /// Display name, e.g. `ReaEQ (Cockos)`.
  final String name;

  /// What the plugin cache is keyed on (plugin file, JS path, plugin id).
  final String identifier;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    'identifier': identifier,
  };

  static PluginRef fromJson(Map<String, Object?> json) => PluginRef(
    kind: json['kind'] as String,
    name: json['name'] as String,
    identifier: json['identifier'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is PluginRef &&
      other.kind == kind &&
      other.name == name &&
      other.identifier == identifier;

  @override
  int get hashCode => Object.hash(kind, name, identifier);
}

/// A media file referenced by a version.
final class MediaRef {
  const MediaRef(this.path, {this.size});

  /// Path as referenced in the `.RPP`.
  final String path;

  /// Local size; null when the file is missing.
  final int? size;

  bool get isPresent => size != null;
}

/// Synchronization state of a file or title (modes cloud and collab).
enum SyncState {
  notCheckedOut,
  upToDate,
  localChanges,
  remoteChanges,
  conflict;

  /// State from content hashes: [base] at last checkout/publish, [local] in
  /// the workspace, [remote] in the repository. Null means absent.
  static SyncState of({String? base, String? local, String? remote}) {
    if (local == null) return notCheckedOut;
    if (local == remote) return upToDate;
    final localChanged = local != base;
    final remoteChanged = remote != base;
    if (localChanged && remoteChanged) return conflict;
    return localChanged ? localChanges : remoteChanges;
  }
}
