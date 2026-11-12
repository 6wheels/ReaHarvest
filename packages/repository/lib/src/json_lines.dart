import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Lines of a JSON Lines file of a migration (SPEC §5.8 step 5): one JSON
/// object per line, each ended by `\n`. A line that is not a JSON object is
/// null; [cut] tells whether the file ends with a line without `\n`, cut by
/// a crash and not part of [lines].
typedef JsonLines = ({List<Map<String, dynamic>?> lines, bool cut});

/// Reads the JSON Lines file [path], or null if absent.
Future<JsonLines?> readJsonLines(RepositoryStorage storage, String path) async {
  if (await storage.stat(path) == null) return null;
  final bytes = [await for (final chunk in storage.read(path)) ...chunk];
  final parts = utf8.decode(bytes, allowMalformed: true).split('\n');
  final cut = parts.removeLast().isNotEmpty;
  return (lines: [for (final line in parts) _object(line)], cut: cut);
}

Map<String, dynamic>? _object(String line) {
  try {
    return switch (jsonDecode(line)) {
      final Map<String, dynamic> object => object,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// Appends JSON objects to the file [path], one line each.
final class JsonLinesFile {
  JsonLinesFile(this._storage, this.path, {this.length = 0, this._cut = false});

  final RepositoryStorage _storage;
  final String path;

  /// Number of lines ended by `\n` in the file.
  int length;

  /// Whether the file may end with a line without `\n`.
  bool _cut;

  /// Appends [objects] in one write; creates the file even when empty. A
  /// line cut by a crash is first closed by `#`, so that it stays invalid
  /// even if what was written of it happens to be a whole object.
  Future<void> append(Iterable<Map<String, Object?>> objects) async {
    final buffer = StringBuffer();
    var added = 0;
    if (_cut) {
      buffer.write('#\n');
      added++;
    }
    for (final o in objects) {
      buffer
        ..write(jsonEncode(o))
        ..write('\n');
      added++;
    }
    try {
      await _storage.append(path, utf8.encode(buffer.toString()));
    } on Object {
      // Part of the lines may have been written.
      _cut = true;
      rethrow;
    }
    _cut = false;
    length += added;
  }
}
