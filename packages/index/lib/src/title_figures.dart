import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'local_index.dart';

/// What takes space in a title folder (SPEC §5.2).
enum FigurePart {
  /// The `.RPP` files of its versions.
  projects,

  /// `Media/` of its versions.
  media,

  /// `Renders/` of its versions.
  renders,

  /// `Assets/` of the title.
  assets,

  /// `.history/` of its versions.
  history,

  /// `.trash/` of the title.
  trash,

  /// REAPER backups, peaks and any other file.
  other,
}

/// Sizes and counts of a title, from the index only (SPEC §5.2).
final class TitleFigures {
  const TitleFigures({
    required this.sizes,
    required this.versions,
    required this.notAdopted,
    required this.trashedVersions,
    required this.backups,
    required this.assets,
  });

  /// Bytes of each part, every part present.
  final Map<FigurePart, int> sizes;

  /// Number of versions, the not adopted ones included.
  final int versions;

  /// Number of versions not adopted yet.
  final int notAdopted;

  /// Number of versions in the trash.
  final int trashedVersions;

  /// Number of backup points of its versions.
  final int backups;

  /// Number of files in `Assets/`.
  final int assets;

  /// Bytes used by the title.
  int get total => sizes.values.fold(0, (a, b) => a + b);

  int get adopted => versions - notAdopted;
}

/// Figures of [title] from its versions' sizes (scan metadata), its trash
/// and the index [files] of its folder: files in `Assets/` count as assets,
/// those outside the version folders and `Assets/` as other; the files of
/// a version folder are counted through [Version.sizes], which also cover
/// what the index leaves out (`.history/`, backups). The project files of
/// free tree versions, counted by their version, are skipped.
TitleFigures figuresOf(Title title, Iterable<IndexedFile> files) {
  final sizes = {for (final part in FigurePart.values) part: 0};
  final folders = <String>{};
  for (final v in title.versions) {
    if (v.folder case final folder? when !folders.add(folder.toLowerCase())) {
      continue; // Several projects in one folder: its bytes count once.
    }
    for (final MapEntry(:key, :value) in v.sizes.entries) {
      final part = switch (key) {
        SizeCategory.project => FigurePart.projects,
        SizeCategory.media => FigurePart.media,
        SizeCategory.renders => FigurePart.renders,
        SizeCategory.history => FigurePart.history,
        SizeCategory.reaperBackups || SizeCategory.other => FigurePart.other,
      };
      sizes[part] = sizes[part]! + value;
    }
  }
  sizes[FigurePart.trash] = title.trashSize;
  final prefix = title.path.isEmpty ? '' : '${title.path}/';
  final projects = {for (final v in title.versions) '$prefix${v.fileName}'};
  var assets = 0;
  for (final f in files) {
    if (!f.path.startsWith(prefix) || projects.contains(f.path)) continue;
    final segments = f.path.substring(prefix.length).split('/');
    final first = segments.first.toLowerCase();
    if (segments.length > 1 && folders.contains(first)) continue;
    final part = segments.length > 1 && first == 'assets'
        ? FigurePart.assets
        : FigurePart.other;
    if (part == FigurePart.assets) assets++;
    sizes[part] = sizes[part]! + f.stamp.size;
  }
  return TitleFigures(
    sizes: sizes,
    versions: title.versions.length,
    notAdopted: title.versions.where((v) => v.metadata == null).length,
    trashedVersions: title.trashedVersions,
    backups: title.backupCount,
    assets: assets,
  );
}
