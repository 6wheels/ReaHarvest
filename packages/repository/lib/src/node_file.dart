import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Node identity file, in each layout node and free tree title (SPEC §3.2).
const nodeFileName = '.node.json';

/// `level` value of free tree title nodes (SPEC §3.3).
const freeTreeLevel = 'title';

/// Content of a `.node.json` file. Title nodes also carry the title and
/// version statuses in local and cloud modes (SPEC §5.9).
final class NodeFile {
  const NodeFile(
    this.id,
    this.level, {
    this.status,
    this.versionStatuses = const {},
  });

  final NodeId id;

  /// Layout level key, or [freeTreeLevel].
  final String level;

  /// Title status key; null when not set.
  final String? status;

  /// Version statuses, by version id.
  final Map<VersionId, String> versionStatuses;

  /// Copy with the title status set to [status] (null or empty clears it).
  NodeFile withStatus(String? status) => NodeFile(
    id,
    level,
    status: _orNull(status),
    versionStatuses: versionStatuses,
  );

  /// Copy with the status of [version] set to [status] (null or empty
  /// clears it).
  NodeFile withVersionStatus(VersionId version, String? status) {
    final statuses = {...versionStatuses}..remove(version);
    if (_orNull(status) case final s?) statuses[version] = s;
    return NodeFile(id, level, status: this.status, versionStatuses: statuses);
  }

  Map<String, Object?> toJson() => {
    'nodeId': id,
    'level': level,
    'status': ?status,
    if (versionStatuses.isNotEmpty) 'versionStatuses': versionStatuses,
  };

  static NodeFile fromJson(Map<String, Object?> json) {
    final id = json['nodeId'];
    final level = json['level'];
    final status = json['status'];
    final versionStatuses = json['versionStatuses'] ?? const {};
    if (id is! String ||
        !isUlid(id) ||
        level is! String ||
        (status != null && status is! String) ||
        versionStatuses is! Map ||
        versionStatuses.values.any((s) => s is! String)) {
      throw FormatException('Invalid $nodeFileName', json);
    }
    return NodeFile(
      NodeId(id),
      level,
      status: _orNull(status as String?),
      versionStatuses: {
        for (final e in versionStatuses.entries)
          if (_orNull(e.value as String) != null)
            VersionId(e.key as String): e.value as String,
      },
    );
  }

  static String? _orNull(String? s) => s == null || s.isEmpty ? null : s;
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
) => _updateNodeFile(storage, titlePath, (n) => n.withStatus(status));

/// Sets the status of [version] in the title at [titlePath] (null clears
/// it).
Future<NodeFile> setVersionStatus(
  RepositoryStorage storage,
  String titlePath,
  VersionId version,
  String? status,
) => _updateNodeFile(
  storage,
  titlePath,
  (n) => n.withVersionStatus(version, status),
);

Future<NodeFile> _updateNodeFile(
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
