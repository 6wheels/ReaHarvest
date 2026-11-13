import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'json_lines.dart';

/// An operation of the journal: its line number (from 0), the fix it
/// belongs to (null outside a fix) and its JSON object.
typedef _Op = ({int line, int? fix, Map<String, dynamic> json});

/// Journal of a migration (SPEC §5.8 step 5), appended to
/// `<folder>/journal.jsonl`, one line per operation, each written before
/// the operation it describes:
/// ```
/// {"op":"fixStart","fix":1,"kind":"normalizeMedia","path":"Band/Song"}
/// {"op":"move","from":"Band/Song/audio/a.wav","to":"Band/Song/Media/a.wav"}
/// {"op":"rewrite","path":"Band/Song/Song.rpp","modified":1731300000000000,"copy":".migration/<stamp>/originals/Band/Song/Song.rpp"}
/// {"op":"create","path":"Band/Song/Media/b.wav"}
/// {"op":"fixEnd","fix":1,"ok":true}
/// {"op":"undoStart","fix":2}
/// {"op":"undoEnd","fix":2}
/// ```
/// `fix` numbers the fixes of the journal from 1; `rewrite` is an existing
/// file about to be overwritten, `modified` its date before (microseconds
/// since the epoch), `copy` the raw copy of its content before; `create` a
/// file about to be written where none was. An undo of a fix (#94) is
/// between `undoStart` and `undoEnd`; the operations of a fix followed by
/// its `undoEnd` are ignored by [locate], [origin] and [rewrittenAfter].
final class MigrationJournal {
  /// An empty journal in the migration [folder]; nothing is written before
  /// the first operation.
  MigrationJournal(RepositoryStorage storage, String folder)
    : _file = JsonLinesFile(storage, '$folder/$fileName');

  MigrationJournal._(this._file);

  static const fileName = 'journal.jsonl';

  final JsonLinesFile _file;
  final _ops = <_Op>[];
  final _fixes = <int>[];
  final _paths = <int, String>{};
  final _succeeded = <int>{};
  final _undoStarted = <int>{};
  final _undone = <({int line, int fix})>[];
  int? _openFix;

  /// Caches of [_kept] and [_keptMoves], cleared by every line added.
  List<_Op>? _keptCache;
  List<(String, String)>? _movesCache;

  /// The journal of the migration [folder], empty if it has none.
  static Future<MigrationJournal> read(
    RepositoryStorage storage,
    String folder,
  ) async {
    final path = '$folder/$fileName';
    final read = await readJsonLines(storage, path);
    final journal = MigrationJournal._(
      JsonLinesFile(
        storage,
        path,
        length: read?.lines.length ?? 0,
        cut: read?.cut ?? false,
      ),
    );
    for (final (line, json) in (read?.lines ?? const []).indexed) {
      if (json != null) journal._add(line, json);
    }
    return journal;
  }

  /// Number of lines of the journal: the position of its end.
  int get length => _file.length;

  /// Appends the line [json] then takes it into account.
  Future<void> _append(Map<String, Object?> json) async {
    await _file.append([json]);
    _add(_file.length - 1, json);
  }

  void _add(int line, Map<String, dynamic> json) {
    _keptCache = null;
    _movesCache = null;
    switch (json) {
      case {'op': 'fixStart', 'fix': final int fix, 'path': final String path}:
        _fixes.add(fix);
        _paths[fix] = path;
        _openFix = fix;
      case {'op': 'fixEnd', 'fix': final int fix, 'ok': final bool ok}:
        if (ok) _succeeded.add(fix);
        _openFix = null;
      case {'op': 'undoStart', 'fix': final int fix}:
        _undoStarted.add(fix);
        _openFix = null;
      case {'op': 'undoEnd', 'fix': final int fix}:
        _undone.add((line: line, fix: fix));
      case {'op': 'move', 'from': String(), 'to': String()} ||
          {'op': 'rewrite', 'path': String(), 'modified': int()} ||
          {'op': 'create', 'path': String()}:
        _ops.add((line: line, fix: _openFix, json: json));
    }
  }

  /// Records the start of a fix of [kind] (`moveFolder`, `moveProject`,
  /// `liftProject`, `normalizeMedia`) on [path]; returns its number.
  Future<int> startFix(String kind, String path) async {
    final fix = (_fixes.lastOrNull ?? 0) + 1;
    await _append({'op': 'fixStart', 'fix': fix, 'kind': kind, 'path': path});
    return fix;
  }

  /// The last fix started, or null.
  int? get lastFix => _fixes.lastOrNull;

  /// The fix started and not ended yet, whose operations are being
  /// recorded, or null.
  int? get openFix => _openFix;

  /// Library path given to the fix [fix] when it started, or null.
  String? pathOf(int fix) => _paths[fix];

