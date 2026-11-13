import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest/ui/title_detail.dart';
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

  /// Version id written in the project [relative] of the library, or null.
  String? versionId(String relative) => RegExp(
    r'^\s*VERSIONID (\S+)',
    multiLine: true,
  ).firstMatch(File(h.path('Band/$relative')).readAsStringSync())?.group(1);

  /// Opens the "To sort" page.
  Future<void> openToSort(WidgetTester tester) async {
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
  }

  /// Closes the report of the batch, which must have found no gap.
  Future<void> closeReport(WidgetTester tester) async {
    expect(find.textContaining(lost), findsNothing);
    await tapText(tester, 'Close');
  }

  testWidgets('moves folders to their place and projects up their title', (
    tester,
  ) async {
    for (final path in [
      'Band/Artist/Album/Song/v1.rpp',
      // Member subfolders, the first one with a taken name, and status
      // subfolders: one known status, one unknown.
      'Band/Artist/Album/Song/Alice/v1.rpp',
      'Band/Artist/Album/Song/mix/final.rpp',
      'Band/Artist/Album/Song/Bob/demo/idea.rpp',
      // A title right under its artist.
      'Band/Artist/Lonely/v1.rpp',
      // An artist that is not a known value.
      'Band/Stranger/Live/Tune/v1.rpp',
    ]) {
      h.copyCleanProject(path);
    }
    await start(tester);
    final library = h.settings.libraries.single;
    final me = h.settings.identity;
    await tester.runAsync(
      () => h.service.setMembers(library, [
        Member(me.memberId, me.displayName),
        Member(MemberId.generate(), 'Alice'),
        Member(MemberId.generate(), 'Bob'),
      ]),
    );
    await tester.pumpAndSettle();
    await openToSort(tester);

    // A title too high, given a value for its missing album.
    await openSectionFix(tester, 'TITLES PLACED TOO HIGH · 1');
    expect(find.text('→ Artist/_Unassigned/Lonely'), findsOne);
    await tester.enterText(dialogField('Album'), 'Singles');
    await tester.pumpAndSettle();
    expect(find.text('→ Artist/Singles/Lonely'), findsOne);
    await confirmFix(tester, h, 1);
    expect(find.text('Folders moved · 1'), findsOne);
    await closeReport(tester);
    expect(
      File(h.path('Band/Artist/Singles/Lonely/v1.rpp')).existsSync(),
      isTrue,
    );

    // An unknown artist kept in place: declared, no longer to sort.
    const unknown =
        'UNKNOWN FOLDERS: DECLARE THEM IN THE LIBRARY SETTINGS, OR MOVE THEM '
        '· 1';
    await openSectionFix(tester, unknown);
    expect(find.text('→ Stranger'), findsOne);
    await confirmFix(tester, h, 1);
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
      () => h.service.knownValuesOf(library),
    ))!.values;
    expect(known.map((v) => v.value), containsAll(['Artist', 'Stranger']));
    expect(
      known.firstWhere((v) => v.value == 'Artist').children.map((v) => v.value),
      contains('Singles'),
    );

    // Member and status subfolders: owner from the member folder, else
    // the default one; status proposed from the status folder.
    await openSectionFix(
      tester,
      'PROJECTS TOO DEEP (MEMBER OR STATUS SUBFOLDER) · 3',
    );
    // The label of each lifted project is its final file name (SPEC §4.2):
    // the title holds a v1.rpp already.
    expect(
      find.text('→ Artist/Album/Song · v1 (2) · Alice · No status'),
      findsOne,
    );
    expect(
      find.text('→ Artist/Album/Song · final · Tester · Mixing'),
      findsOne,
    );
    expect(find.text('→ Artist/Album/Song · idea · Bob · No status'), findsOne);
    await confirmFix(tester, h, 3);
    expect(find.text('Project moved · 3'), findsOne);
    expect(
      find.text('Status folders matching no status: no status set · 1'),
      findsOne,
    );
    await closeReport(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Moved up under free names, and adopted in the move; the project
    // already in place is still to adopt.
    for (final name in ['v1 (2).rpp', 'final.rpp', 'idea.rpp']) {
      expect(versionId('Artist/Album/Song/$name'), isNotNull, reason: name);
    }
    expect(versionId('Artist/Album/Song/v1.rpp'), isNull);
    // Labels and owners in the node file of the title, by final file name;
    // the projects hold their id only.
    final node = jsonDecode(
      File(h.path('Band/Artist/Album/Song/.node.json')).readAsStringSync(),
    ) as Map;
    expect(
      (node['versionLabels'] as Map).values,
      unorderedEquals(['v1 (2)', 'final', 'idea']),
    );
    expect(node['versionOwners'] as Map, hasLength(3));
    expect(
      File(h.path('Band/Artist/Album/Song/final.rpp')).readAsStringSync(),
      isNot(contains('OWNER')),
    );
    expect(
      Directory(h.path('Band/Artist/Album/Song/Alice'))
          .listSync(recursive: true)
          .where((e) => p.extension(e.path) == '.rpp'),
      isEmpty,
    );
    final song = find.widgetWithText(TitleCard, 'Song');
    expect(
      find.descendant(of: song, matching: find.textContaining('1 to adopt')),
      findsOne,
    );
    await tester.tap(song);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsOne);
    for (final owner in ['Alice', 'Bob']) {
      expect(find.textContaining(owner), findsWidgets, reason: owner);
    }
    expect(find.text('Mixing'), findsWidgets);
  });

  testWidgets('merges a folder moved onto an existing one', (tester) async {
    // The same title found under its album and under an album folder
    // placed at the artist level, with media of the same names.
    h.copyCleanProject('Band/Artist/Album/Song/v1.rpp');
    h.copyCleanProject('Band/Album/Song/v1.rpp');
    h.copyCleanProject('Band/Album/Ballad/v1.rpp');
    await start(tester);
    await openToSort(tester);

    // Announced in the preview.
    await openSectionFix(tester, 'FOLDERS AT THE WRONG LEVEL · 1');
    expect(
      find.text('→ Artist/Album · merged with the existing folder'),
      findsOne,
    );
    await confirmFix(tester, h, 1);
    expect(find.text('Folders merged into an existing folder · 1'), findsOne);
    expect(find.textContaining('Renamed on merge'), findsOne);
    await closeReport(tester);

    // The projects of both folders are versions of one title; the moved
    // project follows its renamed media.
    final song = h.path('Band/Artist/Album/Song');
    expect(File(p.join(song, 'v1.rpp')).existsSync(), isTrue);
    final moved = File(p.join(song, 'v1 (2).rpp'));
    expect(moved.existsSync(), isTrue);
    expect(moved.readAsStringSync(), contains('01-261108_1921 (2).wav'));
    expect(
      File(p.join(song, 'Media', '01-261108_1921 (2).wav')).existsSync(),
      isTrue,
    );
    expect(
      File(h.path('Band/Artist/Album/Ballad/v1.rpp')).existsSync(),
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
        matching: find.textContaining('2 versions'),
      ),
      findsOne,
    );
  });
}
