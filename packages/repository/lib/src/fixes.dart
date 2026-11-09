import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'adoption.dart';
import 'node_file.dart';

/// A migration fix of a "To sort" issue (SPEC §5.8 step 4). Plain data,
/// sendable to an isolate.
sealed class MigrationFix {
  const MigrationFix(this.path);

  /// Library path of the folder or project to fix.
  final String path;
}

/// Moves the folder [path] to [target] (its layout position).
final class MoveFolder extends MigrationFix {
  const MoveFolder(super.path, this.target);

  final String target;
}

/// Moves the project [path] into the title folder [titleDir], with its
/// media ([moveProjectToTitle]).
final class MoveProject extends MigrationFix {
  const MoveProject(super.path, this.titleDir);

  final String titleDir;
}

/// Moves the project [path], found in a member or status subfolder of the
/// title [titleDir], up into the title ([liftProject]).
final class LiftProject extends MigrationFix {
  const LiftProject(
    super.path,
    this.titleDir, {
    required this.owner,
    this.status,
    this.statusFolder,
  });

  final String titleDir;

  /// Owner if the project is not adopted yet.
  final MemberId owner;

  /// Version status to set, deduced from [statusFolder].
  final String? status;

  /// Status subfolder whose name matched no status: kept in the report.
  final String? statusFolder;
}

/// Applies [fixes] through [storage] (a [Migration.storage], so that no
/// file is lost), one by one: a failed fix is reported and the others go
/// on.
Future<Report> applyFixes(
  RepositoryStorage storage,
  List<MigrationFix> fixes,
) async {
  var report = const Report();
  for (final fix in fixes) {
    try {
      report += switch (fix) {
        MoveFolder(:final path, :final target) =>
          await storage.stat(target) == null
              ? await _moveFolder(storage, path, target)
              : Report({
                  ReportKind.targetExists: [ReportItem(path, target)],
                }),
        MoveProject(:final path, :final titleDir) => (await moveProjectToTitle(
          storage,
          path,
          titleDir,
        )).toReport(),
        final LiftProject lift => await _lift(storage, lift),
      };
    } on Object catch (error) {
      report += Report({
        ReportKind.fixFailed: [ReportItem(fix.path, '$error')],
      });
    }
  }
  return report;
}

Future<Report> _moveFolder(
  RepositoryStorage storage,
  String path,
  String target,
) async {
  await storage.move(path, target);
  return Report({
    ReportKind.folderMoved: [ReportItem(target)],
  });
}

Future<Report> _lift(RepositoryStorage storage, LiftProject fix) async {
  final moved = await liftProject(
    storage,
    fix.path,
    fix.titleDir,
    owner: fix.owner,
    status: fix.status,
  );
  return Report({
    ReportKind.projectMoved: [ReportItem(moved)],
    if (fix.statusFolder case final folder?)
      ReportKind.statusFolderUnmatched: [ReportItem(moved, folder)],
  });
}

/// Moves the project [path], found in a subfolder of the title [titleDir]
/// (member or status subfolder, SPEC §5.8), up into the title, under a
/// free name. Its relative media references and record path are rewritten
/// to keep pointing at the same files, which do not move (their pool merge
/// is another fix). A project without metadata is adopted for [owner];
/// [status], if set, becomes its version status. Returns its new path.
Future<String> liftProject(
  RepositoryStorage storage,
  String path,
  String titleDir, {
  required MemberId owner,
  String? status,
}) async {
  final folder = p.posix.dirname(path);
  final sub = folder.substring(titleDir.isEmpty ? 0 : titleDir.length + 1);
  var text = await utf8.decodeStream(storage.read(path));
  text = rewriteMediaPaths(text, (ref) => _prefixed(sub, ref));
  final recordPath = RppProject.parse(text).document.root.line('RECORD_PATH');
  if (recordPath != null && recordPath.params.any((s) => s.isNotEmpty)) {
    text = setRootAttribute(text, 'RECORD_PATH', [
      for (final s in recordPath.params) s.isEmpty ? s : _prefixed(sub, s),
    ]);
  }
  var metadata = VersionMetadata.fromExtState(
    RppProject.parse(text).extState(VersionMetadata.section),
  );
  if (metadata == null) {
    metadata = VersionMetadata(id: VersionId.generate(), owner: owner);
    text = setExtState(text, VersionMetadata.section, metadata.toExtState());
  }
  final target = await freePath(
    storage,
    titleDir.isEmpty
        ? p.posix.basename(path)
        : '$titleDir/${p.posix.basename(path)}',
  );
  await storage.move(path, target);
  await storage.write(target, Stream.value(utf8.encode(text)));
  if (status != null) {
    await setVersionStatus(storage, titleDir, metadata.id, status);
  }
  return target;
}

/// [ref], relative to a project in the subfolder [sub] of its title, made
/// relative to the title; absolute references are kept.
String _prefixed(String sub, String ref) {
  final slashed = ref.replaceAll(r'\', '/');
  if (slashed.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(slashed)) {
    return ref;
  }
  final joined = p.posix.normalize('$sub/$slashed');
  final separator = separatorOf(ref);
  return separator == '/' ? joined : joined.replaceAll('/', separator);
}
