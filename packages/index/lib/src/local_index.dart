import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:sqlite3/sqlite3.dart' hide Version;

/// Computes the content hash of the file at [path] (relative to the library
/// root), e.g. [xxh3Hasher] (SPEC §7.1).
typedef FileHasher = Future<String> Function(String path);

/// A file tracked by the index.
typedef IndexedFile = ({String path, FileStamp stamp, String? hash});

/// An issue of a library: a [ScanResult.issues] item, or a corrupted
/// ([ReportKind.corrupted]) or orphan node ([ReportKind.orphanNode]) file.
typedef LibraryIssue = ({LibraryId library, ReportKind kind, ReportItem item});

const _schemaVersion = 10;

/// Milliseconds a writing connection waits for another writer: a library
/// write lasts a few seconds at most.
const _busyTimeout = 60000;

const _schema = '''
CREATE TABLE libraries (
  id TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  journal_folder TEXT,
  journal_line INTEGER
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
  version_labels TEXT NOT NULL,
  version_owners TEXT NOT NULL,
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
  tempo REAL,
  length REAL,
  track_count INTEGER,
  item_count INTEGER,
  plugins TEXT NOT NULL,
  media TEXT NOT NULL,
  record_path TEXT,
  render_file TEXT,
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
CREATE TABLE subprojects (
  library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  media TEXT NOT NULL,
  PRIMARY KEY (library_id, path)
);
CREATE TABLE issues (
  library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  path TEXT NOT NULL,
  detail TEXT,
  level TEXT,
  target TEXT,
  PRIMARY KEY (library_id, kind, path)
);
''';

const _tables = [
  'issues',
  'subprojects',
  'files',
  'versions',
  'titles',
  'nodes',
  'libraries',
];

/// Local SQLite index of libraries, titles, versions and file hashes
/// (SPEC §7.1, §8). It is a cache of the file system: it is rebuilt from
/// scratch when its schema changes.
final class LocalIndex {
  LocalIndex._(this._db, {bool readOnly = false}) {
    _db.execute('PRAGMA foreign_keys = ON');
    if (!readOnly && _db.userVersion != _schemaVersion) {
      _transaction(() {
        for (final t in _tables) {
          _db.execute('DROP TABLE IF EXISTS $t');
        }
        _db.execute(_schema);
        _db.userVersion = _schemaVersion;
      });
    }
  }

  /// Opens (or creates) the index database at [path], rebuilt if its schema
  /// changed. A writing connection waits for the others to finish their
  /// writes; one per isolate that writes ([scanIntoIndex]).
  ///
  /// A [readOnly] connection (the UI isolate) neither creates nor rebuilds
  /// the database ([createIndex] does it first) and fails on any write
  /// instead of blocking. Thanks to WAL, its reads never wait for a writer
  /// and see each write whole.
  factory LocalIndex.open(String path, {bool readOnly = false}) {
    if (readOnly) {
      return LocalIndex._(
        sqlite3.open(path, mode: OpenMode.readOnly),
        readOnly: true,
      );
    }
    final db = sqlite3.open(path);
    db
      ..execute('PRAGMA busy_timeout = $_busyTimeout')
      ..execute('PRAGMA journal_mode = WAL');
    return LocalIndex._(db);
  }

  factory LocalIndex.inMemory() => LocalIndex._(sqlite3.openInMemory());

  final Database _db;

  void close() => _db.close();

  /// Stores [library] and the result of its latest [scan], with the
  /// position of the migration journals it took into account. File hashes
  /// are kept for files whose stamp did not change, and cleared otherwise.
  void update(Library library, ScanResult scan) {
    final id = library.id;
    _transaction(() {
      _db.execute(
        'INSERT INTO libraries (id, json, journal_folder, journal_line) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT (id) DO UPDATE SET json = excluded.json, '
        'journal_folder = excluded.journal_folder, '
        'journal_line = excluded.journal_line',
        [
          id,
          jsonEncode(library.toJson()),
          scan.journalPosition?.folder,
          scan.journalPosition?.line,
        ],
      );
      for (final t in [
        'nodes',
        'titles',
        'versions',
        'subprojects',
        'issues',
      ]) {
        _db.execute('DELETE FROM $t WHERE library_id = ?', [id]);
      }
      _insertNodes(id, scan.nodes);
      _insertTitles(id, scan.titles, scan.nodes);
      _insertSubprojects(id, scan.subprojects);
      _insertIssues(id, scan.issues, scan.corrupted, scan.orphanNodes);
      _updateFiles(id, scan.stamps);
    });
  }

