import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'free_names.dart';
import 'library_path.dart';
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
/// `<name> <yyyy-MM-dd HHmmss>.<ext>`, its relative paths rebased so that the
/// backup opens in REAPER ([rebaseProjectPaths]); the version is unchanged.
/// Returns the path of the backup.
Future<String> backupVersion(
  RepositoryStorage storage,
  String titleDir,
  String fileName, {
  DateTime? now,
}) async {
  final name = p.posix.basenameWithoutExtension(fileName);
  final ext = p.posix.extension(fileName);
  final history = joinPath(titleDir, historyFolderName);
  final target = await freePath(
    storage,
    joinPath(history, '$name ${_stamp(now ?? DateTime.now())}$ext'),
  );
  final text = await _readText(storage, joinPath(titleDir, fileName));
  await _writeText(
    storage,
    target,
    rebaseProjectPaths(text, parentOf(joinPath(titleDir, fileName)), history),
  );
  return target;
}

/// Backups of the title [titleDir], by version, newest first. Files that are
/// not projects or carry no version identity are left out.
Future<Map<VersionId, List<Backup>>> readHistory(
  RepositoryStorage storage,
  String titleDir,
) async {
  final folder = joinPath(titleDir, historyFolderName);
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
/// replaced, its relative paths rebased to the title folder. Returns the path
/// of that new backup.
Future<String> restoreBackup(
  RepositoryStorage storage,
  String titleDir,
  String fileName,
  String backup, {
  DateTime? now,
}) async {
  final saved = await backupVersion(storage, titleDir, fileName, now: now);
  final version = joinPath(titleDir, fileName);
  final text = await _readText(storage, backup);
  await _writeText(
    storage,
    version,
    rebaseProjectPaths(text, parentOf(backup), parentOf(version)),
  );
  return saved;
}

/// Normalizes the relative paths of the backup [backup] before it is opened
/// in REAPER, which lengthens them on every save of a backup (SPEC §5.4).
/// The file is written only if a path changed.
Future<void> cleanBackupPaths(RepositoryStorage storage, String backup) async {
  final text = await _readText(storage, backup);
  final dir = parentOf(backup);
  final cleaned = rebaseProjectPaths(text, dir, dir);
  if (cleaned != text) await _writeText(storage, backup, cleaned);
}

/// Rewrites the relative paths of a project written for the folder [from]
/// (library path) so that they denote the same files from the folder [to],
/// normalized (SPEC §5.4): media references, record paths (`RECORD_PATH`,
/// empty = project folder) and render target (`RENDER_FILE`). Absolute
/// paths are kept. Targeted patches: the text is unchanged when no path
/// changes.
String rebaseProjectPaths(String text, String from, String to) {
  String? rebase(String ref) {
    if (isAbsoluteReference(ref)) return null;
    final slashed = ref.replaceAll(r'\', '/');
    // Resolved under a deep virtual root, so that paths leading outside the
    // library keep their meaning.
    final target = p.posix.join(_virtualRoot, from, slashed);
    final relative = p.posix.relative(
      target,
      from: p.posix.join(_virtualRoot, to),
    );
    if (relative == '.') return '';
    final separator = separatorOf(ref);
    return separator == '/' ? relative : relative.replaceAll('/', separator);
  }

  var out = rewriteMediaPaths(text, (ref) => rebase(ref) ?? ref);
  final root = RppProject.parse(out).document.root;
  final record = root.line('RECORD_PATH')?.params;
  if (record != null && record.isNotEmpty) {
    final primary = rebase(record[0]) ?? record[0];
    final secondary = record.length > 1 && record[1].isNotEmpty
        ? rebase(record[1]) ?? record[1]
        : record.elementAtOrNull(1);
    if (primary != record[0] || secondary != record.elementAtOrNull(1)) {
      out = setRootAttribute(out, 'RECORD_PATH', [
        primary,
        ?secondary,
        ...record.skip(2),
      ]);
    }
  }
  final render = root.line('RENDER_FILE')?.params;
  if (render != null && render.isNotEmpty) {
    final file = rebase(render[0]) ?? render[0];
    if (file != render[0]) {
      out = setRootAttribute(out, 'RENDER_FILE', [file, ...render.skip(1)]);
    }
  }
  return out;
}

/// Root under which library paths are resolved by [rebaseProjectPaths].
final _virtualRoot = '/${List.filled(64, 'r').join('/')}';

Future<String> _readText(RepositoryStorage storage, String path) =>
    storage.read(path).transform(utf8.decoder).join();

Future<void> _writeText(RepositoryStorage storage, String path, String text) =>
    storage.write(path, Stream.value(utf8.encode(text)));

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
