import 'ids.dart';

/// A title: leaf node folder holding its assets, its trash and one folder
/// per version (SPEC §3.2).
final class Title {
  const Title({
    required this.id,
    required this.libraryId,
    required this.path,
    required this.levels,
    this.tags = const [],
    this.versions = const [],
    this.versionStatuses = const {},
    this.trashSize = 0,
    this.trashedVersions = 0,
    this.backupCount = 0,
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

  /// Level values derived from the path (e.g. `artist`, `album`, `title`).
  final Map<String, String> levels;

  /// Free tags of the title, shared by the members (SPEC §5.9): trimmed,
  /// unique ignoring case (see [normalizeTags]).
  final List<String> tags;

  final List<Version> versions;

  /// Status of each version, by [Version.key]. May hold keys of versions
  /// that no longer exist.
  final Map<String, String> versionStatuses;

  /// Bytes used by the title's `.trash/`, from the scan (SPEC §5.2).
  final int trashSize;

  /// Number of versions in the title's `.trash/`, from the scan.
  final int trashedVersions;

  /// Number of backup points (`.history/`) of its versions, from the scan.
  final int backupCount;

  /// Status of [version]; null when not set.
  String? statusOf(Version version) => versionStatuses[version.key];

  /// Title status, never stored (SPEC §5.9): the highest status of its
  /// versions in the order of [defaultStatuses], a status outside it
  /// ranking below; null when no version has one.
  String? get status {
    String? best;
    var rank = -2;
    for (final v in versions) {
      final s = statusOf(v);
      if (s == null) continue;
      final r = defaultStatuses.indexOf(s);
      if (r > rank) (best, rank) = (s, r);
    }
    return best;
  }
}

/// [tags] trimmed, without the empty ones and the duplicates ignoring case,
/// the first spelling kept (SPEC §5.9).
List<String> normalizeTags(Iterable<String> tags) {
  final seen = <String>{};
  return [
    for (final t in tags.map((t) => t.trim()))
      if (t.isNotEmpty && seen.add(t.toLowerCase())) t,
  ];
}

/// The tags used by [titles], for autocompletion: unique ignoring case (the
/// first spelling kept), sorted ignoring case.
List<String> knownTags(Iterable<Title> titles) =>
    normalizeTags([for (final t in titles) ...t.tags])
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

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

/// Version metadata (SPEC §4.2): the id is stored in the `.RPP` EXTSTATE
/// section; label and owner in the title's `.node.json`, filled in by the
/// scan.
final class VersionMetadata {
  const VersionMetadata({required this.id, this.label = '', this.owner});

  static const section = 'REAHARVEST';
  static const idKey = 'VERSIONID';

  final VersionId id;
  final String label;

  /// Null when the library declares no members, or none was chosen.
  final MemberId? owner;

  /// EXTSTATE values: the version id only. `OWNER` and `LABEL` keys found
  /// in a project are neither read nor removed.
  Map<String, String> toExtState() => {idKey: id};

  /// Reads an EXTSTATE section (id only, label and owner left empty); null
  /// if the version is not adopted.
  static VersionMetadata? fromExtState(Map<String, String> values) {
    final id = [
      for (final e in values.entries)
        if (e.key.toUpperCase() == idKey) e.value,
    ].firstOrNull;
    if (id == null || id.isEmpty) return null;
    return VersionMetadata(id: VersionId(id));
  }
}

/// A version of a title: in a layout library, a version folder holding its
/// `.RPP` (SPEC §3.2); in a free tree, a `.RPP` below the title (SPEC §3.3).
final class Version {
  const Version({
    required this.fileName,
    required this.modified,
    required this.size,
    this.folder,
    this.sizes = const {},
    this.sampleRate,
    this.metadata,
    this.tempo,
    this.length,
    this.trackCount,
    this.itemCount,
    this.plugins = const [],
    this.media = const [],
    this.recordPath,
    this.renderFile,
  });

  /// Path of the `.RPP` relative to the title folder, `/`-separated:
  /// `<version>/<version>.RPP` in layout libraries, possibly nested in a
  /// free tree (SPEC §3.3). Not part of the identity.
  final String fileName;

  /// Version date (file modification time).
  final DateTime modified;

  /// Bytes used: every file of the version folder in layout libraries,
  /// backups included; the `.RPP` alone in a free tree.
  final int size;

  /// [size] by category of file; empty when unknown.
  final Map<SizeCategory, int> sizes;

  /// Name of the version folder, in the title folder; null in a free tree.
  final String? folder;

  /// Project sample rate (`SAMPLERATE`); null when unknown.
  final int? sampleRate;

  /// Null when the file has no metadata yet ("To adopt" section).
  final VersionMetadata? metadata;

  /// Project tempo (BPM); null when unknown (e.g. free tree projects,
  /// which are never read, SPEC §3.3).
  final double? tempo;

  /// Project length (end of the last item), in seconds; null when unknown
  /// (like [tempo]).
  final double? length;

  /// Number of tracks; null when unknown (like [tempo]).
  final int? trackCount;

  /// Number of media items; null when unknown (like [tempo]).
  final int? itemCount;

  /// Plugins used by the project, deduplicated; empty when unknown.
  final List<PluginRef> plugins;

  /// Media references (`FILE` lines of `SOURCE` chunks), deduplicated, as
  /// written in the project (relative or absolute); empty when unknown.
  final List<String> media;

  /// Record path (`RECORD_PATH`) as written; null when absent or unknown.
  final String? recordPath;

  /// Render target (`RENDER_FILE`) as written; null when absent or unknown.
  final String? renderFile;

  bool get isAdopted => metadata != null;

  /// This version with [metadata] instead of its own.
  Version withMetadata(VersionMetadata metadata) => _copy(metadata: metadata);

  /// This version in the version folder [folder], whose files weigh
  /// [sizes]; [size] is their total.
  Version withSizes(String? folder, Map<SizeCategory, int> sizes) => _copy(
    folder: folder,
    sizes: sizes,
    size: sizes.values.fold<int>(0, (a, b) => a + b),
  );

  Version _copy({
    VersionMetadata? metadata,
    String? folder,
    int? size,
    Map<SizeCategory, int>? sizes,
  }) => Version(
    fileName: fileName,
    modified: modified,
    size: size ?? this.size,
    folder: folder ?? this.folder,
    sizes: sizes ?? this.sizes,
    sampleRate: sampleRate,
    metadata: metadata ?? this.metadata,
    tempo: tempo,
    length: length,
    trackCount: trackCount,
    itemCount: itemCount,
    plugins: plugins,
    media: media,
    recordPath: recordPath,
    renderFile: renderFile,
  );

  /// Version identity used for statuses: the version id, or [fileName] when
  /// the version has no metadata (free tree versions, SPEC §3.3).
  String get key => metadata?.id ?? fileName;
}

/// Kind of the files of a version folder, to tell what takes space (SPEC
/// §4.3).
enum SizeCategory {
  /// The `.RPP` files of the folder.
  project,

  /// `Media/`.
  media,

  /// `Renders/`.
  renders,

  /// The backup points of ReaHarvest (`.history/`).
  history,

  /// REAPER's own backups: `Backups/`, `.rpp-bak` and `.rpp-undo` files.
  reaperBackups,

  /// Anything else (peaks, notes…).
  other,
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
