import 'dart:typed_data';

import 'package:xxh3/xxh3.dart';

/// Hash of the content of the file at a library path.
typedef ContentHash = Future<String> Function(String path);

/// XXH3-64 hash of [content] (SPEC §7.1), computed chunk by chunk, as 16
/// lowercase hex digits.
Future<String> xxh3Hash(Stream<List<int>> content) async {
  final state = xxh3Stream();
  await for (final chunk in content) {
    state.update(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
  }
  return state.digestString().padLeft(16, '0');
}
