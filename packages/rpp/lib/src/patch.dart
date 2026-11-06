import 'dart:convert';

import 'ext_state.dart';
import 'tokens.dart';
import 'tree.dart';

/// Targeted text patches on RPP source. Every function returns the new text;
/// lines outside the patched range are kept byte-for-byte.

/// Sets a root-level attribute line (e.g. `TITLE`, `AUTHOR`, `RECORD_PATH`).
/// Replaces the existing line, or inserts it right after the root header.
String setRootAttribute(String text, String name, List<String> params) {
  final doc = RppDocument.parse(text);
  final lines = doc.lines;
  final indent = _indent(1);
  final eol = doc.newline == '\r\n' ? '\r' : '';
  final content = [name, ...params.map(quote)].join(' ');
  final existing = doc.root.line(name);
  if (existing != null) {
    final old = lines[existing.index];
    final lead = old.substring(0, old.length - old.trimLeft().length);
    lines[existing.index] = '$lead$content${old.endsWith('\r') ? '\r' : ''}';
  } else {
    lines.insert(doc.root.start + 1, '$indent$content$eol');
  }
  return lines.join('\n');
}

/// Merges [values] into the `EXTSTATE` section [section]. A null or empty
/// value removes the key. Keys are upper-cased and sorted like REAPER does.
/// Only the section block is rewritten; it is created when missing.
String setExtState(String text, String section, Map<String, String?> values) {
  final doc = RppDocument.parse(text);
  final lines = doc.lines;
  final eol = doc.newline == '\r\n' ? '\r' : '';
  final sectionName = section.toUpperCase();

  final extState = doc.root.chunk('EXTSTATE');
  final current = extState?.chunk(sectionName);

  final merged = current == null
      ? <String, String>{}
      : Map.of(readExtStateSection(current));
  values.forEach((k, v) {
    if (v == null || v.isEmpty) {
      merged.remove(k.toUpperCase());
    } else {
      merged[k.toUpperCase()] = v;
    }
  });

  final block = merged.isEmpty
      ? <String>[]
      : _sectionBlock(sectionName, merged, depth: 2, eol: eol);

  if (current != null) {
    lines.replaceRange(current.start, current.end + 1, block);
  } else if (block.isEmpty) {
    return text;
  } else if (extState != null) {
    lines.insertAll(extState.end, block);
  } else {
    lines.insertAll(doc.root.end, [
      '${_indent(1)}<EXTSTATE$eol',
      ...block,
      '${_indent(1)}>$eol',
    ]);
  }
  return lines.join('\n');
}

List<String> _sectionBlock(
  String name,
  Map<String, String> values, {
  required int depth,
  required String eol,
}) {
  final i0 = _indent(depth);
  final i1 = _indent(depth + 1);
  final i2 = _indent(depth + 2);
  final out = ['$i0<$name$eol'];
  for (final key in values.keys.toList()..sort()) {
    final v = values[key]!;
    if (v.contains('"') || v.contains('\n') || v.contains('\r')) {
      out.add('$i1<BIN $key$eol');
      final b64 = base64.encode(utf8.encode(v));
      for (var i = 0; i < b64.length; i += 128) {
        final end = i + 128 < b64.length ? i + 128 : b64.length;
        out.add('$i2${b64.substring(i, end)}$eol');
      }
      out.add('$i1>$eol');
    } else {
      out.add('$i1$key ${quote(v)}$eol');
    }
  }
  out.add('$i0>$eol');
  return out;
}

String _indent(int depth) => '  ' * depth;
