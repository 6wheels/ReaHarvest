import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'library_path.dart';
import 'node_file.dart';
import 'project_file.dart';

/// Adopts the project [fileName] of the title [titleDir] ("To adopt", SPEC
/// §4.2): label and owner of [metadata] in the title's node file, then its
/// id in the project, the only rewrite. The node file comes first: if the
/// project cannot be written, the entry left names no version.
Future<void> adoptVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
  VersionMetadata metadata,
) async {
  await writeVersionEntries(storage, titleDir, metadata);
  await writeVersionId(storage, joinPath(titleDir, fileName), metadata.id);
}

/// Makes the *Save As* copy [fileName] of the title [titleDir] a new version
/// (SPEC §4.2): a new id in the file, the label of the original copied to it
/// and [owner], if any, set. Returns the new id. Throws [StateError] if the
/// project is not adopted.
Future<VersionId> separateDuplicateVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName, {
  MemberId? owner,
}) async {
  final path = joinPath(titleDir, fileName);
  final (:text, :encoding) = await readProject(storage, path);
  final original = VersionMetadata.fromExtState(
    RppProject.parse(text).extState(VersionMetadata.section),
  );
  if (original == null) throw StateError('Version not adopted: $path');
  final id = VersionId.generate();
  await updateNodeFile(storage, titleDir, (node) {
    var copy = node;
    if (node.versionLabels[original.id] case final label?) {
      copy = copy.withVersionLabel(id, label);
    }
    return owner == null ? copy : copy.withVersionOwner(id, owner);
  });
  await writeProject(
    storage,
    path,
    setExtState(
      text,
      VersionMetadata.section,
      VersionMetadata(id: id).toExtState(),
    ),
    encoding,
  );
  return id;
}

/// Writes the label and owner of the version [metadata] into the node file
/// of the title [titleDir] (SPEC §4.2, [NodeFile.withVersion]).
Future<NodeFile> writeVersionEntries(
  RepositoryStorage storage,
  String titleDir,
  VersionMetadata metadata,
) => updateNodeFile(storage, titleDir, (node) => node.withVersion(metadata));

/// Writes the version [id] into the EXTSTATE section of the project at
/// [path]: targeted patch, atomic write, in the encoding of the project
/// (SPEC §7.3). Other keys of the section are kept.
Future<void> writeVersionId(
  RepositoryStorage storage,
  String path,
  VersionId id,
) async {
  final (:text, :encoding) = await readProject(storage, path);
  final patched = setExtState(
    text,
    VersionMetadata.section,
    VersionMetadata(id: id).toExtState(),
  );
  await writeProject(storage, path, patched, encoding);
}
