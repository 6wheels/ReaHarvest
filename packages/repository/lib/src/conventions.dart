import 'package:path/path.dart' as p;

import 'mounted_folder_storage.dart';

/// Collab journal folder, at the library root (SPEC §6.3).
const collabFolderName = '.collab';

/// Migration inventories and original projects, at the library root
/// (SPEC §5.8).
const migrationFolderName = '.migration';

/// Title subfolders holding no versions (SPEC §3.2), lowercase.
const reservedTitleFolders = {
  'media',
  'renders',
  'assets',
  '.history',
  '.trash',
  'backups',
};

/// Folders never scanned for versions, wherever they are, lowercase:
/// REAPER backups, history and trash.
const _excludedFolders = {'backups', '.history', '.trash'};

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

/// Whether [name] can be a layout folder name on every OS: not empty, no
/// path separator or reserved character, no trailing dot or space, and no
/// leading dot (reserved for application files, SPEC §3.2).
bool isValidFolderName(String name) =>
    name.isNotEmpty &&
    !name.startsWith('.') &&
    !name.endsWith('.') &&
    !name.endsWith(' ') &&
    !RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(name);
