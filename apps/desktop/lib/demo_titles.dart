import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Library of the sample titles.
final demoLibrary = Library(
  id: const LibraryId('demo'),
  mode: LibraryMode.local,
  layout: Layout.classic(),
);

/// Sample titles to review the design without a library
/// (`flutter run --dart-define=REAHARVEST_DEMO=true`).
List<Title> demoTitles() {
  const names = [
    'Northern Lights',
    'Paper Boats',
    'Slow Tide',
    'Glass Garden',
    'Midnight Ferry',
    'Copper Sky',
    'Lantern Song',
    'Quiet Engine',
    'Velvet Static',
    'Harbor Lines',
    'Winter Orchard',
    'First Light',
  ];
  const statuses = ['idea', 'writing', 'recording', 'mixing', 'done', null];
  final now = DateTime(2026, 11, 6);
  return [
    for (final (i, name) in names.indexed)
      Title(
        id: NodeId('demo-$i-$name'),
        libraryId: demoLibrary.id,
        path: 'Sample Artist/Album ${i ~/ 4 + 1}/$name',
        tags: {
          'artist': i.isEven ? 'Sample Artist' : 'Other Artist',
          'album': 'Album ${i ~/ 4 + 1}',
          'title': name,
        },
        status: statuses[i % statuses.length],
        versions: [
          for (var v = 0; v <= i % 5; v++)
            Version(
              fileName: '$name v${v + 1}.rpp',
              modified: now.subtract(Duration(days: i * 9 + v)),
              size: 1,
              tempo: 72.0 + i * 7,
              metadata: i == 3 && v == 0
                  ? null
                  : VersionMetadata(
                      id: VersionId('demo-$i-$v'),
                      owner: const MemberId('demo-member'),
                      label: 'take ${v + 1}',
                    ),
            ),
        ],
      ),
  ];
}
