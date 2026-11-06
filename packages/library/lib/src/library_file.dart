import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Name of the library description file, at the library root (SPEC §6.5).
const libraryFileName = '_library.json';

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

/// Reads `_library.json` from [storage] (the repository root in cloud and
/// collab modes, the workspace root in local mode), or null if absent.
Future<Library?> readLibrary(RepositoryStorage storage) async {
  if (await storage.stat(libraryFileName) == null) return null;
  final text = await utf8.decodeStream(storage.read(libraryFileName));
  return Library.fromJson((jsonDecode(text) as Map).cast());
}

/// Writes `_library.json` atomically to [storage].
Future<void> writeLibrary(RepositoryStorage storage, Library library) {
  final text = const JsonEncoder.withIndent('  ').convert(library.toJson());
  return storage.write(libraryFileName, Stream.value(utf8.encode('$text\n')));
}