  /// Operations recorded during the fix [fix], in order: `move`, `rewrite`
  /// and `create` lines.
  List<Map<String, dynamic>> operationsOf(int fix) => [
    for (final op in _ops)
      if (op.fix == fix) op.json,
  ];

  /// Records the start of the undo of the fix [fix].
  Future<void> startUndo(int fix) => _append({'op': 'undoStart', 'fix': fix});

  /// Records the end of the undo of the fix [fix]: its operations no longer
  /// count.
  Future<void> endUndo(int fix) => _append({'op': 'undoEnd', 'fix': fix});

  /// Records the end of the fix [fix], [ok] if it completed.
  Future<void> endFix(int fix, {required bool ok}) =>
      _append({'op': 'fixEnd', 'fix': fix, 'ok': ok});

  /// Records the move of [from] (a file or a folder) to [to].
  Future<void> recordMove(String from, String to) =>
      _append({'op': 'move', 'from': from, 'to': to});

  /// Records the rewrite of the existing file [path], dated [modified],
  /// whose content before is kept in the file [copy].
  Future<void> recordRewrite(String path, DateTime modified, String copy) =>
      _append({
        'op': 'rewrite',
        'path': path,
        'modified': modified.microsecondsSinceEpoch,
        'copy': copy,
      });

  /// Records the creation of the file [path].
  Future<void> recordCreate(String path) =>
      _append({'op': 'create', 'path': path});

  bool _isUndone(int? fix) => fix != null && _undone.any((u) => u.fix == fix);

  /// Operations that still count: those of the fixes not undone.
  List<_Op> get _kept => _keptCache ??= [
    for (final op in _ops)
      if (!_isUndone(op.fix)) op,
  ];

  /// Moves of [_kept], as (from, to).
  List<(String, String)> get _keptMoves => _movesCache ??= [
    for (final op in _kept)
      if (op.json case {
        'op': 'move',
        'from': final String from,
        'to': final String to,
      })
        (from, to),
  ];

  /// Current library path of [path], following the moves of [ops].
  static String _forward(String path, Iterable<_Op> ops) {
    var current = path;
    for (final op in ops) {
      if (op.json case {
        'op': 'move',
        'from': final String from,
        'to': final String to,
      }) {
        current = _moved(current, from, to);
      }
    }
    return current;
  }

  /// [path] after the move of [from] to [to]. Called for every file and
  /// every move: the prefix is checked without building a string.
  static String _moved(String path, String from, String to) {
    if (path.length < from.length || !path.startsWith(from)) return path;
    if (path.length == from.length) return to;
    if (path.codeUnitAt(from.length) != 0x2F) return path; // '/'
    return '$to${path.substring(from.length)}';
  }

  /// Current library path of the file that was at [path] before the
  /// journal, following the recorded moves.
  String locate(String path) {
    var current = path;
    for (final (from, to) in _keptMoves) {
      current = _moved(current, from, to);
    }
    return current;
  }

  /// Path before the journal of the file now at [path] (reverse of
  /// [locate]), or null if the migration created it.
  String? origin(String path) {
    var current = path;
    for (final op in _kept.reversed) {
      switch (op.json) {
        case {'op': 'move', 'from': final String from, 'to': final String to}:
          current = _moved(current, to, from);
        case {'op': 'create', 'path': final String created}
            when created == current:
          return null;
      }
    }
    return current;
  }

  /// The last fix left to undo, or null: neither completed nor undone, or
  /// whose undo started and did not end.
  int? get unfinishedFix => _fixes.lastWhereOrNull(
    (fix) =>
        !_isUndone(fix) &&
        (!_succeeded.contains(fix) || _undoStarted.contains(fix)),
  );

  /// Current paths of the files rewritten from the line [line] on, and of
  /// those restored by an undo recorded from then on.
  Set<String> rewrittenAfter(int line) {
    final kept = _kept;
    final paths = <String>{};
    for (final (i, op) in kept.indexed) {
      if (op.line < line) continue;
      if (op.json case {'op': 'rewrite', 'path': final String path}) {
        paths.add(_forward(path, kept.skip(i + 1)));
      }
    }
    for (final undo in _undone) {
      if (undo.line < line) continue;
      final ops = [
        for (final op in _ops)
          if (op.fix == undo.fix) op,
      ];
      for (final (i, op) in ops.indexed) {
        if (op.json case {'op': 'rewrite', 'path': final String path}) {
          // Back where the fix found it, then through the moves since.
          var restored = path;
          for (final before in ops.take(i).toList().reversed) {
            if (before.json case {
              'op': 'move',
              'from': final String from,
              'to': final String to,
            }) {
              restored = _moved(restored, to, from);
            }
          }
          paths.add(
            _forward(restored, kept.where((op) => op.line > undo.line)),
          );
        }
      }
    }
    return paths;
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (final e in reversed) {
      if (test(e)) return e;
    }
    return null;
  }
}
