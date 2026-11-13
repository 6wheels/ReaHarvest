import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'library_scans.dart';
import 'navigation.dart';
import 'providers.dart';
import 'tasks.dart';

final _log = Logger('library.catalog');

/// Why a folder cannot become a library.
enum LibraryProblem {
  /// The folder holds a cloud or collab library (milestone B).
  unsupportedMode,

  /// The folder is, contains or is inside a folder of another library.
  overlap,

  /// The folder holds an unreadable `.library.json`.
  invalidFile,

  /// The library already holds titles: its layout cannot change without a
  /// migration (SPEC §3.1).
  layoutLocked,
}

final class LibraryException implements Exception {
  const LibraryException(this.problem);

  final LibraryProblem problem;

  @override
  String toString() => 'LibraryException($problem)';
}

/// The catalog of libraries: creation or attachment, removal, known values
/// and members (SPEC §3.1, §6.5).
class LibraryCatalog {
  LibraryCatalog(this.ref);

  final Ref ref;

  /// Library already described in [folder] (`.library.json`), or null.
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

  /// Whether [folder] holds a REAPER project (backups, history and trash
  /// left out), listed in an isolate. The layout of a library holding
  /// projects can no longer change (SPEC §3.1).
  Future<bool> hasProjects(String folder) => Isolate.run(() async {
    for (final e in await MountedFolderStorage(
      folder,
    ).list('', recursive: true)) {
      final segments = e.path.split('/');
      if (!e.isDirectory &&
          isProjectFile(segments.last) &&
          !segments.any(isExcludedFolder)) {
        return true;
      }
    }
    return false;
  });

  /// Known values to offer for [layout] in [folder] (SPEC §3.1).
  Future<List<KnownValue>> prefillKnownValues(String folder, Layout layout) =>
      prefillKnownValuesIn(folder, layout);

  /// Adds the local library at [folder] with [layout] (null: free tree):
  /// attaches the library already described there (keeping its id, and
  /// replacing its layout if it differs and is not locked), or creates it,
  /// with [knownValues] when given (SPEC §3.1). Then scans it. Throws
  /// [LibraryException].
  Future<void> addLocal({
    required String folder,
    required String displayName,
    required Layout? layout,
    List<KnownValue> knownValues = const [],
  }) async {
    final found = await existing(folder);
    if (found != null && found.mode != LibraryMode.local) {
      throw const LibraryException(LibraryProblem.unsupportedMode);
    }
    final changed = found == null || !sameLayout(found.layout, layout);
    if (found != null && changed && await hasProjects(folder)) {
      throw const LibraryException(LibraryProblem.layoutLocked);
    }
    final kept = changed
        ? Library(
            id: found?.id ?? LibraryId.generate(),
            mode: LibraryMode.local,
            layout: layout,
          )
        : found;
    final library = knownValues.isEmpty
        ? kept
        : kept.withKnownValues(knownValues);
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
    if (changed || knownValues.isNotEmpty) {
      await writeLibrary(MountedFolderStorage(folder), library);
    }
    await ref.read(settingsProvider.notifier).change((_) => updated);
    _log.info(
      '${found == null ? 'Created' : 'Attached'} library '
      '${entry.displayName} at $folder'
      '${changed && found != null ? ', layout replaced' : ''}'
      '${knownValues.isEmpty ? '' : ', ${knownValues.paths.length} known values'}',
    );
    await ref.read(libraryScansProvider).scanTask(entry);
  }

  /// Known values of the library [entry], and those still used by a folder
  /// (paths joined with `/`), which cannot be removed (SPEC §3.1).
  Future<({List<KnownValue> values, Set<String> used})> knownValuesOf(
    LibraryEntry entry,
  ) async {
    final root = entry.libraryRoot;
    final library = await readLibrary(MountedFolderStorage(root));
    final values = library?.knownValues ?? const <KnownValue>[];
    final used = <String>{};
    for (final path in values.paths) {
      if (await Directory(p.joinAll([root, ...path])).exists()) {
        used.add(path.join('/'));
      }
    }
    return (values: values, used: used);
  }

  /// Replaces the known values of the library [entry] (SPEC §3.1), in the
  /// turn of the library. Then rescans it, as a task whose report is shown
  /// at the end.
  Future<void> setKnownValues(
    LibraryEntry entry,
    List<KnownValue> values,
  ) async {
    final written = await ref.read(libraryTurnsProvider).run(
      entry.id,
      () async {
        final storage = MountedFolderStorage(entry.libraryRoot);
        final library = await readLibrary(storage);
        if (library == null) return false;
        await writeLibrary(storage, library.withKnownValues(values));
        return true;
      },
    );
    if (!written) return;
    _log.info(
      'Known values of ${entry.displayName} set: '
      '${values.paths.map((v) => v.join('/')).join(', ')}',
    );
    await ref.read(libraryScansProvider).scanTask(entry);
  }

  /// Declared members of the library [entry] (SPEC §6.5).
  Future<List<Member>> membersOf(LibraryEntry entry) async =>
      (await readLibrary(MountedFolderStorage(entry.libraryRoot)))?.members ??
      const [];

  /// Replaces the declared members of the library [entry] (SPEC §6.5).
  /// Then rescans it, to index them. In the turn of the library.
  Future<void> setMembers(LibraryEntry entry, List<Member> members) =>
      ref.read(libraryTurnsProvider).run(entry.id, () async {
        final storage = MountedFolderStorage(entry.libraryRoot);
        final library = await readLibrary(storage);
        if (library == null) return;
        await writeLibrary(storage, library.withMembers(members));
        _log.info(
          'Members of ${entry.displayName} set: '
          '${members.map((m) => m.name).join(', ')}',
        );
        await ref.read(libraryScansProvider).scan(entry);
      });

  /// Forgets [id]: settings and index only, files are left untouched.
  Future<void> remove(LibraryId id) async {
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.removeLibrary(id));
    // Reload the filter and views, cleared of the library.
    ref.invalidate(navigationProvider);
    ref.read(localIndexProvider).removeLibrary(id);
    ref.read(indexRevisionProvider.notifier).bump();
    _log.info('Removed library $id (files left untouched)');
  }
}

/// Same layout levels and render mapping.
bool sameLayout(Layout? a, Layout? b) =>
    jsonEncode(a?.toJson()) == jsonEncode(b?.toJson());

final libraryCatalogProvider = Provider<LibraryCatalog>(LibraryCatalog.new);

extension LibraryLookup on Ref {
  /// The configured library [id]. Throws [StateError] if it was removed.
  LibraryEntry libraryEntry(LibraryId id) =>
      read(settingsProvider).library(id) ??
      (throw StateError('Library $id is not configured'));
}

/// Owner of the versions the local member creates in a library (SPEC
/// §4.2): the local member if the library declares it, else none.
final localOwnerProvider = Provider.family<MemberId?, LibraryId>((ref, id) {
  final me = ref.watch(settingsProvider.select((s) => s.identity.memberId));
  final members =
      ref.watch(indexedLibrariesProvider)[id]?.members ?? const <Member>[];
  return members.any((m) => m.id == me) ? me : null;
});
