import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'adoption.dart';
import 'conventions.dart';
import 'scaffold.dart';

/// A backup of a version, in the `.history/` folder of its title (SPEC §5.4).
final class Backup {
  const Backup({
    required this.path,
    required this.versionId,
    required this.created,
  });

  /// Library path of the backup file.
  final String path;

  /// Version it is a backup of (the copy keeps the version identity).
  final VersionId versionId;

  /// When it was made: the date in its name, or its modification date.
  final DateTime created;
}

/// Backs up the version [fileName] of the title [titleDir] (UI: « Créer un
/// point de sauvegarde », SPEC §5.4): copies it into `.history/` as
/// `<name> <yyyy-MM-dd HHmmss>.<ext>`; the version is unchanged. Returns the
/// path of the backup.
Future<String> backupVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName, {
  DateTime? now,
}) async {
  final source = _join(titleDir, fileName);
  final name = p.posix.basenameWithoutExtension(fileName);
  final ext = p.posix.extension(fileName);
  final target = await freePath(
    storage,
    _join(
      titleDir,
      '$historyFolderName/$name ${_stamp(now ?? DateTime.now())}$ext',
    ),
  );
  await storage.write(target, storage.read(source));
  return target;
}

/// Backups of the title [titleDir], by version, newest first. Files that are
/// not projects or carry no version identity are left out.
Future<Map<VersionId, List<Backup>>> readHistory(
  RepositoryStorage storage,
  String titleDir,
) async {
  final folder = _join(titleDir, historyFolderName);
  if (await storage.stat(folder) == null) return const {};
  final history = <VersionId, List<Backup>>{};
  for (final e in await storage.list(folder)) {
    if (e.isDirectory || !isProjectFile(e.path)) continue;
    final text = await storage
        .read(e.path)
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final metadata = VersionMetadata.fromExtState(
      RppProject.parse(text).extState(VersionMetadata.section),
    );
    if (metadata == null) continue;
    history
        .putIfAbsent(metadata.id, () => [])
        .add(
          Backup(
            path: e.path,
            versionId: metadata.id,
            created: _dateOf(e.path) ?? e.modified,
          ),
        );
  }
  for (final backups in history.values) {
    backups.sort((a, b) => b.created.compareTo(a.created));
  }
  return history;
}

/// Restores the backup [backup] into the version [fileName] of the title
/// [titleDir] (SPEC §5.4): the current content is backed up first, then
/// replaced. Returns the path of that new backup.
Future<String> restoreBackup(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
  String backup, {
  DateTime? now,
}) async {
  final saved = await backupVersion(storage, titleDir, fileName, now: now);
  await storage.write(_join(titleDir, fileName), storage.read(backup));
  return saved;
}

String _stamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}${two(d.minute)}${two(d.second)}';
}

final _datePattern = RegExp(
  r' (\d{4})-(\d\d)-(\d\d) (\d\d)(\d\d)(\d\d)(?: \(\d+\))?$',
);

/// Local date in the backup name [path], or null.
DateTime? _dateOf(String path) {
  final m = _datePattern.firstMatch(p.posix.basenameWithoutExtension(path));
  if (m == null) return null;
  final n = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime(n[0], n[1], n[2], n[3], n[4], n[5]);
}

String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';
