import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'state/providers.dart';

/// Sample titles to review the design without a library
/// (`flutter run --dart-define=REAHARVEST_DEMO=true`).
List<TitleView> demoTitles() {
  const names = [
    'Northern Lights', 'Paper Boats', 'Slow Tide', 'Glass Garden',
    'Midnight Ferry', 'Copper Sky', 'Lantern Song', 'Quiet Engine',
    'Velvet Static', 'Harbor Lines', 'Winter Orchard', 'First Light',
  ];
  const statuses = ['idea', 'writing', 'recording', 'mixing', 'done', null];
  final now = DateTime(2026, 11, 6);
  return [
    for (final (i, name) in names.indexed)
      (
        title: Title(
          id: NodeId('demo-$i-$name'),
          libraryId: const LibraryId('demo'),
          path: 'Sample Artist/Album ${i ~/ 4 + 1}/$name',
          tags: {
            'artist': 'Sample Artist',
            'album': 'Album ${i ~/ 4 + 1}',
            'title': name,
          },
          versions: [
            for (var v = 0; v <= i % 5; v++)
              Version(
                fileName: '$name v${v + 1}.rpp',
                modified: now.subtract(Duration(days: i * 9 + v)),
                size: 1,
              ),
          ],
        ),
        bpm: 72 + i * 7,
        status: statuses[i % statuses.length],
      ),
  ];
}
