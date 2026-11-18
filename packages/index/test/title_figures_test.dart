import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026);

  IndexedFile file(String path, int size) =>
      (path: path, stamp: (size: size, modified: t0), hash: null);

  Version version(
    String folder, {
    bool adopted = true,
    Map<SizeCategory, int> sizes = const {},
  }) => Version(
    fileName: '$folder/$folder.RPP',
    modified: t0,
    size: 0,
    folder: folder,
    sizes: sizes,
    metadata: adopted ? VersionMetadata(id: VersionId.generate()) : null,
  );

  Title title(
    List<Version> versions, {
    String path = 'a/b/song',
    int trashSize = 0,
    int trashedVersions = 0,
    int backupCount = 0,
  }) => Title(
    id: NodeId.generate(),
    libraryId: LibraryId.generate(),
    path: path,
    levels: const {},
    versions: versions,
    trashSize: trashSize,
    trashedVersions: trashedVersions,
    backupCount: backupCount,
  );

  test('splits the size on disk by part, with the counts', () {
    final figures = figuresOf(
      title(
        [
          version(
            'v1',
            sizes: {
              SizeCategory.project: 10,
              SizeCategory.media: 100,
              SizeCategory.renders: 20,
              SizeCategory.history: 30,
              SizeCategory.reaperBackups: 4,
              SizeCategory.other: 1,
            },
          ),
          version('v2', adopted: false, sizes: {SizeCategory.project: 10}),
        ],
        trashSize: 500,
        trashedVersions: 2,
        backupCount: 4,
      ),
      [
        file('a/b/song/v1/v1.RPP', 10),
        file('a/b/song/v1/Media/a.wav', 100),
        file('a/b/song/v2/v2.RPP', 10),
        file('a/b/song/Assets/score.pdf', 1000),
        file('a/b/song/assets/tab.pdf', 200),
        file('a/b/song/.node.json', 7),
        file('a/b/song/notes.txt', 3),
        file('a/b/other/Assets/x.pdf', 9999),
        file('a/b/songs/Assets/x.pdf', 9999),
      ],
    );
    expect(figures.sizes, {
      FigurePart.projects: 20,
      FigurePart.media: 100,
      FigurePart.renders: 20,
      FigurePart.assets: 1200,
      FigurePart.history: 30,
      FigurePart.trash: 500,
      FigurePart.other: 15,
    });
    expect(figures.total, 1885);
    expect((figures.versions, figures.adopted, figures.notAdopted), (2, 1, 1));
    expect(
      (figures.trashedVersions, figures.assets, figures.backups),
      (2, 2, 4),
    );
  });

  test('counts a folder holding several projects once', () {
    final sizes = {SizeCategory.media: 100};
    final figures = figuresOf(
      title([
        version('v1', sizes: sizes),
        Version(
          fileName: 'v1/other.RPP',
          modified: t0,
          size: 0,
          folder: 'v1',
          sizes: sizes,
        ),
      ]),
      const [],
    );
    expect(figures.sizes[FigurePart.media], 100);
    expect(figures.versions, 2);
  });

  test('skips the projects of a free tree and counts other files', () {
    final figures = figuresOf(
      title([
        Version(
          fileName: 'take/song.rpp',
          modified: t0,
          size: 10,
          sizes: {SizeCategory.project: 10},
        ),
      ], path: ''),
      [file('take/song.rpp', 10), file('take/notes.txt', 5)],
    );
    expect(figures.sizes[FigurePart.projects], 10);
    expect(figures.sizes[FigurePart.other], 5);
  });

  test('an empty title has no size', () {
    final figures = figuresOf(title(const []), const []);
    expect(figures.total, 0);
    expect(figures.versions, 0);
  });
}
