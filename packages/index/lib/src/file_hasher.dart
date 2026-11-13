import 'dart:isolate';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart' show xxh3Hash;

import 'local_index.dart';

export 'package:reaharvest_repository/reaharvest_repository.dart' show xxh3Hash;

/// [FileHasher] hashing files of [storage] with [xxh3Hash], each in a
/// background isolate. [storage] must be sendable to an isolate.
FileHasher xxh3Hasher(RepositoryStorage storage) =>
    (path) => Isolate.run(() => xxh3Hash(storage.read(path)));