  /// Stores the result of [scanTitle] for the title folder [titlePath] of
  /// [library] (SPEC §8): its node, title and versions, and the files,
  /// subprojects and issues below its folder replace the stored ones; the
  /// issues of the folder itself (its level) are left. Duplicated version
  /// identifiers, which span titles, are then found again from the indexed
  /// versions. File hashes are kept for files whose stamp did not change.
  void updateTitle(Library library, String titlePath, TitleScan scan) {
    final id = library.id;
    final prefix = titlePath.isEmpty ? '' : '$titlePath/';
    const below = 'library_id = ?1 AND substr(path, 1, length(?2)) = ?2';
    _transaction(() {
      _db.execute('UPDATE libraries SET json = ? WHERE id = ?', [
        jsonEncode(library.toJson()),
        id,
      ]);
      for (final t in ['nodes', 'titles']) {
        _db.execute('DELETE FROM $t WHERE library_id = ? AND path = ?', [
          id,
          titlePath,
        ]);
      }
      _db.execute(
        'DELETE FROM versions WHERE library_id = ? AND title_path = ?',
        [id, titlePath],
      );
      _db.execute('DELETE FROM subprojects WHERE $below', [id, prefix]);
      _db.execute('DELETE FROM issues WHERE $below', [id, prefix]);
      final nodes = {titlePath: ?scan.node};
      _insertNodes(id, nodes);
      _insertTitles(id, [?scan.title], nodes);
      _insertSubprojects(id, scan.subprojects);
      _insertIssues(id, scan.issues, scan.corrupted, scan.orphanNodes);
      _updateFiles(id, scan.stamps, prefix: prefix);
      _db.execute('DELETE FROM issues WHERE library_id = ? AND kind = ?', [
        id,
        ReportKind.duplicateVersionId.name,
      ]);
      _insertIssues(
        id,
        Report({
          ReportKind.duplicateVersionId: [
            for (final r in _db.select(
              'SELECT title_path, file_name, version_id FROM versions '
              'WHERE library_id = ?1 AND version_id IN (SELECT version_id '
              'FROM versions WHERE library_id = ?1 AND version_id IS NOT NULL '
              'GROUP BY version_id HAVING count(*) > 1)',
              [id],
            ))
              ReportItem(
                joinPath(r['title_path'] as String, r['file_name'] as String),
                r['version_id'] as String,
              ),
          ],
        }),
        const [],
        const [],
      );
    });
  }

  void _insertNodes(LibraryId id, Map<String, NodeFile> nodes) => _insertAll(
    'INSERT INTO nodes (library_id, path, node_id, level) VALUES (?, ?, ?, ?)',
    [
      for (final e in nodes.entries) [id, e.key, e.value.id, e.value.level],
    ],
  );

