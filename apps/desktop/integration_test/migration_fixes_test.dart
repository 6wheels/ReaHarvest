import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'harness.dart';

/// Migration fixes from the "To sort" page, each through its preview and
/// report, the inventory check passing: folders moved to their layout
/// position with optional level values, an unknown folder declared in
/// place, member and status subfolders moved up with their owner and
/// status, batch adoption (#68); a folder moved onto an existing one
/// merged (#81). SPEC §5.8 step 4: `flutter test
/// integration_test/migration_fixes_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  const lost = 'Files missing or changed since the inventory';

  /// Starts the app on the classic library "Band", whose known values are
  /// the artist "Artist" and its album "Album".
  Future<void> start(WidgetTester tester) async {
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(
      tester,
      'Band',
      Layout.classic(),
      knownValues: const [
        KnownValue('Artist', [KnownValue('Album')]),
      ],
    );
  }

  /// Opens the "To sort" page.
  Future<void> openToSort(WidgetTester tester) async {
    await tester.tap(find.textContaining('TO SORT //'));
    await tester.pumpAndSettle();
  }

  /// Closes the report of the batch, which must have found no gap.
  Future<void> closeReport(WidgetTester tester) async {
    expect(find.textContaining(lost), findsNothing);
    await tapText(tester, 'Close');
  }

  testWidgets('moves folders to their place', (tester) async {
    for (final path in [
      'Band/Artist/Album/Song/v1/v1.rpp',
      // A title right under its artist.
      'Band/Artist/Lonely/v1/v1.rpp',
      // An artist that is not a known value.
      'Band/Stranger/Live/Tune/v1/v1.rpp',
    ]) {
      h.copyCleanProject(path);
    }
    await start(tester);
    final library = h.settings.libraries.single;
    await openToSort(tester);

    // A title too high, given a value for its missing album.
    await openSectionFix(tester, 'TITLES PLACED TOO HIGH · 1');
    expect(find.text('→ Artist/_Unassigned/Lonely'), findsOne);
    await tester.enterText(dialogField('Album'), 'Singles');
    await tester.pumpAndSettle();
    expect(find.text('→ Artist/Singles/Lonely'), findsOne);
    await confirmFix(tester, h);
    expect(find.text('Folders moved · 1'), findsOne);
    await closeReport(tester);
    expect(
      File(h.path('Band/Artist/Singles/Lonely/v1/v1.rpp')).existsSync(),
      isTrue,
    );

    // An unknown artist kept in place: declared, no longer to sort.
    const unknown =
        'UNKNOWN FOLDERS: DECLARE THEM IN THE LIBRARY SETTINGS, OR MOVE THEM '
        '· 1';
    await openSectionFix(tester, unknown);
    expect(find.text('→ Stranger'), findsOne);
    await confirmFix(tester, h);
    expect(
      find.text('Folders kept in place, added to the known values · 1'),
      findsOne,
    );
    await closeReport(tester);
    // Its own album is now the unknown folder.
    expect(find.text('Expected: Artist'), findsNothing);
    expect(find.text('Expected: Album'), findsOne);
    // Both values joined the known values.
    final known = (await tester.runAsync(
      () => h.catalog.knownValuesOf(library),
    ))!.values;
    expect(known.map((v) => v.value), containsAll(['Artist', 'Stranger']));
    expect(
      known.firstWhere((v) => v.value == 'Artist').children.map((v) => v.value),
      contains('Singles'),
    );

    // Projects of member and status subfolders are lifted into version
    // folders by #148.
  });

  testWidgets('merges a folder moved onto an existing one', (tester) async {
    // The same title found under its album and under an album folder
    // placed at the artist level, with media of the same names.
    h.copyCleanProject('Band/Artist/Album/Song/v1/v1.rpp');
    h.copyCleanProject('Band/Album/Song/v1/v1.rpp');
    h.copyCleanProject('Band/Album/Ballad/v1/v1.rpp');
    await start(tester);
    await openToSort(tester);

    // Announced in the preview.
    await openSectionFix(tester, 'FOLDERS AT THE WRONG LEVEL · 1');
    expect(
      find.text('→ Artist/Album · merged with the existing folder'),
      findsOne,
    );
    await confirmFix(tester, h);
    expect(find.text('Folders merged into an existing folder · 1'), findsOne);
    expect(find.textContaining('Renamed on merge'), findsOne);
    await closeReport(tester);

    // The projects of both folders are versions of one title, in one
    // version folder (#147 reports it); the moved project follows its
    // renamed media.
    final song = h.path('Band/Artist/Album/Song/v1');
    expect(File(p.join(song, 'v1.rpp')).existsSync(), isTrue);
    final moved = File(p.join(song, 'v1 (2).rpp'));
    expect(moved.existsSync(), isTrue);
    expect(moved.readAsStringSync(), contains('01-261108_1921 (2).wav'));
    expect(
      File(p.join(song, 'Media', '01-261108_1921 (2).wav')).existsSync(),
      isTrue,
    );
    expect(
      File(h.path('Band/Artist/Album/Ballad/v1/v1.rpp')).existsSync(),
      isTrue,
    );
    // What is left of the moved folder is kept in the migration folder.
    expect(Directory(h.path('Band/Album')).existsSync(), isFalse);
    final migrations = Directory(h.path('Band/.migration')).listSync();
    expect(
      Directory(p.join(migrations.single.path, 'merged', 'Album')).existsSync(),
      isTrue,
    );
    expect(find.text('FOLDERS AT THE WRONG LEVEL · 1'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(TitleCard, 'Song'),
        matching: find.textContaining('VER 2'),
      ),
      findsOne,
    );
  });
}
