import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'node_file.dart';

/// Media pool folder of a title (SPEC §4.3).
const mediaFolderName = 'Media';

/// Default render folder of a title (SPEC §5.3).
const rendersFolderName = 'Renders';

/// Attached files of a title (SPEC §5.9).
const assetsFolderName = 'Assets';

/// Backups of the versions of a title (SPEC §5.4).
const historyFolderName = '.history';

/// Deleted versions and assets of a title (SPEC §5.4).
const trashFolderName = '.trash';

/// Folders created with every title of a layout library (SPEC §3.2).
const titleFolders = [
  mediaFolderName,
  rendersFolderName,
  assetsFolderName,
  historyFolderName,
  trashFolderName,
];

/// Creates or adopts the title folder [dir] of a layout library (SPEC §3.2):
/// creates its [titleFolders] and writes its node file with a new id and
/// [level]. Returns the node.
Future<NodeFile> scaffoldTitle(
  RepositoryStorage storage,
  String dir,
  String level,
) async {
  for (final name in titleFolders) {
    await storage.createDirectory(dir.isEmpty ? name : '$dir/$name');
  }
  final node = NodeFile(NodeId.generate(), level);
  await writeNodeFile(storage, dir, node);
  return node;
}
