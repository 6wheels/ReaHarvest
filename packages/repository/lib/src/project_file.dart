import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Text encoding of a project file (SPEC §7.3).
enum ProjectEncoding { utf8, windows1252 }

/// Thrown by [writeProject] when the text holds a character that
/// Windows-1252 cannot write. The project at [path] is left untouched.
final class ProjectEncodingException implements Exception {
  const ProjectEncodingException(this.path);

  final String path;

  @override
  String toString() =>
      'This project uses an old text encoding that cannot hold this name '
      '($path). Rename the folder or the file without special characters, '
      'then try again.';
}

/// Reads the project at [path]: UTF-8 when its bytes are valid UTF-8,
/// Windows-1252 otherwise. Any byte sequence decodes.
Future<({String text, ProjectEncoding encoding})> readProject(
  RepositoryStorage storage,
  String path,
) async {
  final bytes = <int>[];
  await for (final chunk in storage.read(path)) {
    bytes.addAll(chunk);
  }
  try {
    return (
      text: const Utf8Decoder().convert(bytes),
      encoding: ProjectEncoding.utf8,
    );
  } on FormatException {
    return (text: _decode1252(bytes), encoding: ProjectEncoding.windows1252);
  }
}

/// Writes [text] to the project at [path] in [encoding]. Throws
/// [ProjectEncodingException], without writing, if [text] cannot be
/// written in it.
Future<void> writeProject(
  RepositoryStorage storage,
  String path,
  String text,
  ProjectEncoding encoding,
) async {
  final bytes = switch (encoding) {
    ProjectEncoding.utf8 => utf8.encode(text),
    ProjectEncoding.windows1252 => _encode1252(path, text),
  };
  await storage.write(path, Stream.value(bytes));
}

/// Code points of the bytes 0x80 to 0x9F; the five undefined bytes map to
/// the code point of the same value.
const _high = <int>[
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, //
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, //
];

final _byteOf = {for (var i = 0; i < _high.length; i++) _high[i]: 0x80 + i};

String _decode1252(List<int> bytes) => String.fromCharCodes([
  for (final b in bytes) b >= 0x80 && b < 0xA0 ? _high[b - 0x80] : b,
]);

List<int> _encode1252(String path, String text) {
  final bytes = <int>[];
  for (final c in text.codeUnits) {
    if (c < 0x80 || (c >= 0xA0 && c <= 0xFF)) {
      bytes.add(c);
    } else if (_byteOf[c] case final b?) {
      bytes.add(b);
    } else {
      throw ProjectEncodingException(path);
    }
  }
  return bytes;
}
