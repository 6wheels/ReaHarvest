import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'media.dart';
import 'media_plan.dart';
import 'migration.dart';

/// One version of a migration fix (SPEC §5.8 step 4): its project and what
/// it becomes. Plain data, sendable to an isolate.
final class FixVersion {
  const FixVersion(
    this.source, {
    required this.folder,
    required this.label,
    this.owner,
    this.status,
    this.statusFolder,
  });

  /// Library path of its project.
  final String source;

  /// Name of its version folder in the target title (its file keeps its
  /// name); a free `name (n)` variant if taken.
  final String folder;

  /// Its label (SPEC §4.2).
  final String label;

  /// Its owner; null when the library declares no members.
  final MemberId? owner;

  /// Its status, if any (SPEC §5.9).
  final String? status;

  /// Status subfolder it was found in, kept in the report when [status] is
  /// null.
  final String? statusFolder;

  @override
  String toString() =>
      ['$source -> $folder', label, ?owner, ?status].join(', ');
}

/// A migration fix of a title candidate (SPEC §5.8 step 4, #148). Plain
/// data, sendable to an isolate.
sealed class MigrationFix {
  const MigrationFix(
    this.path,
    this.target,
    this.versions, {
    required this.level,
    this.force = false,
  });

  /// Library path of the candidate root, or of the project moved.
  final String path;

  /// Path of the target title.
  final String target;

  /// Its versions, organized in this order.
  final List<FixVersion> versions;

  /// Layout key of the title level, for the node file of a title the fix
  /// creates.
  final String level;

  /// Whether its versions with a missing or external media (e.g. one of
  /// another computer, that REAPER will ask for when the project opens)
  /// are organized too, rather than left as they are.
  final bool force;

  /// Name of the fix in the migration journal.
  String get kind;

  @override
  String toString() => [
    '$kind $path -> $target${force ? ', forced' : ''}',
    for (final v in versions) '  $v',
  ].join('\n');
}

/// Organizes the candidate [path] into version folders at [target]: a
/// title folder ([titleFolder]) is moved there first; the projects of a
/// candidate placed above the title level move one by one into the target
/// title, created.
final class OrganizeTitle extends MigrationFix {
  const OrganizeTitle(
    super.path,
    super.target,
    super.versions, {
    required super.level,
    super.force,
    this.titleFolder = true,
  });

  /// Whether [path] is a title folder, moved as a whole.
  final bool titleFolder;

  @override
  String get kind => 'organizeTitle';
}

/// Attaches the versions of the candidate [path] to the existing title
/// [target]: their version folders join it, their node entries are added.
final class AttachVersions extends MigrationFix {
  const AttachVersions(
    super.path,
    super.target,
    super.versions, {
    required super.level,
    super.force,
  });

  @override
  String get kind => 'attachVersions';
}

/// Moves one project to another title [target] (created if missing), where
/// it becomes a version folder.
final class MoveProject extends MigrationFix {
  MoveProject(
    FixVersion version,
    String target, {
    required super.level,
    super.force,
  }) : super(version.source, target, [version]);

  @override
  String get kind => 'moveProject';
}

/// Applies [fixes] through the storage of [migration] (so that no file is
/// lost), one by one, each between a `fixStart` and a `fixEnd` line of its
/// journal (`ok:false` when it throws): a failed fix is reported and the
/// others go on. Each fix is gathered, planned ([planFix]) and applied
/// ([applyPlan]); [usage] tells the projects referencing each media of the
/// library ([mediaUsage]). A fix with nothing to do but a failure (a
/// project that cannot be read) fails.
Future<Report> applyFixes(
  Migration migration,
  List<MigrationFix> fixes, {
  Map<String, List<String>> usage = const {},
}) async {
  final storage = migration.storage;
  final journal = migration.journal;
  var report = const Report();
  for (final fix in fixes) {
    final number = await journal.startFix(fix.kind, fix.path);
    try {
      final plan = planFix(fix, await gatherFix(storage, fix), usage: usage);
      if (plan.operations.isEmpty) {
        if (plan.blocked.items[ReportKind.fixFailed] case [final failed, ...]) {
          throw StateError(failed.detail ?? failed.path);
        }
      }
      report += await applyPlan(storage, plan);
    } on Object catch (error) {
      await journal.endFix(number, ok: false);
      report += Report({
        ReportKind.fixFailed: [ReportItem(fix.path, '$error')],
      });
      continue;
    }
    await journal.endFix(number, ok: true);
  }
  return report;
}
