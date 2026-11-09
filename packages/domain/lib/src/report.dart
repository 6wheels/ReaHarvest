import 'library.dart';

/// Level of a report section, in display order.
enum ReportLevel { error, warning, skipped, done }

/// Kind of outcome of a long action, with its level (SPEC §5.2). Declared
/// grouped by level, in [ReportLevel] order: this is the display order.
enum ReportKind {
  scanFailed(ReportLevel.error),
  corrupted(ReportLevel.error),
  fileLost(ReportLevel.error),
  titleTooHigh(ReportLevel.warning),
  misplacedLevel(ReportLevel.warning),
  unknownValue(ReportLevel.warning),
  orphanNode(ReportLevel.warning),
  toSort(ReportLevel.warning),
  missingMedia(ReportLevel.warning),
  externalMedia(ReportLevel.warning),
  libraryUnavailable(ReportLevel.skipped),
  libraryScanned(ReportLevel.done),
  projectMoved(ReportLevel.done),
  mediaMoved(ReportLevel.done),
  mediaCopied(ReportLevel.done);

  const ReportKind(this.level);

  final ReportLevel level;
}

/// One reported file or folder, with an optional detail (an error message),
/// and for a misplaced folder, the layout level it was expected at and the
/// proposed target path (SPEC §5.8).
final class ReportItem {
  const ReportItem(this.path, [this.detail]) : level = null, target = null;

  /// Folder found where [level] was expected, to move to [target] if known.
  const ReportItem.misplaced(this.path, {required this.level, this.target})
    : detail = null;

  final String path;
  final String? detail;
  final LayoutLevel? level;
  final String? target;

  /// This item at [path].
  ReportItem withPath(String path) => level == null
      ? ReportItem(path, detail)
      : ReportItem.misplaced(path, level: level, target: target);

  @override
  bool operator ==(Object other) =>
      other is ReportItem &&
      other.path == path &&
      other.detail == detail &&
      other.level?.key == level?.key &&
      other.target == target;

  @override
  int get hashCode => Object.hash(path, detail, level?.key, target);

  @override
  String toString() => [
    path,
    if (detail != null) ': $detail',
    if (level != null) ' [${level!.key}]',
    if (target != null) ' -> $target',
  ].join();
}

/// Report of a long action (SPEC §5.2): items by kind of outcome.
final class Report {
  const Report([this.items = const {}]);

  final Map<ReportKind, List<ReportItem>> items;

  /// Non-empty sections, in [ReportKind] order (by level).
  List<(ReportKind, List<ReportItem>)> get sections => [
    for (final kind in ReportKind.values)
      if (items[kind] case final list? when list.isNotEmpty) (kind, list),
  ];

  bool get isEmpty => sections.isEmpty;

  bool get hasErrors => _has(ReportLevel.error);

  bool get hasWarnings => _has(ReportLevel.warning);

  bool _has(ReportLevel level) =>
      sections.any((section) => section.$1.level == level);

  /// Items of both reports.
  Report operator +(Report other) => Report({
    for (final kind in {...items.keys, ...other.items.keys})
      kind: [...?items[kind], ...?other.items[kind]],
  });

  /// Plain text, one section per line block (for the log).
  @override
  String toString() => [
    for (final (kind, list) in sections) ...[
      '${kind.name} (${list.length})',
      for (final item in list) '  $item',
    ],
  ].join('\n');
}
