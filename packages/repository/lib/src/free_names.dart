import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'library_path.dart';

/// [path], or the first free `name (n).ext` variant; `name (n)` for a
/// [folder], whose name has no extension.
Future<String> freePath(
  RepositoryStorage storage,
  String path, {
  bool folder = false,
}) async {
  final dir = parentOf(path);
  final name = p.posix.basename(path);
  final stem = folder ? name : p.posix.basenameWithoutExtension(path);
  final ext = folder ? '' : p.posix.extension(path);
  for (var i = 1; ; i++) {
    final candidate = i == 1 ? path : joinPath(dir, '$stem ($i)$ext');
    if (await storage.stat(candidate) == null) return candidate;
  }
}
