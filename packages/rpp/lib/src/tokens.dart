/// REAPER line tokenization and quoting rules.
///
/// A token is either bare (up to the next whitespace) or delimited by one of
/// `"`, `'` or `` ` ``, with no escape mechanism.
library;

const _quotes = {'"', "'", '`'};

bool _isSpace(int c) => c == 0x20 || c == 0x09;

/// Splits a (trimmed or untrimmed) RPP line into tokens.
List<String> tokenize(String line) {
  final tokens = <String>[];
  var i = 0;
  final n = line.length;
  while (i < n) {
    while (i < n && _isSpace(line.codeUnitAt(i))) {
      i++;
    }
    if (i >= n) break;
    final c = line[i];
    if (_quotes.contains(c)) {
      final end = line.indexOf(c, i + 1);
      if (end < 0) {
        tokens.add(line.substring(i + 1));
        break;
      }
      tokens.add(line.substring(i + 1, end));
      i = end + 1;
    } else {
      final start = i;
      while (i < n && !_isSpace(line.codeUnitAt(i))) {
        i++;
      }
      tokens.add(line.substring(start, i));
    }
  }
  return tokens;
}

/// Quotes a single-line token the way REAPER does: bare when possible, then
/// `"`, `'`, `` ` `` depending on which delimiters the value contains.
String quote(String value) {
  if (value.isEmpty) return '""';
  final needsQuotes = value.contains(
    RegExp(
      r'[\s"'
      "'`]",
    ),
  );
  if (!needsQuotes) return value;
  if (!value.contains('"')) return '"$value"';
  if (!value.contains("'")) return "'$value'";
  if (!value.contains('`')) return '`$value`';
  // All three delimiters present: REAPER degrades backticks to quotes.
  return '`${value.replaceAll('`', "'")}`';
}
