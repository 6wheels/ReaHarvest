import 'dart:convert';
import 'dart:typed_data';

final _base64Line = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

/// Names of [fileNames] that appear in [projectText] outside the `FILE`
/// lines of its `SOURCE` chunks (SPEC §4.3): in plain text, or in the
/// decoded base64 lines of a plugin state, as UTF-8 or UTF-16LE. A name is
/// the file name with its extension, searched as a substring, ignoring
/// case. A false positive only keeps a file where it is.
Set<String> namedOutsideSources(
  String projectText,
  Iterable<String> fileNames,
) {
  final originals = <String, String>{
    for (final name in fileNames)
      if (name.isNotEmpty) name.toLowerCase(): name,
  };
  if (originals.isEmpty) return const {};
  final names = originals.keys;
  final found = <String>{};
  final plain = StringBuffer();
  final chunks = <String>[];
  var run = BytesBuilder(copy: false);

  void flushRun() {
    if (run.isEmpty) return;
    final bytes = run.takeBytes();
    for (final text in _decodings(bytes)) {
      for (final name in names) {
        if (text.contains(name)) found.add(name);
      }
    }
  }

  for (final raw in const LineSplitter().convert(projectText)) {
    final line = raw.trim();
    if (line.startsWith('<')) {
      chunks.add(line.substring(1).split(RegExp(r'\s')).first);
    } else if (line == '>') {
      if (chunks.isNotEmpty) chunks.removeLast();
    }
    final isSourceFile =
        chunks.lastOrNull == 'SOURCE' && line.startsWith('FILE ');
    if (!isSourceFile) plain.writeln(line.toLowerCase());
    if (line.length % 4 == 0 && _base64Line.hasMatch(line)) {
      run.add(base64.decode(line));
      continue;
    }
    flushRun();
    run = BytesBuilder(copy: false);
  }
  flushRun();
  final text = plain.toString();
  for (final name in names) {
    if (text.contains(name)) found.add(name);
  }
  return {for (final name in found) originals[name]!};
}

/// [bytes] as lowercase text: UTF-8, then UTF-16LE from each alignment.
Iterable<String> _decodings(Uint8List bytes) sync* {
  yield utf8.decode(bytes, allowMalformed: true).toLowerCase();
  for (final start in [0, 1]) {
    final units = <int>[
      for (var i = start; i + 1 < bytes.length; i += 2)
        bytes[i] | (bytes[i + 1] << 8),
    ];
    yield String.fromCharCodes(units).toLowerCase();
  }
}
