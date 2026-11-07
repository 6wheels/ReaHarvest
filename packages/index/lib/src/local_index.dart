import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:sqlite3/sqlite3.dart' hide Version;

/// Computes the content hash of the file at [path] (relative to the library
/// root), e.g. [xxh3Hasher] (SPEC §7.1).
typedef FileHasher = Future<String> Function(String path);

/// A file tracked by the index.
typedef IndexedFile = ({String path, FileStamp stamp, String? hash});

const _schemaVersion = 2;

const _schema = '''
CREATE TABLE libraries (
  id TEXT PRIMARY KEY,
  json TEXT NOT NULL
);
CREATE TABLE nodes (
  library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  node_id TEXT NOT NULL,
  level TEXT NOT NULL,
  PRIMARY KEY (library_id, path)
);
CREATE TABLE titles (
  library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  id TEXT NOT NULL,
  tags TEXT NOT NULL,
  status TEXT,
  version_statuses TEXT NOT NULL,
  PRIMARY KEY (library_id, path)
);
CREATE TABLE versions (
  library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  title_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  size INTEGER NOT NULL,
  modified INTEGER NOT NULL,
  version_id TEXT,
  owner TEXT,
  label TEXT,
  PRIMARY KEY (library_id, title_path, file_name)
);
CREATE TABLE files (
  library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  size INTEGER NOT NULL,
  modified INTEGER NOT NULL,
  hash TEXT,
  PRIMARY KEY (library_id, path)
);
CREATE TABLE issues (
  library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('toSort', 'corrupted')),
  path TEXT NOT NULL,
  PRIMARY KEY (library_id, kind, path)
);
''';

const _tables = ['issues', 'files', 'versions', 'titles', 'nodes', 'libraries'];

