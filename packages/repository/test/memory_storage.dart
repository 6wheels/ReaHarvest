import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Failure thrown by [MemoryStorage] at the change chosen by
/// [MemoryStorage.failAt].
final class InjectedFailure implements Exception {
  const InjectedFailure(this.operation);

  final String operation;

  @override
  String toString() => 'Injected failure: $operation';
}

/// In-memory [RepositoryStorage]: a tree of files and folders, the log of
/// its changes and a failure injected at the n-th change.
final class MemoryStorage implements RepositoryStorage {
  final files = <String, ({List<int> bytes, DateTime modified})>{};
  final dirs = <String>{};

  /// Changes made, in order: `write a`, `append a`, `move a b`,
  /// `createDirectory a`, `delete a`, `setModified a`.
  final log = <String>[];

  /// Bytes passed to [write] and [append].
  int bytesWritten = 0;

  /// Paths read, in order (when their reading starts).
  final reads = <String>[];

  /// Folders listed, in order, recursive ones suffixed with `/**`.
  final listed = <String>[];

  /// Paths passed to [stat], in order.
  final stats = <String>[];

  /// Largest number of project files read at the same time.
  int maxOpenProjectReads = 0;

  var _openProjectReads = 0;

  /// Number (from 1) of the change that throws an [InjectedFailure]
  /// instead of being made; null for none.
  int? failAt;

  /// Whether every change from [failAt] on throws: the drive is gone, or
  /// the application stopped (no line written after the failure).
  bool failAfter = false;

  /// Share of its bytes (0.5: the first half, 1: all) that a failing
  /// [append] writes before throwing, as a write cut by the failure or one
  /// failing at its flush; null: none.
  double? appendedOnFailure;

  var _changes = 0;

  /// Number of changes asked so far, the failed one included.
  int get changes => _changes;

  /// Date given to the files written: one second later at each change.
  DateTime get _now => DateTime(2026).add(Duration(seconds: _changes));

  /// Writes the text [content] at [path], outside the log.
  void put(String path, String content, {DateTime? modified}) {
    _addParents(path);
    files[path] = (
      bytes: [...utf8.encode(content)],
      modified: modified ?? _now,
    );
  }

  /// Text of the file [path].
  String text(String path) => utf8.decode(files[path]!.bytes);

  /// The first change that threw (cleared by the tests).
  String? failed;

  void _change(String operation) {
    if (_fails(++_changes)) {
      failed ??= operation;
      throw InjectedFailure(operation);
    }
    log.add(operation);
  }

  bool _fails(int change) =>
      failAt != null && (change == failAt || (failAfter && change > failAt!));

  void _addParents(String path) {
    final segments = path.split('/');
    for (var i = 1; i < segments.length; i++) {
      dirs.add(segments.sublist(0, i).join('/'));
    }
  }

  static bool _below(String path, String dir) =>
      dir.isEmpty || path.startsWith('$dir/');

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) async {
    this.listed.add(recursive ? '$dir/**' : dir);
    bool listed(String path) =>
        _below(path, dir) &&
        (recursive ||
            !path.substring(dir.isEmpty ? 0 : dir.length + 1).contains('/'));
    return [
      for (final d in dirs)
        if (listed(d))
          StorageEntry(
            path: d,
            isDirectory: true,
            size: 0,
            modified: DateTime(2026),
          ),
      for (final MapEntry(key: path, value: f) in files.entries)
        if (listed(path))
          StorageEntry(
            path: path,
            isDirectory: false,
            size: f.bytes.length,
            modified: f.modified,
          ),
    ];
  }

  @override
  Future<StorageEntry?> stat(String path) async {
    stats.add(path);
    if (dirs.contains(path)) {
      return StorageEntry(
        path: path,
        isDirectory: true,
        size: 0,
        modified: DateTime(2026),
      );
    }
    final f = files[path];
    if (f == null) return null;
    return StorageEntry(
      path: path,
      isDirectory: false,
      size: f.bytes.length,
      modified: f.modified,
    );
  }

  @override
  Stream<List<int>> read(String path) async* {
    final f = files[path];
    if (f == null) throw StateError('No file $path');
    reads.add(path);
    final project = path.toLowerCase().endsWith('.rpp');
    if (project && ++_openProjectReads > maxOpenProjectReads) {
      maxOpenProjectReads = _openProjectReads;
    }
    try {
      yield f.bytes;
    } finally {
      if (project) _openProjectReads--;
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> content) async {
    final bytes = [await for (final chunk in content) ...chunk];
    _change('write $path');
    bytesWritten += bytes.length;
    _addParents(path);
    files[path] = (bytes: bytes, modified: _now);
  }

  @override
  Future<void> append(String path, List<int> bytes) async {
    if (appendedOnFailure case final share? when _fails(_changes + 1)) {
      _addParents(path);
      files[path] = (
        bytes: [
          ...?files[path]?.bytes,
          ...bytes.take((bytes.length * share).floor()),
        ],
        modified: _now,
      );
    }
    _change('append $path');
    bytesWritten += bytes.length;
    _addParents(path);
    // In place: appending stays linear.
    files[path] = (
      bytes: (files[path]?.bytes ?? <int>[])..addAll(bytes),
      modified: _now,
    );
  }

  @override
  Future<void> move(String from, String to) async {
    if (await stat(to) != null) throw StateError('Target exists: $to');
    if (await stat(from) == null) throw StateError('No source: $from');
    _change('move $from $to');
    _addParents(to);
    String moved(String path) =>
        path == from ? to : '$to${path.substring(from.length)}';
    bool inside(String path) => path == from || path.startsWith('$from/');
    for (final d in dirs.where(inside).toList()) {
      dirs
        ..remove(d)
        ..add(moved(d));
    }
    for (final path in files.keys.where(inside).toList()) {
      files[moved(path)] = files.remove(path)!;
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    _change('createDirectory $path');
    _addParents(path);
    dirs.add(path);
  }

  @override
  Future<void> delete(String path) async {
    _change('delete $path');
    files.remove(path);
  }

  @override
  Future<void> setModified(String path, DateTime modified) async {
    _change('setModified $path');
    files[path] = (bytes: files[path]!.bytes, modified: modified);
  }
}
