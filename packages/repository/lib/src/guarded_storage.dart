import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'conventions.dart';
import 'free_names.dart';
import 'inventory.dart';
import 'migration_journal.dart';

/// [RepositoryStorage] given to the fixes of a migration (SPEC §5.8 step
/// 5): every move and write is recorded in the [MigrationJournal] before it
/// is made, the raw original of an inventoried file is kept before its
/// first rewrite, a rewritten project keeps its date (its version date,
/// SPEC §4.2), and nothing is deleted. Every rewrite names a copy of the
/// content it replaces, so that its fix can be undone (#94): the original
/// when it is the first rewrite of an inventoried file, else a copy under
/// `fixes/<fix>/` in the migration folder.
final class GuardedStorage implements RepositoryStorage {
  /// Requires a complete [inventory]: no change before it.
  GuardedStorage(this._inner, this._inventory, this._journal) {
    if (!_inventory.isComplete) throw StateError('Inventory not complete');
  }

  final RepositoryStorage _inner;
  final Inventory _inventory;
  final MigrationJournal _journal;

  @override
  Future<List<StorageEntry>> list(String dir, {bool recursive = false}) =>
      _inner.list(dir, recursive: recursive);

  @override
  Future<StorageEntry?> stat(String path) => _inner.stat(path);

  @override
  Stream<List<int>> read(String path) => _inner.read(path);

  @override
  Future<void> write(String path, Stream<List<int>> content) async {
    final existing = await _inner.stat(path);
    if (existing == null) {
      await _journal.recordCreate(path);
      await _inner.write(path, content);
      return;
    }
    final copy = await _keepOriginal(path) ?? await _keepCopy(path);
    await _journal.recordRewrite(path, existing.modified, copy);
    await _inner.write(path, content);
    if (isProjectFile(path)) await _inner.setModified(path, existing.modified);
  }

  /// Copies the raw file at [path] into `originals/` under its inventory
  /// path and returns the copy, unless it is not inventoried or already
  /// kept (null).
  Future<String?> _keepOriginal(String path) async {
    final origin = _journal.origin(path);
    if (origin == null || _inventory.entryOf(origin) == null) return null;
    final copy = _inventory.originalPath(origin);
    if (await _inner.stat(copy) != null) return null;
    await _inner.write(copy, _inner.read(path));
    return copy;
  }

  /// Copies the raw file at [path] under `fixes/<fix>/` (a free name) and
  /// returns the copy.
  Future<String> _keepCopy(String path) async {
    final fix = _journal.openFix ?? 0;
    final copy = await freePath(
      _inner,
      '${_inventory.folder}/fixes/$fix/$path',
    );
    await _inner.write(copy, _inner.read(path));
    return copy;
  }

  /// Allowed in `.migration/` only.
  @override
  Future<void> append(String path, List<int> bytes) async {
    if (path.split('/').first != migrationFolderName) {
      throw UnsupportedError('No append outside $migrationFolderName: $path');
    }
    await _inner.append(path, bytes);
  }

  @override
  Future<void> setModified(String path, DateTime modified) =>
      _inner.setModified(path, modified);

  /// Refused before it is recorded when [from] is missing or [to] exists:
  /// a recorded move then leaves [to] present and [from] absent only if it
  /// was made, which its undo relies on.
  @override
  Future<void> move(String from, String to) async {
    if (await _inner.stat(from) == null) {
      throw StateError('No source to move: $from');
    }
    if (await _inner.stat(to) != null) {
      throw StateError('Move target exists: $to');
    }
    await _journal.recordMove(from, to);
    await _inner.move(from, to);
  }

  @override
  Future<void> createDirectory(String path) => _inner.createDirectory(path);

  @override
  Future<void> delete(String path) async =>
      throw UnsupportedError('No file is deleted during a migration: $path');
}
