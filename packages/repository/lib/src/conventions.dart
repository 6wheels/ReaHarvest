import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'mounted_folder_storage.dart';

/// Node identity file, in each layout node and free tree title (SPEC §3.2).
const nodeFileName = '.node.json';

/// `level` value of free tree title nodes (SPEC §3.3).
const freeTreeLevel = 'title';

/// Collab journal folder, at the library root (SPEC §6.3).
const collabFolderName = '_collab';

/// Title subfolders holding no versions (SPEC §3.2), lowercase.
const reservedTitleFolders = {
  'media',
  'renders',
  'assets',
  '_versions',
  '_trash',
  'backups',
};

/// Folders never scanned for versions, wherever they are, lowercase:
/// REAPER backups, history and trash.
const _excludedFolders = {'backups', '_versions', '_trash'};

const _excludedNames = {'.ds_store', 'desktop.ini', 'thumbs.db'};

const _excludedExtensions = {
  '.reapeaks',
  '.rpp-bak',
  '.rpp-undo',
  '.rpp-prox',
  '.reapindex',
  '.gdoc',
  '.gsheet',
  '.gslides',
  '.gdraw',
  '.gform',
  '.gmap',
  '.gsite',
  MountedFolderStorage.tempSuffix,
};

/// Whether [name] is a REAPER project file (case-insensitive).
bool isProjectFile(String name) => p.extension(name).toLowerCase() == '.rpp';

/// Whether the file [name] is excluded from sync and indexing (SPEC §3.2).
bool isExcludedFile(String name) {
  final lower = name.toLowerCase();
  return _excludedNames.contains(lower) ||
      lower.startsWith('._') ||
      _excludedExtensions.contains(p.extension(lower));
}

/// Whether the folder [name] is excluded from version scanning.
bool isExcludedFolder(String name) =>
    _excludedFolders.contains(name.toLowerCase());

/// Content of a `.node.json` file.
final class NodeFile {
  const NodeFile(this.id, this.level);

  final NodeId id;

  /// Layout level key, or [freeTreeLevel].
  final String level;

  Map<String, Object?> toJson() => {'nodeId': id, 'level': level};

  static NodeFile fromJson(Map<String, Object?> json) {
    final id = json['nodeId'];
    final level = json['level'];
    if (id is! String || !isUlid(id) || level is! String) {
      throw FormatException('Invalid $nodeFileName', json);
    }
    return NodeFile(NodeId(id), level);
  }
}