  void _insertTitles(
    LibraryId id,
    List<Title> titles,
    Map<String, NodeFile> nodes,
  ) {
    _insertAll(
      'INSERT INTO titles (library_id, path, id, tags, status, '
      'version_statuses, version_labels, version_owners) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        for (final t in titles)
          [
            id,
            t.path,
            t.id,
            jsonEncode(t.tags),
            t.status,
            jsonEncode(t.versionStatuses),
            // Raw node entries: the next scan reuses them while the node
            // file is unchanged (SPEC §4.2).
            jsonEncode(nodes[t.path]?.versionLabels ?? const {}),
            jsonEncode(nodes[t.path]?.versionOwners ?? const {}),
          ],
      ],
    );
    _insertAll(
      'INSERT INTO versions (library_id, title_path, file_name, size, '
      'modified, version_id, owner, label, tempo, length, track_count, '
      'item_count, plugins, media, record_path, render_file) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        for (final t in titles)
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
              v.tempo,
              v.length,
              v.trackCount,
              v.itemCount,
              jsonEncode([for (final p in v.plugins) p.toJson()]),
              jsonEncode(v.media),
              v.recordPath,
              v.renderFile,
            ],
      ],
    );
  }

  void _insertSubprojects(
    LibraryId id,
    Map<String, List<String>> subprojects,
  ) => _insertAll(
    'INSERT INTO subprojects (library_id, path, media) VALUES (?, ?, ?)',
    [
      for (final MapEntry(:key, :value) in subprojects.entries)
        [id, key, jsonEncode(value)],
    ],
  );

  void _insertIssues(
    LibraryId id,
    Report issues,
    List<String> corrupted,
    List<String> orphanNodes,
  ) => _insertAll(
    'INSERT INTO issues (library_id, kind, path, detail, level, target) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [
      for (final (kind, items) in issues.sections)
        for (final i in items)
          [id, kind.name, i.path, i.detail, i.level?.key, i.target],
      for (final p in corrupted)
        [id, ReportKind.corrupted.name, p, null, null, null],
      for (final p in orphanNodes)
        [id, ReportKind.orphanNode.name, p, null, null, null],
    ],
  );

  /// Replaces the stamps of the files of [id] whose path starts with
  /// [prefix] by [stamps].
  void _updateFiles(
    LibraryId id,
    Map<String, FileStamp> stamps, {
    String prefix = '',
  }) {
    final existing = _stamps(id, prefix: prefix);
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

  /// Position of the migration journals taken into account by the last scan
  /// stored for [id], or null if none.
  JournalPosition? journalPosition(LibraryId id) {
    final rows = _db.select(
      'SELECT journal_folder, journal_line FROM libraries WHERE id = ?',
      [id],
    );
    return switch (rows.firstOrNull) {
      {'journal_folder': final String folder, 'journal_line': final int line} =>
        (folder: folder, line: line),
      _ => null,
    };
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
  List<Title> titles({LibraryId? library}) =>
      _snapshot(() => _titles(library: library));

  /// [titles], only the one at [path] when set (with [library]).
  List<Title> _titles({LibraryId? library, String? path}) {
    const where = 'WHERE (?1 IS NULL OR library_id = ?1)';
    final args = [library, path];
    final versions = <(String, String), List<Version>>{};
    for (final r in _db.select(
      'SELECT * FROM versions $where AND (?2 IS NULL OR title_path = ?2) '
      'ORDER BY file_name',
      args,
    )) {
      final key = (r['library_id'] as String, r['title_path'] as String);
      versions.putIfAbsent(key, () => []).add(_version(r));
    }
    return [
      for (final r in _db.select(
        'SELECT * FROM titles $where AND (?2 IS NULL OR path = ?2) '
        'ORDER BY library_id, path',
        args,
      ))
        Title(
          id: NodeId(r['id'] as String),
          libraryId: LibraryId(r['library_id'] as String),
          path: r['path'] as String,
          tags: (jsonDecode(r['tags'] as String) as Map).cast(),
          versions: versions[(r['library_id'], r['path'])] ?? const [],
          status: r['status'] as String?,
          versionStatuses: _stringMap(r['version_statuses'] as String),
        ),
    ];
  }

  /// Last scan stored for [id], with its journal position (read together),
  /// to rescan incrementally after a restart; null if the library was never
  /// indexed.
  ScanResult? scanResult(LibraryId id) => _snapshot(() => _scanResult(id));

  ScanResult? _scanResult(LibraryId id) {
    final known = _db.select('SELECT json FROM libraries WHERE id = ?', [id]);
    if (known.isEmpty) return null;
    final library = Library.fromJson(
      (jsonDecode(known.single['json'] as String) as Map).cast(),
    );
    final stored = issues(library: id);
    List<String> paths(ReportKind kind) => [
      for (final i in stored)
        if (i.kind == kind) i.item.path,
    ];
    final restored = titles(library: id);
    return ScanResult(
      titles: restored,
      nodes: _nodes(id, restored),
      issues: Report({
        for (final kind in {
          for (final i in stored) i.kind,
        }.difference({ReportKind.corrupted, ReportKind.orphanNode}))
          kind: [
            for (final i in stored)
              if (i.kind == kind) i.item,
          ],
      }),
      corrupted: paths(ReportKind.corrupted),
      orphanNodes: paths(ReportKind.orphanNode),
      stamps: _stamps(id),
      subprojects: _subprojects(id),
      freeTree: library.isFreeTree,
      journalPosition: journalPosition(id),
    );
  }

  /// The stored rows that [scanTitle] reuses for the title [titlePath] of
  /// [id]: the title, its node, and the stamps and subprojects below its
  /// folder, without loading the rest of the library (SPEC §8). Null if no
  /// such title is indexed.
  ScanResult? storedTitle(LibraryId id, String titlePath) =>
      _snapshot(() => _storedTitle(id, titlePath));

  ScanResult? _storedTitle(LibraryId id, String titlePath) {
    final title = _titles(library: id, path: titlePath).firstOrNull;
    if (title == null) return null;
    final prefix = titlePath.isEmpty ? '' : '$titlePath/';
    return ScanResult(
      titles: [title],
      nodes: _nodes(id, [title], path: titlePath),
      stamps: _stamps(id, prefix: prefix),
      subprojects: _subprojects(id, prefix: prefix),
    );
  }

  /// Stored node files of [id] (only the one at [path] when set), with the
  /// statuses of [titles] and the raw label and owner entries.
  Map<String, NodeFile> _nodes(
    LibraryId id,
    List<Title> titles, {
    String? path,
  }) {
    final byPath = {for (final t in titles) t.path: t};
    final entries = {
      for (final r in _db.select(
        'SELECT path, version_labels, version_owners FROM titles '
        'WHERE library_id = ?1 AND (?2 IS NULL OR path = ?2)',
        [id, path],
      ))
        r['path'] as String: (
          labels: _stringMap(r['version_labels'] as String),
          owners: _stringMap(r['version_owners'] as String),
        ),
    };
    return {
      for (final r in _db.select(
        'SELECT * FROM nodes WHERE library_id = ?1 AND (?2 IS NULL OR path = ?2)',
        [id, path],
      ))
        r['path'] as String: NodeFile(
          NodeId(r['node_id'] as String),
          r['level'] as String,
          status: byPath[r['path']]?.status,
          versionStatuses: byPath[r['path']]?.versionStatuses ?? const {},
          versionLabels: entries[r['path']]?.labels ?? const {},
          versionOwners: entries[r['path']]?.owners ?? const {},
        ),
    };
  }

  /// Stored stamps of the files of [id] whose path starts with [prefix].
  Map<String, FileStamp> _stamps(LibraryId id, {String prefix = ''}) => {
    for (final r in _db.select(
      'SELECT path, size, modified FROM files WHERE library_id = ?1 '
      'AND substr(path, 1, length(?2)) = ?2',
      [id, prefix],
    ))
      r['path'] as String: (
        size: r['size'] as int,
        modified: DateTime.fromMicrosecondsSinceEpoch(r['modified'] as int),
      ),
  };

  /// Stored subprojects of [id] whose path starts with [prefix].
  Map<String, List<String>> _subprojects(
    LibraryId id, {
    String prefix = '',
  }) => {
    for (final r in _db.select(
      'SELECT path, media FROM subprojects WHERE library_id = ?1 '
      'AND substr(path, 1, length(?2)) = ?2',
      [id, prefix],
    ))
      r['path'] as String: (jsonDecode(r['media'] as String) as List).cast(),
  };

  /// Issues ("To sort", SPEC §5.2) of [library], or of all libraries, of
  /// [kind] if set; sorted by library, kind (display order) then path.
  /// Expected levels carry the labels of their library's layout.
  List<LibraryIssue> issues({LibraryId? library, ReportKind? kind}) =>
      _snapshot(() => _issues(library: library, kind: kind));

  List<LibraryIssue> _issues({LibraryId? library, ReportKind? kind}) {
    final layouts = {
      for (final r in _db.select('SELECT id, json FROM libraries'))
        r['id'] as String: Library.fromJson(
          (jsonDecode(r['json'] as String) as Map).cast(),
        ).layout,
    };
    final rows = _db.select(
      'SELECT * FROM issues WHERE (?1 IS NULL OR library_id = ?1) '
      'AND (?2 IS NULL OR kind = ?2)',
      [library, kind?.name],
    );
    return [
      for (final r in rows)
        (
          library: LibraryId(r['library_id'] as String),
          kind: ReportKind.values.byName(r['kind'] as String),
          item: switch (r['level'] as String?) {
            null => ReportItem(r['path'] as String, r['detail'] as String?),
            final key => ReportItem.misplaced(
              r['path'] as String,
              level:
                  layouts[r['library_id']]?.levels
                      .where((l) => l.key == key)
                      .firstOrNull ??
                  LayoutLevel(key),
              target: r['target'] as String?,
            ),
          },
        ),
    ]..sort(
      (a, b) => switch ((
        a.library.compareTo(b.library),
        a.kind.index.compareTo(b.kind.index),
      )) {
        (0, 0) => a.item.path.compareTo(b.item.path),
        (0, final byKind) => byKind,
        (final byLibrary, _) => byLibrary,
      },
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
              owner: r['owner'] as MemberId?,
              label: r['label'] as String? ?? '',
            ),
      tempo: (r['tempo'] as num?)?.toDouble(),
      length: (r['length'] as num?)?.toDouble(),
      trackCount: r['track_count'] as int?,
      itemCount: r['item_count'] as int?,
      plugins: [
        for (final p in jsonDecode(r['plugins'] as String) as List)
          PluginRef.fromJson((p as Map).cast()),
      ],
      media: (jsonDecode(r['media'] as String) as List).cast(),
      recordPath: r['record_path'] as String?,
      renderFile: r['render_file'] as String?,
    );
  }

  static Map<String, String> _stringMap(String json) => {
    for (final e in (jsonDecode(json) as Map).entries)
      e.key as String: e.value as String,
  };

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

  /// Runs the reads of [body] on one state of the database: never a mix of
  /// the states before and after a write of another connection.
  T _snapshot<T>(T Function() body) {
    if (!_db.autocommit) return body();
    _db.execute('BEGIN');
    try {
      return body();
    } finally {
      _db.execute('COMMIT');
    }
  }

  /// Runs [body] as one write transaction, taking the write lock first (a
  /// read-then-write transaction could not wait for another writer).
  void _transaction(void Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
