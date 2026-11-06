import 'dart:isolate';
import 'dart:typed_data';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:xxh3/xxh3.dart';

import 'local_index.dart';

/// XXH3-64 hash of [content] (SPEC §7.1), computed chunk by chunk, as 16
/// lowercase hex digits.
Future<String> xxh3Hash(Stream<List<int>> content) async {
  final state = xxh3Stream();
  await for (final chunk in content) {
    state.update(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
  }
  return state.digestString().padLeft(16, '0');
}

/// [FileHasher] hashing files of [storage] with [xxh3Hash], each in a
/// background isolate. [storage] must be sendable to an isolate.
FileHasher xxh3Hasher(RepositoryStorage storage) =>
    (path) => Isolate.run(() => xxh3Hash(storage.read(path)));
