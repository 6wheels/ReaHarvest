import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

/// Writes [metadata] into the EXTSTATE section of the project at [path]
/// ("To adopt", Save As duplicates, SPEC §4.2): targeted patch, atomic
/// write. Throws [FormatException] if the file is not valid UTF-8.
Future<void> writeVersionMetadata(
  RepositoryStorage storage,
  String path,
  VersionMetadata metadata,
) async {
  final text = await _readText(storage, path);
  final patched = setExtState(
    text,
    VersionMetadata.section,
    metadata.toExtState(),
  );
  await storage.write(path, Stream.value(utf8.encode(patched)));
}

Future<String> _readText(RepositoryStorage storage, String path) =>
    storage.read(path).transform(utf8.decoder).join();
