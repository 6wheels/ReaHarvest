import 'hlc.dart';
import 'ids.dart';

/// File or folder in a repository.
final class StorageEntry {
  const StorageEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  /// Path relative to the repository root, `/`-separated.
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
}

/// Access to a library repository (SPEC §3.0). Paths are relative to the
/// repository root and `/`-separated. Implementations must not read file
/// contents unless asked (on-demand cloud files).
abstract interface class RepositoryStorage {
  /// Entries of [dir] (`''` for the root), recursively if [recursive].
  Future<List<StorageEntry>> list(String dir, {bool recursive = false});

  /// Entry at [path], or null if absent.
  Future<StorageEntry?> stat(String path);

  Stream<List<int>> read(String path);

  /// Writes [path] atomically (temporary file, then rename), creating
  /// parent folders.
  Future<void> write(String path, Stream<List<int>> content);

  /// Moves [from] to [to] (e.g. to `.trash/` or `.history/`).
  Future<void> move(String from, String to);

  Future<void> createDirectory(String path);
}

/// Entity types of the canonical collab model (SPEC §6.2).
enum CollabEntity {
  member,
  titleMeta,
  versionMeta,
  task,
  note,
  lyrics,
  asset,
  activity,
}

/// A canonical collab record (SPEC §6.2).
final class CollabRecord {
  const CollabRecord({
    required this.uid,
    required this.groupId,
    required this.libraryId,
    required this.entity,
    required this.author,
    required this.hlc,
    this.deleted = false,
    this.fields = const {},
  });

  /// Client-generated ULID; canonical identity.
  final String uid;
  final GroupId groupId;
  final LibraryId libraryId;
  final CollabEntity entity;
  final MemberId author;

  /// Timestamp of the last write.
  final Hlc hlc;

  /// Tombstone.
  final bool deleted;

  /// Entity-specific fields (JSON values).
  final Map<String, Object?> fields;
}

/// Record selection: [entity] if set, and every [fields] value equal.
final class CollabFilter {
  const CollabFilter({this.entity, this.fields = const {}});

  final CollabEntity? entity;
  final Map<String, Object?> fields;

  bool matches(CollabRecord record) =>
      (entity == null || record.entity == entity) &&
      fields.entries.every((e) => record.fields[e.key] == e.value);
}

/// Full store content, used to switch store implementations.
final class CanonicalExport {
  const CanonicalExport(this.records);

  final List<CollabRecord> records;
}

/// Shared collab data store (SPEC §6). Conflicts are resolved per field,
/// last writer wins, ordered by HLC then author.
abstract interface class CollabStore {
  Future<void> upsert(
    CollabEntity entity,
    String uid,
    Map<String, Object?> fields,
  );

  Future<void> delete(CollabEntity entity, String uid);

  Future<List<CollabRecord>> query(
    CollabEntity entity, [
    CollabFilter filter = const CollabFilter(),
  ]);

  /// Changed records matching [filter].
  Stream<CollabRecord> subscribe([CollabFilter filter = const CollabFilter()]);

  Future<CanonicalExport> exportAll();

  /// Idempotent upsert by uid, LWW applied.
  Future<void> importAll(CanonicalExport export);
}
