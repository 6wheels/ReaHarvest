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

/// Sets the project notes (`<NOTES` chunk, one `|line` per note line).
/// An existing chunk keeps its header; a missing one is created after
/// `TITLE`/`AUTHOR`. Null or empty notes leave an empty chunk.
String setNotes(String text, String? notes) {
  final doc = RppDocument.parse(text);
  final lines = doc.lines;
  final eol = doc.newline == '\r\n' ? '\r' : '';
  final content = (notes == null || notes.isEmpty)
      ? <String>[]
      : notes
            .replaceAll('\r\n', '\n')
            .split('\n')
            .map((l) => '${_indent(2)}|$l$eol')
            .toList();

  final current = doc.root.chunk('NOTES');
  if (current != null) {
    lines.replaceRange(current.start + 1, current.end, content);
  } else {
    if (content.isEmpty) return text;
    final after = [
      doc.root.line('TITLE'),
      doc.root.line('AUTHOR'),
    ].nonNulls.fold(doc.root.start, (i, l) => l.index > i ? l.index : i);
    lines.insertAll(after + 1, [
      '${_indent(1)}<NOTES 0 2$eol',
      ...content,
      '${_indent(1)}>$eol',
    ]);
  }
  return lines.join('\n');
}

/// Merges [tags] into the `<RENDER_METADATA` chunk. Keys are
/// `SCHEMA:FIELD` (e.g. `ID3:TIT2`), values may use REAPER wildcards
/// (`$title`). A null or empty value removes the tag. Tags are sorted like
/// REAPER does; the chunk is removed when empty, and created after the last
/// root-level `RENDER_*` line when missing. When tags remain, metadata
/// embedding is enabled in the render settings.
String setRenderMetadata(String text, Map<String, String?> tags) {
  final doc = RppDocument.parse(text);
  final lines = doc.lines;
  final eol = doc.newline == '\r\n' ? '\r' : '';

  final current = doc.root.chunk('RENDER_METADATA');
  final merged = <String, String>{
    if (current != null)
      for (final l in current.lines)
        if (l.name == 'TAG' && l.params.isNotEmpty)
          l.params[0]: l.params.length > 1 ? l.params[1] : '',
  };
  tags.forEach((k, v) {
    if (v == null || v.isEmpty) {
      merged.remove(k);
    } else {
      merged[k] = v;
    }
  });

  final block = merged.isEmpty
      ? <String>[]
      : [
          '${_indent(1)}<RENDER_METADATA$eol',
          for (final k in merged.keys.toList()..sort())
            '${_indent(2)}TAG ${quote(k)} ${quote(merged[k]!)}$eol',
          '${_indent(1)}>$eol',
        ];

  if (current != null) {
    lines.replaceRange(current.start, current.end + 1, block);
  } else if (block.isEmpty) {
    return text;
  } else {
    final lastRender = doc.root.lines
        .where((l) => l.name.startsWith('RENDER_'))
        .lastOrNull;
    lines.insertAll(
      lastRender == null ? doc.root.end : lastRender.index + 1,
      block,
    );
  }
  final out = lines.join('\n');
  return merged.isEmpty ? out : _enableEmbedMetadata(out);
}

/// Render dialog "Metadata" checkbox: bit 512 of `RENDER_STEMS`.
const _embedMetadataFlag = 512;

String _enableEmbedMetadata(String text) {
  final params = RppDocument.parse(text).root.line('RENDER_STEMS')?.params;
  final flags = int.tryParse(params?.firstOrNull ?? '') ?? 0;
  if (flags & _embedMetadataFlag != 0) return text;
  return setRootAttribute(text, 'RENDER_STEMS', [
    '${flags | _embedMetadataFlag}',
    ...?params?.skip(1),
  ]);
}

/// Rewrites media references (`FILE` lines of `SOURCE` chunks, at any
/// depth). [map] receives each path as written and returns the new one;
/// lines whose path is unchanged are kept byte-for-byte, and the tokens after
/// the path (e.g. `QN` on MIDI sources) are preserved.
String rewriteMediaPaths(String text, String Function(String path) map) {
  final doc = RppDocument.parse(text);
  final lines = doc.lines;
  var changed = false;

  void visit(RppChunk c) {
    if (c.name == 'SOURCE') {
      for (final l in c.lines) {
        if (l.name != 'FILE' || l.params.isEmpty) continue;
        final path = l.params.first;
        final newPath = map(path);
        if (newPath == path) continue;
        final old = lines[l.index];
        final lead = old.substring(0, old.length - old.trimLeft().length);
        final rest = l.params.skip(1).map(quote);
        // REAPER always double-quotes media paths.
        final q = newPath.contains('"') ? quote(newPath) : '"$newPath"';
        lines[l.index] =
            '$lead${['FILE', q, ...rest].join(' ')}'
            '${old.endsWith('\r') ? '\r' : ''}';
        changed = true;
      }
    }
    c.chunks.forEach(visit);
  }

  visit(doc.root);
  return changed ? lines.join('\n') : text;
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
