import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

/// [RepositoryStorage] over a local, mounted or provider-synchronized folder
/// (SPEC §3.0). Symbolic links are not followed.
final class MountedFolderStorage implements RepositoryStorage {
  MountedFolderStorage(this.root);

  /// Suffix of temporary files used for atomic writes.
  static const tempSuffix = '.reaharvest-tmp';

  final String root;

  String _abs(String path) =>
      path.isEmpty ? root : p.joinAll([root, ...path.split('/')]);

  String _rel(String abs) => p.split(p.relative(abs, from: root)).join('/');

  StorageEntry _entry(String path, FileStat stat) => StorageEntry(
    path: path,
    isDirectory: stat.type == FileSystemEntityType.directory,
    size: stat.size,
    modified: stat.modified,
  );

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) async {
    final entries = <StorageEntry>[];
    final stream = Directory(_abs(dir))
        .list(recursive: recursive, followLinks: false);
    await for (final e in stream) {
      if (e is Link) continue;
      final stat = await e.stat();
      if (stat.type == FileSystemEntityType.notFound) continue;
      entries.add(_entry(_rel(e.path), stat));
    }
    return entries;
  }

  @override
  Future<StorageEntry?> stat(String path) async {
    final stat = await FileStat.stat(_abs(path));
    if (stat.type == FileSystemEntityType.notFound) return null;
    return _entry(path, stat);
  }

  @override
  Stream<List<int>> read(String path) => File(_abs(path)).openRead();

  @override
  Future<void> write(String path, Stream<List<int>> content) async {
    final target = File(_abs(path));
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}$tempSuffix');
    final sink = tmp.openWrite();
    try {
      await sink.addStream(content);
      await sink.flush();
    } finally {
      await sink.close();
    }
    await tmp.rename(target.path);
  }

  @override
  Future<void> move(String from, String to) async {
    final target = _abs(to);
    if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      throw FileSystemException('Target already exists', target);
    }
    await Directory(p.dirname(target)).create(recursive: true);
    final source = _abs(from);
    if (await FileSystemEntity.isDirectory(source)) {
      await Directory(source).rename(target);
    } else {
      await File(source).rename(target);
    }
  }

  @override
  Future<void> createDirectory(String path) =>
      Directory(_abs(path)).create(recursive: true);
}
