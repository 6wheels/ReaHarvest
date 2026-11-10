// Removes the ReaHarvest technical files from a library folder, to start
// again from scratch. Project content is never touched: `.rpp` files (and
// their EXTSTATE), audio, `Media/`, `Renders/`, `Assets/`, `.history/`,
// `.trash/`, REAPER backups and peaks are all kept.
//
// Usage: dart tool/clean_library.dart <library root> [--dry-run]

import 'dart:io';

/// Files written by library initialization and by the scan (title nodes).
const _files = {'.library.json', '.node.json'};

/// Folders owned by ReaHarvest (collab journal).
const _folders = {'.collab', '.migration'};

/// Suffix of temporary files left by an interrupted atomic write.
const _tempSuffix = '.reaharvest-tmp';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.length != 1) {
    stderr.writeln(
      'Usage: dart tool/clean_library.dart <library root> [--dry-run]',
    );
    exitCode = 64;
    return;
  }
  final root = Directory(paths.single);
  if (!root.existsSync()) {
    stderr.writeln('Folder not found: ${root.path}');
    exitCode = 66;
    return;
  }

  final targets = <FileSystemEntity>[];
  void visit(Directory dir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.path.split(Platform.pathSeparator).last;
      if (e is Directory) {
        _folders.contains(name) ? targets.add(e) : visit(e);
      } else if (e is File &&
          (_files.contains(name) || name.endsWith(_tempSuffix))) {
        targets.add(e);
      }
    }
  }

  visit(root);
  for (final e in targets) {
    stdout.writeln('${dryRun ? 'Would remove' : 'Removing'} ${e.path}');
    if (!dryRun) e.deleteSync(recursive: true);
  }
  stdout.writeln(
    '${targets.length} item(s) ${dryRun ? 'to remove' : 'removed'} '
    'in ${root.path}.',
  );
}
