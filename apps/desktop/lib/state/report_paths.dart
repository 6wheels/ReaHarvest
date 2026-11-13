import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Absolute path of [path], relative to the library at [root].
String _absolute(String root, String path) =>
    p.joinAll([root, ...path.split('/')]);

/// Items for [paths] of the library at [root], as absolute paths.
List<ReportItem> absoluteItems(String root, List<String> paths) => [
  for (final path in paths) ReportItem(_absolute(root, path)),
];

/// Kinds whose detail is a path of the library, one per line.
const _pathDetails = {
  ReportKind.targetExists,
  ReportKind.folderMerged,
  ReportKind.fileRenamed,
  ReportKind.mediaMoved,
  ReportKind.mediaCopied,
  ReportKind.mediaTrashed,
  ReportKind.mediaUsedElsewhere,
  ReportKind.referencedByPlugin,
};

/// [report] of the library at [root], with absolute paths, details
/// included.
Report rootedReport(String root, Report report) => Report({
  for (final MapEntry(key: kind, value: items) in report.items.entries)
    kind: [
      for (final item in items)
        switch (item.detail) {
          final detail? when _pathDetails.contains(kind) => ReportItem(
            _absolute(root, item.path),
            [for (final line in detail.split('\n')) _absolute(root, line)]
                .join('\n'),
          ),
          _ => item.withPath(_absolute(root, item.path)),
        },
    ],
});
