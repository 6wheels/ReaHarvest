import 'tokens.dart';

/// A non-chunk line inside a chunk, e.g. `TEMPO 120 4 4`.
class RppLine {
  RppLine(this.index, this.text);

  /// Zero-based line index in the source text.
  final int index;

  /// Line content without leading indentation.
  final String text;

  List<String>? _tokens;

  List<String> get tokens => _tokens ??= tokenize(text);

  /// First token (attribute name), or the raw text for content lines.
  String get name => tokens.isEmpty ? '' : tokens.first;

  /// Tokens after the attribute name.
  List<String> get params => tokens.length <= 1 ? const [] : tokens.sublist(1);
}

/// A `<NAME params…` … `>` block.
class RppChunk {
  RppChunk(this.name, this.params, this.start);

  final String name;
  final List<String> params;

  /// Line index of the opening `<NAME` line.
  final int start;

  /// Line index of the closing `>` line.
  int end = -1;

  final List<RppChunk> chunks = [];
  final List<RppLine> lines = [];

  /// First direct child line whose name is [name].
  RppLine? line(String name) {
    for (final l in lines) {
      if (l.name == name) return l;
    }
    return null;
  }

  /// First direct child chunk named [name].
  RppChunk? chunk(String name) {
    for (final c in chunks) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Direct child chunks named [name].
  Iterable<RppChunk> chunksNamed(String name) =>
      chunks.where((c) => c.name == name);
}

/// Parsed RPP text: source lines plus the chunk tree rooted at
/// `<REAPER_PROJECT` (or `<REAPER_TRACK` templates, or any root chunk).
class RppDocument {
  RppDocument._(this.lines, this.newline, this.root);

  /// Raw source lines split on `\n` (a trailing `\r` is kept), so that
  /// `lines.join('\n')` restores the exact source.
  final List<String> lines;

  /// Line terminator to use for inserted lines (`\r\n` or `\n`).
  final String newline;

  final RppChunk root;

  factory RppDocument.parse(String text) {
    final newline = text.contains('\r\n') ? '\r\n' : '\n';
    final lines = text.split('\n');

    RppChunk? root;
    final stack = <RppChunk>[];
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isEmpty) continue;
      if (t.startsWith('<')) {
        final tokens = tokenize(t.substring(1));
        final chunk = RppChunk(
          tokens.isEmpty ? '' : tokens.first,
          tokens.length <= 1 ? const [] : tokens.sublist(1),
          i,
        );
        if (stack.isEmpty) {
          if (root != null) break; // ignore trailing content
          root = chunk;
        } else {
          stack.last.chunks.add(chunk);
        }
        stack.add(chunk);
      } else if (t == '>' || t.startsWith('> ')) {
        if (stack.isEmpty) {
          throw const FormatException('Unbalanced ">" in RPP');
        }
        stack.removeLast().end = i;
      } else if (stack.isNotEmpty) {
        // Keep trailing spaces (meaningful in NOTES), drop only the CR.
        var raw = lines[i].trimLeft();
        if (raw.endsWith('\r')) raw = raw.substring(0, raw.length - 1);
        stack.last.lines.add(RppLine(i, raw));
      }
    }
    if (root == null) throw const FormatException('No root chunk in RPP');
    if (stack.isNotEmpty) throw const FormatException('Unclosed chunk in RPP');
    return RppDocument._(lines, newline, root);
  }

  /// Exact source text.
  String get text => lines.join('\n');
}
