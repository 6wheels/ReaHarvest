import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Instant, typo-tolerant title search over tag values, version names,
/// labels and owners (SPEC §5.2). Built in memory from the index.
final class TitleSearch {
  /// [memberNames] maps owners to display names; unknown owners are
  /// searched by id.
  TitleSearch(
    Iterable<Title> titles, {
    Map<MemberId, String> memberNames = const {},
  }) : _entries = [
         for (final t in titles) (title: t, words: _wordsOf(t, memberNames)),
       ];

  final List<({Title title, List<String> words})> _entries;

  /// Titles matching every word of [query], best first; all titles, in
  /// their original order, for a blank query.
  List<Title> search(String query) {
    final tokens = _words(query);
    if (tokens.isEmpty) return [for (final e in _entries) e.title];
    final scored = <({Title title, double score, int order})>[];
    for (final (i, e) in _entries.indexed) {
      var total = 0.0;
      for (final token in tokens) {
        final best = e.words.fold(0.0, (m, w) => math.max(m, _score(token, w)));
        if (best == 0) {
          total = 0;
          break;
        }
        total += best;
      }
      if (total > 0) scored.add((title: e.title, score: total, order: i));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });
    return [for (final s in scored) s.title];
  }

  static List<String> _wordsOf(Title t, Map<MemberId, String> names) => {
    for (final value in t.tags.values) ..._words(value),
    for (final v in t.versions) ...[
      ..._words(p.withoutExtension(v.fileName)),
      if (v.metadata case final m?) ...[
        ..._words(m.label),
        if (m.owner case final owner?) ..._words(names[owner] ?? owner),
      ],
    ],
  }.toList();

  /// Match quality of a query [token] against an indexed [word]; 0 if none.
  static double _score(String token, String word) {
    if (word == token) return 4;
    if (word.startsWith(token)) return 3;
    if (word.contains(token)) return 2;
    final allowed = token.length >= 9 ? 2 : (token.length >= 4 ? 1 : 0);
    if (allowed == 0) return 0;
    // Typo in a whole word, or in the beginning of a word being typed.
    final prefix = word.length > token.length
        ? word.substring(0, token.length)
        : word;
    final distance = math.min(_distance(token, word), _distance(token, prefix));
    return distance <= allowed ? 1 : 0;
  }

  /// Optimal string alignment distance (Levenshtein with transpositions).
  static int _distance(String a, String b) {
    final d = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => i == 0 ? j : (j == 0 ? i : 0)),
    );
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = math.min(
          math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
          d[i - 1][j - 1] + cost,
        );
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          v = math.min(v, d[i - 2][j - 2] + 1);
        }
        d[i][j] = v;
      }
    }
    return d[a.length][b.length];
  }

  /// Lowercase words without diacritics.
  static List<String> _words(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final c = String.fromCharCode(rune);
      buffer.write(_folded[c] ?? c);
    }
    return buffer
        .toString()
        .split(_separator)
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static final _separator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static const _folded = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', //
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', //
    'œ': 'oe', 'æ': 'ae', 'ß': 'ss',
  };
}
