import 'ids.dart';

/// A title: leaf node folder holding `Media/`, assets and versions.
final class Title {
  const Title({
    required this.id,
    required this.libraryId,
    required this.path,
    required this.tags,
    this.versions = const [],
  });

  final NodeId id;
  final LibraryId libraryId;

  /// Folder path relative to the library root, `/`-separated.
  final String path;

  /// Tags derived from the path (e.g. `artist`, `album`, `title`).
  final Map<String, String> tags;

  final List<Version> versions;
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
  });

  /// File name; free, not part of the identity.
  final String fileName;

  /// Version date (file modification time).
  final DateTime modified;

  final int size;

  /// Null when the file has no metadata yet ("À adopter").
  final VersionMetadata? metadata;

  bool get isAdopted => metadata != null;
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
