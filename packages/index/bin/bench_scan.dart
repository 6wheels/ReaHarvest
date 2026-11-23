// coverage:ignore-file
// Benchmark of the scan (B2 and B3 of docs/performance.md), compiled ahead of
// time by tool/perf/bench.dart (`dart compile exe`): a measuring tool, not
// part of the application, outside the coverage gate.
//
// Usage: bench_scan <library folder> <index file>
//
// Deletes the index file, then times the first full scan (B2) and the rescan
// with no change (B3), both through `scanIntoIndex`, and counts the files the
// rescan reads. Prints one JSON line:
// `{"b2": <ms>, "b3": <ms>, "contentReads": <n>}`.

import 'dart:convert';
import 'dart:io';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

/// Storage counting the files whose content is read.
final class _CountingStorage implements RepositoryStorage {
  _CountingStorage(this._inner);

  final RepositoryStorage _inner;
  var reads = 0;

  @override
  Stream<List<int>> read(String path) {
    reads++;
    return _inner.read(path);
  }

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) =>
      _inner.list(dir, recursive: recursive);

  @override
  Future<StorageEntry?> stat(String path) => _inner.stat(path);

  @override
  Future<void> write(String path, Stream<List<int>> content) =>
      _inner.write(path, content);

  @override
  Future<void> append(String path, List<int> bytes) =>
      _inner.append(path, bytes);

  @override
  Future<void> move(String from, String to) => _inner.move(from, to);

  @override
  Future<void> createDirectory(String path) => _inner.createDirectory(path);

  @override
  Future<void> delete(String path) => _inner.delete(path);

  @override
  Future<void> setModified(String path, DateTime modified) =>
      _inner.setModified(path, modified);
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: bench_scan <library folder> <index file>');
    exitCode = 64;
    return;
  }
  final [root, indexPath] = args;
  final library = Library.fromJson(
    (jsonDecode(File('$root/.library.json').readAsStringSync()) as Map).cast(),
  );
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('$indexPath$suffix');
    if (file.existsSync()) file.deleteSync();
  }
  await createIndex(indexPath);

  final watch = Stopwatch()..start();
  await scanIntoIndex(indexPath, root, library);
  final b2 = watch.elapsedMicroseconds / 1000;

  watch
    ..reset()
    ..start();
  await scanIntoIndex(indexPath, root, library);
  final b3 = watch.elapsedMicroseconds / 1000;

  // The same rescan on a counting storage: no file content may be read.
  final index = LocalIndex.open(indexPath, readOnly: true);
  final previous = index.scanResult(library.id);
  index.close();
  final spy = _CountingStorage(MountedFolderStorage(root));
  await scan(
    spy,
    library,
    previous: previous,
    journalPosition: previous?.journalPosition,
  );

  stdout.writeln(jsonEncode({'b2': b2, 'b3': b3, 'contentReads': spy.reads}));
}