/// Local SQLite index of libraries, titles, versions and file hashes
/// (SPEC §7.1, §8). It is a cache of the file system: it is rebuilt from
/// scratch when its schema changes.
final class LocalIndex {
  LocalIndex._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    if (_db.userVersion != _schemaVersion) {
      _transaction(() {
        for (final t in _tables) {
          _db.execute('DROP TABLE IF EXISTS $t');
        }
        _db.execute(_schema);
        _db.userVersion = _schemaVersion;
      });
    }
  }

  /// Opens (or creates) the index database at [path].
  factory LocalIndex.open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL');
    return LocalIndex._(db);
  }

  factory LocalIndex.inMemory() => LocalIndex._(sqlite3.openInMemory());

  final Database _db;

  void close() => _db.close();

  /// Stores [library] and the result of its latest [scan]. File hashes are
  /// kept for files whose stamp did not change, and cleared otherwise.
  void update(Library library, ScanResult scan) {
    final id = library.id;
    _transaction(() {
      _db.execute(
        'INSERT INTO libraries (id, json) VALUES (?, ?) '
        'ON CONFLICT (id) DO UPDATE SET json = excluded.json',
        [id, jsonEncode(library.toJson())],
      );
      for (final t in ['nodes', 'titles', 'versions', 'issues']) {
        _db.execute('DELETE FROM $t WHERE library_id = ?', [id]);
      }
      _insertAll(
        'INSERT INTO nodes (library_id, path, node_id, level) '
        'VALUES (?, ?, ?, ?)',
        [
          for (final e in scan.nodes.entries)
            [id, e.key, e.value.id, e.value.level],
        ],
      );
      _insertAll(
        'INSERT INTO titles (library_id, path, id, tags, status, '
        'version_statuses) VALUES (?, ?, ?, ?, ?, ?)',
        [
          for (final t in scan.titles)
            [
              id,
              t.path,
              t.id,
              jsonEncode(t.tags),
              t.status,
              jsonEncode(t.versionStatuses),
            ],
        ],
      );
      _insertAll(
        'INSERT INTO versions (library_id, title_path, file_name, size, '
        'modified, version_id, owner, label) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          for (final t in scan.titles)
            for (final v in t.versions)
              [
                id,
                t.path,
                v.fileName,
                v.size,
                v.modified.microsecondsSinceEpoch,
                v.metadata?.id,
                v.metadata?.owner,
                v.metadata?.label,
              ],
        ],
      );
      _insertAll(
        'INSERT INTO issues (library_id, kind, path) VALUES (?, ?, ?)',
        [
          for (final p in scan.toSort) [id, 'toSort', p],
          for (final p in scan.corrupted) [id, 'corrupted', p],
        ],
      );
      _updateFiles(id, scan.stamps);
    });
  }

  void _updateFiles(LibraryId id, Map<String, FileStamp> stamps) {
    final existing = {for (final f in files(id)) f.path: f.stamp};
    final upsert = _db.prepare(
      'INSERT INTO files (library_id, path, size, modified) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (library_id, path) DO UPDATE SET size = excluded.size, '
      'modified = excluded.modified, hash = NULL',
    );
    final delete = _db.prepare(
      'DELETE FROM files WHERE library_id = ? AND path = ?',
    );
    try {
      for (final e in stamps.entries) {
        if (existing.remove(e.key) == e.value) continue;
        upsert.execute([
          id,
          e.key,
          e.value.size,
          e.value.modified.microsecondsSinceEpoch,
        ]);
      }
      for (final path in existing.keys) {
        delete.execute([id, path]);
      }
    } finally {
      upsert.close();
      delete.close();
    }
  }

  /// Removes [id] and everything indexed for it.
  void removeLibrary(LibraryId id) =>
      _db.execute('DELETE FROM libraries WHERE id = ?', [id]);

  /// Indexed libraries.
  List<Library> libraries() => [
    for (final r in _db.select('SELECT json FROM libraries ORDER BY id'))
      Library.fromJson((jsonDecode(r['json'] as String) as Map).cast()),
  ];

  /// Titles of all libraries (or of [library]), sorted by library then path,
  /// with their versions: the startup view (SPEC §8).
  List<Title> titles({LibraryId? library}) {
    final where = library == null ? '' : 'WHERE library_id = ?';
    final args = [?library];
    final versions = <(String, String), List<Version>>{};
    for (final r in _db.select(
      'SELECT * FROM versions $where ORDER BY file_name',
      args,
    )) {
      final key = (r['library_id'] as String, r['title_path'] as String);
      versions.putIfAbsent(key, () => []).add(_version(r));
    }
    return [
      for (final r in _db.select(
        'SELECT * FROM titles $where ORDER BY library_id, path',
        args,
      ))
        Title(
          id: NodeId(r['id'] as String),
          libraryId: LibraryId(r['library_id'] as String),
          path: r['path'] as String,
          tags: (jsonDecode(r['tags'] as String) as Map).cast(),
          versions: versions[(r['library_id'], r['path'])] ?? const [],
          status: r['status'] as String?,
          versionStatuses: {
            for (final e
                in (jsonDecode(r['version_statuses'] as String) as Map).entries)
              e.key as String: e.value as String,
          },
        ),
    ];
  }

  /// Last scan stored for [id], to rescan incrementally after a restart;
  /// null if the library was never indexed.
  ScanResult? scanResult(LibraryId id) {
    final known = _db.select('SELECT json FROM libraries WHERE id = ?', [id]);
    if (known.isEmpty) return null;
    final library = Library.fromJson(
      (jsonDecode(known.single['json'] as String) as Map).cast(),
    );
    List<String> issues(String kind) => [
      for (final r in _db.select(
        'SELECT path FROM issues WHERE library_id = ? AND kind = ? '
        'ORDER BY path',
        [id, kind],
      ))
        r['path'] as String,
    ];
    final restored = titles(library: id);
    final byPath = {for (final t in restored) t.path: t};
    return ScanResult(
      titles: restored,
      nodes: {
        for (final r in _db.select('SELECT * FROM nodes WHERE library_id = ?', [
          id,
        ]))
          r['path'] as String: NodeFile(
            NodeId(r['node_id'] as String),
            r['level'] as String,
            status: byPath[r['path']]?.status,
            versionStatuses: byPath[r['path']]?.versionStatuses ?? const {},
          ),
      },
      toSort: issues('toSort'),
      corrupted: issues('corrupted'),
      stamps: {for (final f in files(id)) f.path: f.stamp},
      freeTree: library.isFreeTree,
    );
  }

  /// Stored hash of [path], or null if not computed yet.
  String? hashOf(LibraryId id, String path) {
    final rows = _db.select(
      'SELECT hash FROM files WHERE library_id = ? AND path = ?',
      [id, path],
    );
    return rows.isEmpty ? null : rows.first['hash'] as String?;
  }

  /// Stores the [hash] of [path] computed for [stamp]. Ignored if the file
  /// is no longer indexed with that stamp (changed since). Returns whether
  /// the hash was stored.
  bool setHash(LibraryId id, String path, FileStamp stamp, String hash) {
    _db.execute(
      'UPDATE files SET hash = ? '
      'WHERE library_id = ? AND path = ? AND size = ? AND modified = ?',
      [hash, id, path, stamp.size, stamp.modified.microsecondsSinceEpoch],
    );
    return _db.updatedRows > 0;
  }

  /// Hashes every unhashed file of [id] with [hasher] (which should run in
  /// an isolate), storing each hash as soon as it is computed. Returns the
  /// number of hashes stored.
  Future<int> hashPending(LibraryId id, FileHasher hasher) async {
    var count = 0;
    for (final f in files(id, unhashedOnly: true)) {
      final hash = await hasher(f.path);
      if (setHash(id, f.path, f.stamp, hash)) count++;
    }
    return count;
  }

  /// Files of [id] (only those without a hash, new or changed, if
  /// [unhashedOnly]), sorted by path so that the files of a title are
  /// processed together.
  List<IndexedFile> files(LibraryId id, {bool unhashedOnly = false}) => [
    for (final r in _db.select(
      'SELECT path, size, modified, hash FROM files WHERE library_id = ? '
      '${unhashedOnly ? 'AND hash IS NULL ' : ''}ORDER BY path',
      [id],
    ))
      (
        path: r['path'] as String,
        stamp: (
          size: r['size'] as int,
          modified: DateTime.fromMicrosecondsSinceEpoch(r['modified'] as int),
        ),
        hash: r['hash'] as String?,
      ),
  ];

  static Version _version(Row r) {
    final versionId = r['version_id'] as String?;
    return Version(
      fileName: r['file_name'] as String,
      modified: DateTime.fromMicrosecondsSinceEpoch(r['modified'] as int),
      size: r['size'] as int,
      metadata: versionId == null
          ? null
          : VersionMetadata(
              id: VersionId(versionId),
              owner: MemberId(r['owner'] as String),
              label: r['label'] as String? ?? '',
            ),
    );
  }

  void _insertAll(String sql, List<List<Object?>> rows) {
    final statement = _db.prepare(sql);
    try {
      for (final row in rows) {
        statement.execute(row);
      }
    } finally {
      statement.close();
    }
  }

  void _transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
