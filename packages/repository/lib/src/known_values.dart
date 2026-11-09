import 'dart:isolate';

import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'conventions.dart';
import 'mounted_folder_storage.dart';

/// Known values to offer for [layout] (SPEC §3.1): the intermediate folders
/// of the projects lying at the title depth or below it (member subfolders),
/// in name order. Projects placed higher are left out: they are what the
/// known values help to report.
Future<List<KnownValue>> prefillKnownValues(
  RepositoryStorage storage,
  Layout layout,
) async {
  final intermediate = layout.levels.length - 1;
  final paths = <String>{};
  for (final e in await storage.list('', recursive: true)) {
    final segments = e.path.split('/');
    final folders = segments.take(segments.length - 1).toList();
    if (e.isDirectory ||
        !isProjectFile(segments.last) ||
        folders.length < layout.levels.length ||
        segments.first == collabFolderName ||
        folders.any(isExcludedFolder) ||
        folders.take(layout.levels.length).any(_isReserved)) {
      continue;
    }
    paths.add(folders.take(intermediate).join('/'));
  }
  var values = const <KnownValue>[];
  for (final path in paths.toList()..sort()) {
    if (path.isNotEmpty) values = values.withPath(path.split('/'));
  }
  return values;
}

/// [prefillKnownValues] of the folder [root], in a background isolate.
Future<List<KnownValue>> prefillKnownValuesIn(String root, Layout layout) =>
    Isolate.run(() => prefillKnownValues(MountedFolderStorage(root), layout));

bool _isReserved(String name) =>
    reservedTitleFolders.contains(name.toLowerCase());
