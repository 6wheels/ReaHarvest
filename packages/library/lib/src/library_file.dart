import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Name of the library description file, at the library root (SPEC §6.5).
const libraryFileName = '.library.json';

/// Layout templates provided out of the box (SPEC §3.1).
enum LayoutTemplate {
  classic,
  projectOriented,
  film;

  static const recommended = classic;

  Layout create() => switch (this) {
    classic => Layout.classic(),
    projectOriented => Layout.projectOriented(),
    film => Layout.film(),
  };
}

/// Reads `.library.json` from [storage] (the repository root in cloud and
/// collab modes, the workspace root in local mode), or null if absent.
Future<Library?> readLibrary(RepositoryStorage storage) async {
  if (await storage.stat(libraryFileName) == null) return null;
  final text = await utf8.decodeStream(storage.read(libraryFileName));
  return Library.fromJson((jsonDecode(text) as Map).cast());
}

/// Writes `.library.json` atomically to [storage].
Future<void> writeLibrary(RepositoryStorage storage, Library library) {
  final text = const JsonEncoder.withIndent('  ').convert(library.toJson());
  return storage.write(libraryFileName, Stream.value(utf8.encode('$text\n')));
}

/// Adds the intermediate folders of the existing [paths] (folders or
/// titles, moved or created there) to the known values of the library in
/// [storage], when it declares some (SPEC §3.1): a value created by a move
/// is no longer reported as unknown. Returns the values added, joined with
/// `/`.
Future<List<String>> addKnownPaths(
  RepositoryStorage storage,
  List<String> paths,
) async {
  final library = await readLibrary(storage);
  final layout = library?.layout;
  if (library == null || layout == null || library.knownValues.isEmpty) {
    return const [];
  }
  var known = library.knownValues;
  final added = <String>[];
  for (final path in paths) {
    final values = path.split('/').take(layout.levels.length - 1).toList();
    if (!known.knows(values) && await storage.stat(path) != null) {
      known = known.withPath(values);
      added.add(values.join('/'));
    }
  }
  if (added.isNotEmpty) {
    await writeLibrary(storage, library.withKnownValues(known));
  }
  return added;
}
