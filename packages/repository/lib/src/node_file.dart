import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Node identity file, in each layout node and free tree title (SPEC §3.2).
const nodeFileName = '.node.json';

/// `level` value of free tree title nodes (SPEC §3.3).
const freeTreeLevel = 'title';

/// Content of a `.node.json` file. Title nodes also carry the title and
/// version statuses (SPEC §5.9), and the version labels and owners (SPEC
/// §4.2), until the collab store takes them over.
final class NodeFile {
  const NodeFile(
    this.id,
    this.level, {
    this.status,
    this.versionStatuses = const {},
    this.versionLabels = const {},
    this.versionOwners = const {},
  });

  final NodeId id;

  /// Layout level key, or [freeTreeLevel].
  final String level;

  /// Title status key; null when not set.
  final String? status;

  /// Version statuses, by [Version.key]: version id, or path relative to the
  /// title folder in a free tree.
  final Map<String, String> versionStatuses;

  /// Version labels, by version id. May hold ids of versions that no longer
  /// exist, like [versionStatuses].
  final Map<String, String> versionLabels;

  /// Version owners (member ids), by version id.
  final Map<String, String> versionOwners;

  /// Copy with the title status set to [status] (null or empty clears it).
  NodeFile withStatus(String? status) => NodeFile(
    id,
    level,
    status: _orNull(status),
    versionStatuses: versionStatuses,
    versionLabels: versionLabels,
    versionOwners: versionOwners,
  );

  /// Copy with the status of the version keyed [version] (see
  /// [Version.key]) set to [status] (null or empty clears it).
  NodeFile withVersionStatus(String version, String? status) =>
      _copy(versionStatuses: _with(versionStatuses, version, status));

  /// Copy with the label of the version [id] set to [label] (null or empty
  /// clears it).
  NodeFile withVersionLabel(String id, String? label) =>
      _copy(versionLabels: _with(versionLabels, id, label));

  /// Copy with the owner of the version [id] set to [owner] (null or empty
  /// clears it).
  NodeFile withVersionOwner(String id, String? owner) =>
      _copy(versionOwners: _with(versionOwners, id, owner));

  /// Copy with the label and owner of the version [metadata]; only where the
  /// version has none if [onlyMissing]. A null owner is not written.
  NodeFile withVersion(VersionMetadata metadata, {bool onlyMissing = false}) {
    final id = metadata.id;
    var updated = this;
    if (!onlyMissing || !versionLabels.containsKey(id)) {
      updated = updated.withVersionLabel(id, metadata.label);
    }
    if (metadata.owner case final owner?
        when !onlyMissing || !versionOwners.containsKey(id)) {
      updated = updated.withVersionOwner(id, owner);
    }
    return updated;
  }

  NodeFile _copy({
    Map<String, String>? versionStatuses,
    Map<String, String>? versionLabels,
    Map<String, String>? versionOwners,
  }) => NodeFile(
    id,
    level,
    status: status,
    versionStatuses: versionStatuses ?? this.versionStatuses,
    versionLabels: versionLabels ?? this.versionLabels,
    versionOwners: versionOwners ?? this.versionOwners,
  );

  Map<String, Object?> toJson() => {
    'nodeId': id,
    'level': level,
    'status': ?status,
    if (versionStatuses.isNotEmpty) 'versionStatuses': versionStatuses,
    if (versionLabels.isNotEmpty) 'versionLabels': versionLabels,
    if (versionOwners.isNotEmpty) 'versionOwners': versionOwners,
  };

  static NodeFile fromJson(Map<String, Object?> json) {
    final id = json['nodeId'];
    final level = json['level'];
    final status = json['status'];
    if (id is! String ||
        !isUlid(id) ||
        level is! String ||
        (status != null && status is! String)) {
      throw FormatException('Invalid $nodeFileName', json);
    }
    Map<String, String> map(String key) {
      final value = json[key] ?? const {};
      if (value is! Map || value.values.any((s) => s is! String)) {
        throw FormatException('Invalid $nodeFileName', json);
      }
      return {
        for (final e in value.entries)
          if (_orNull(e.value as String) != null)
            e.key as String: e.value as String,
      };
    }

    return NodeFile(
      NodeId(id),
      level,
      status: _orNull(status as String?),
      versionStatuses: map('versionStatuses'),
      versionLabels: map('versionLabels'),
      versionOwners: map('versionOwners'),
    );
  }

  static String? _orNull(String? s) => s == null || s.isEmpty ? null : s;

  /// [map] with [key] set to [value], or removed when it is null or empty.
  static Map<String, String> _with(
    Map<String, String> map,
    String key,
    String? value,
  ) {
    final copy = {...map}..remove(key);
    if (_orNull(value) case final v?) copy[key] = v;
    return copy;
  }
}

/// Reads the node file of the folder [dir]; null if absent.
Future<NodeFile?> readNodeFile(RepositoryStorage storage, String dir) async {
  final path = _nodePath(dir);
  if (await storage.stat(path) == null) return null;
  final text = await utf8.decodeStream(storage.read(path));
  return NodeFile.fromJson((jsonDecode(text) as Map).cast());
}

/// Writes the node file of the folder [dir] (atomic write by [storage]).
Future<void> writeNodeFile(
  RepositoryStorage storage,
  String dir,
  NodeFile node,
) {
  final json = jsonEncode(node.toJson());
  return storage.write(_nodePath(dir), Stream.value(utf8.encode('$json\n')));
}

/// Sets the status of the title at [titlePath] (null clears it). The node
/// file is read again first, so that no concurrent change is lost.
Future<NodeFile> setTitleStatus(
  RepositoryStorage storage,
  String titlePath,
  String? status,
) => updateNodeFile(storage, titlePath, (n) => n.withStatus(status));

/// Sets the status of the version keyed [version] (see [Version.key]) in
/// the title at [titlePath] (null clears it).
Future<NodeFile> setVersionStatus(
  RepositoryStorage storage,
  String titlePath,
  String version,
  String? status,
) => updateNodeFile(
  storage,
  titlePath,
  (n) => n.withVersionStatus(version, status),
);

/// Sets the label of the version [id] in the title at [titlePath] (SPEC
/// §4.2; null or empty clears it). No project is read nor written.
Future<NodeFile> setVersionLabel(
  RepositoryStorage storage,
  String titlePath,
  VersionId id,
  String? label,
) => updateNodeFile(storage, titlePath, (n) => n.withVersionLabel(id, label));

/// Sets the owner of the version [id] in the title at [titlePath] (SPEC
/// §4.2; null clears it). No project is read nor written.
Future<NodeFile> setVersionOwner(
  RepositoryStorage storage,
  String titlePath,
  VersionId id,
  MemberId? owner,
) => updateNodeFile(storage, titlePath, (n) => n.withVersionOwner(id, owner));

/// Applies [change] to the node file of [dir], read again first. Throws
/// [StateError] when [dir] has no node file.
Future<NodeFile> updateNodeFile(
  RepositoryStorage storage,
  String dir,
  NodeFile Function(NodeFile) change,
) async {
  final node = await readNodeFile(storage, dir);
  if (node == null) {
    throw StateError('No $nodeFileName in "$dir"; scan the library first');
  }
  final updated = change(node);
  await writeNodeFile(storage, dir, updated);
  return updated;
}

String _nodePath(String dir) =>
    dir.isEmpty ? nodeFileName : '$dir/$nodeFileName';
