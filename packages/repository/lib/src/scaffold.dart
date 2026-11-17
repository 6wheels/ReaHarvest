import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'node_file.dart';

/// Media folder of a version, its record path (SPEC §4.3).
const mediaFolderName = 'Media';

/// Default render folder of a version (SPEC §5.3).
const rendersFolderName = 'Renders';

/// Attached files of a title (SPEC §5.9).
const assetsFolderName = 'Assets';

/// Backups of a version, in its folder (SPEC §5.4).
const historyFolderName = '.history';

/// Deleted versions and assets of a title (SPEC §5.4).
const trashFolderName = '.trash';

/// Folders created with every version of a layout library (SPEC §3.2).
const versionFolders = [mediaFolderName, rendersFolderName];

/// Creates or adopts the title folder [dir] of a layout library (SPEC §3.2):
/// writes its node file with a new id and [level]; its other folders are
/// created by the first operation that needs them. Returns the node.
Future<NodeFile> scaffoldTitle(
  RepositoryStorage storage,
  String dir,
  String level,
) async {
  final node = NodeFile(NodeId.generate(), level);
  await writeNodeFile(storage, dir, node);
  return node;
}
