import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'project_file.dart';

/// Writes [metadata] into the EXTSTATE section of the project at [path]
/// ("To adopt", Save As duplicates, SPEC §4.2): targeted patch, atomic
/// write, in the encoding of the project (SPEC §7.3).
Future<void> writeVersionMetadata(
  RepositoryStorage storage,
  String path,
  VersionMetadata metadata,
) async {
  final (:text, :encoding) = await readProject(storage, path);
  final patched = setExtState(
    text,
    VersionMetadata.section,
    metadata.toExtState(),
  );
  await writeProject(storage, path, patched, encoding);
}
