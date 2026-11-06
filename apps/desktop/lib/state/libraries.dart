import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'providers.dart';

/// Why a folder cannot become a library.
enum LibraryProblem {
  /// The folder holds a cloud or collab library (milestone B).
  unsupportedMode,

  /// The folder is, contains or is inside a folder of another library.
  overlap,

  /// The folder holds an unreadable `_library.json`.
  invalidFile,
}

final class LibraryException implements Exception {
  const LibraryException(this.problem);

  final LibraryProblem problem;

  @override
  String toString() => 'LibraryException($problem)';
}

/// Library operations: creation or attachment, removal, and scanning into
/// the local index (SPEC §5.1, §8).
class LibraryService {
  LibraryService(this.ref);

  final Ref ref;

  /// Library already described in [folder] (`_library.json`), or null.
  /// Throws [LibraryException] if the file is unreadable.
  Future<Library?> existing(String folder) async {
    try {
      return await readLibrary(MountedFolderStorage(folder));
    } on FormatException {
      throw const LibraryException(LibraryProblem.invalidFile);
    } on TypeError {
      throw const LibraryException(LibraryProblem.invalidFile);
    }
  }

  /// Adds the local library at [folder] with [layout] (null: free tree):
  /// attaches the library already described there (keeping its id, and
  /// replacing its layout if it differs), or creates it. Then scans it.
  /// Throws [LibraryException].
  Future<void> addLocal({
    required String folder,
    required String displayName,
    required Layout? layout,
  }) async {
    final found = await existing(folder);
    if (found != null && found.mode != LibraryMode.local) {
      throw const LibraryException(LibraryProblem.unsupportedMode);
    }
    final library = Library(
      id: found?.id ?? LibraryId.generate(),
      mode: LibraryMode.local,
      layout: layout,
    );
    final entry = LibraryEntry(
      id: library.id,
      displayName: displayName.trim().isEmpty
          ? p.basename(folder)
          : displayName.trim(),
      workspaceRoot: folder,
    );
    final settings = ref.read(settingsProvider);
    final AppSettings updated;
    try {
      updated = settings.addLibrary(entry);
    } on ArgumentError {
      throw const LibraryException(LibraryProblem.overlap);
    }
    if (found == null || !sameLayout(found.layout, layout)) {
      await writeLibrary(MountedFolderStorage(folder), library);
    }
    await ref.read(settingsProvider.notifier).change((_) => updated);
    await scan(entry);
  }

  /// Forgets [id]: settings and index only, files are left untouched.
  Future<void> remove(LibraryId id) async {
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.removeLibrary(id));
    ref.read(localIndexProvider).removeLibrary(id);
    ref.read(indexRevisionProvider.notifier).bump();
  }

  /// Scans every configured library, one after the other.
  Future<void> scanAll() async {
    for (final entry in ref.read(settingsProvider).libraries) {
      await scan(entry);
    }
  }

  /// Scans [entry] in an isolate, incrementally from the stored scan, and
  /// updates the index. Unavailable libraries are skipped.
  Future<void> scan(LibraryEntry entry) async {
    try {
      final root = entry.libraryRoot;
      final library = await readLibrary(MountedFolderStorage(root));
      if (library == null) return;
      final index = ref.read(localIndexProvider);
      final result = await scanFolder(
        root,
        library,
        previous: index.scanResult(library.id),
      );
      index.update(library, result);
      ref.read(indexRevisionProvider.notifier).bump();
    } on Object catch (error) {
      // The library stays configured; it is scanned again on next start.
      debugPrint('Scan of ${entry.displayName} failed: $error');
    }
  }
}

/// Same layout levels and render mapping (the frozen flag is ignored).
bool sameLayout(Layout? a, Layout? b) =>
    jsonEncode(a?.freeze().toJson()) == jsonEncode(b?.freeze().toJson());

final libraryServiceProvider = Provider<LibraryService>(LibraryService.new);
