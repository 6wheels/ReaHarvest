import 'dart:convert';

import 'tree.dart';

/// Decodes an `EXTSTATE` section chunk: `KEY value` lines and `<BIN KEY`
/// base64 sub-chunks. Keys are upper-cased.
Map<String, String> readExtStateSection(RppChunk section) {
  final values = <String, String>{};
  for (final l in section.lines) {
    final t = l.tokens;
    if (t.isNotEmpty) values[t.first.toUpperCase()] = t.length > 1 ? t[1] : '';
  }
  for (final bin in section.chunksNamed('BIN')) {
    final key = bin.params.firstOrNull;
    if (key == null) continue;
    final b64 = bin.lines.map((l) => l.text.trim()).join();
    values[key.toUpperCase()] = utf8.decode(base64.decode(b64));
  }
  return values;
}
