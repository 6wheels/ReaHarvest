// Builds the reference library of docs/performance.md: 1,000 projects in the
// classic layout (20 artists x 5 albums x 10 titles, one version each), their
// media, and a data folder (settings and index) for the application. Seeded:
// every run gives the same library.
//
// Usage: dart run tool/perf/make_library.dart <folder> [--data=<folder>]
//            [--tray] [--no-index]
//
// <folder> is rebuilt when it holds a previous reference library (marker
// file), never otherwise. --data defaults to "<folder>-data".

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

const artists = 20;
const albums = 5;
const titles = 10;

/// File written in a folder built by this tool: only such a folder is
/// deleted again.
const markerName = '.perf-library';

/// Fixtures the projects are copied from, in turn (UTF-8 projects only).
const fixtureNames = [
  'tracks.rpp',
  'render.rpp',
  'render-file.rpp',
  'media-paths.rpp',
  'empty.rpp',
  'reference-metadata.rpp',
  'project-template.rpp',
];

const _libraryId = LibraryId('perf-reference-library');
const _memberId = MemberId('perf-reference-member');

/// Builds the reference library in [folder] and its data folder [data]:
/// settings with the tray icon shown if [tray], and an up-to-date index
/// unless [indexed] is false. [fixtures] is the `test/fixtures` folder.
Future<void> makeLibrary(
  String folder,
  String data, {
  required String fixtures,
  bool tray = false,
  bool indexed = true,
}) async {
  for (final dir in [folder, data]) {
    _resetFolder(dir);
  }
  final sources = [
    for (final name in fixtureNames)
      utf8.decode(File(p.join(fixtures, name)).readAsBytesSync()),
  ];
  // Node files are written here, with fixed ids: the scan would give them
  // random ones.
  final storage = MountedFolderStorage(folder);
  var nodes = 0;
  // A ULID: 26 characters, here the number of the node.
  Future<void> node(String dir, String level) => writeNodeFile(
    storage,
    dir,
    NodeFile(NodeId('${++nodes}'.padLeft(26, '0')), level),
  );
  var n = 0;
  for (var a = 1; a <= artists; a++) {
    await node('Artist $a', 'artist');
    for (var b = 1; b <= albums; b++) {
      await node('Artist $a/Album $b', 'album');
      for (var t = 1; t <= titles; t++) {
        final title = 'Title ${(++n).toString().padLeft(4, '0')}';
        await node('Artist $a/Album $b/$title', 'title');
        _writeProject(
          p.join(folder, 'Artist $a', 'Album $b', title, 'v1'),
          sources[(n - 1) % sources.length],
          title,
        );
      }
    }
  }
  final library = Library(
    id: _libraryId,
    mode: LibraryMode.local,
    layout: Layout.classic(),
  );
  await writeLibrary(storage, library);
  await SettingsFile(p.join(data, 'settings.json')).save(
    AppSettings(
      identity: const LocalIdentity(_memberId, 'Perf'),
      libraries: [
        LibraryEntry(
          id: _libraryId,
          displayName: 'Reference',
          workspaceRoot: folder,
        ),
      ],
      language: 'en',
      showInTray: tray,
    ),
  );
  if (indexed) {
    await scanIntoIndex(p.join(data, 'index.sqlite'), folder, library);
  }
}

/// Empties [dir] if it holds a previous reference library; fails on any
/// other non-empty folder.
void _resetFolder(String dir) {
  final folder = Directory(dir);
  if (folder.existsSync() && folder.listSync().isNotEmpty) {
    if (!File(p.join(dir, markerName)).existsSync()) {
      throw StateError('$dir is not empty and is no reference library.');
    }
    folder.deleteSync(recursive: true);
  }
  folder.createSync(recursive: true);
  File(p.join(dir, markerName)).writeAsStringSync('');
}

void _writeProject(String versionDir, String source, String title) {
  final text = setRootAttribute(source, 'TITLE', [title]);
  final media = <String>{};
  rewriteMediaPaths(text, (path) {
    media.add(path.split(RegExp(r'[\\/]')).last);
    return path;
  });
  Directory(versionDir).createSync(recursive: true);
  File(p.join(versionDir, 'v1.RPP')).writeAsStringSync(text);
  for (final name in media) {
    File(p.join(versionDir, 'Media', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(1024, 0));
  }
}

/// `test/fixtures` of the repository, found from the working directory up.
String findFixtures() {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    final candidate = p.join(dir.path, 'test', 'fixtures');
    if (Directory(candidate).existsSync()) return candidate;
    if (dir.parent.path == dir.path) throw StateError('No test/fixtures');
  }
}

Future<void> main(List<String> args) async {
  final options = args.where((a) => a.startsWith('--')).toList();
  final folders = args.where((a) => !a.startsWith('--')).toList();
  final dataOption = options.where((a) => a.startsWith('--data=')).firstOrNull;
  if (folders.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/perf/make_library.dart <folder> [--data=<folder>] '
      '[--tray] [--no-index]',
    );
    exitCode = 64;
    return;
  }
  final folder = p.normalize(p.absolute(folders.single));
  await makeLibrary(
    folder,
    dataOption == null
        ? '$folder-data'
        : p.normalize(p.absolute(dataOption.substring(7))),
    fixtures: findFixtures(),
    tray: options.contains('--tray'),
    indexed: !options.contains('--no-index'),
  );
}
