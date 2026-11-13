import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'library_path.dart';

/// [path], or the first free `name (n).ext` variant.
Future<String> freePath(RepositoryStorage storage, String path) async {
  final dir = parentOf(path);
  final stem = p.posix.basenameWithoutExtension(path);
  final ext = p.posix.extension(path);
  for (var i = 1; ; i++) {
    final candidate = i == 1 ? path : joinPath(dir, '$stem ($i)$ext');
    if (await storage.stat(candidate) == null) return candidate;
  }
}
