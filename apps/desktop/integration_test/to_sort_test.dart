import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:reaharvest/ui/to_sort/outside_file.dart';
import 'package:reaharvest/ui/to_sort/to_sort_page.dart';
import 'package:reaharvest/ui/to_sort/candidate_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'harness.dart';

/// "To sort" of a misorganized folder, title-oriented (#149): one card per
/// title candidate with what is wrong and the fix proposed for it, the
/// files outside any title apart; a card fixed from the page, a file
/// attached to the Unsorted folder of a title. SPEC §5.2, §5.8 steps 3 and
/// 4: `flutter test integration_test/to_sort_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  /// [finder] in the "To sort" page, not in the library under it.
  Finder inPage(Finder finder) =>
      find.descendant(of: find.byType(ToSortPage), matching: finder);

  /// Confirms the preview of the fixes, then waits for the end of their
  /// batch, whose report opens.
  Future<void> confirm(WidgetTester tester) async {
    final before = h.tasks.length;
    // In the preview, not the task of a previous batch.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Fix 1 item'),
      ),
    );
    await waitFor(
      tester,
      () => h.tasks.length > before && !h.tasks[before].isRunning,
      reason: 'batch done',
    );
  }

  testWidgets('lists the title candidates, fixes them from their card', (
    tester,
  ) async {
    for (final path in [
      'Band/Artist/Album/Song/v1/v1.rpp',
      // Member and status subfolders in a version folder.
      'Band/Artist/Album/Song/v1/Alice/take.rpp',
      'Band/Artist/Album/Song/v1/mix/final.rpp',
      // An album at the artist level.
      'Band/Album/Ballad/v1/v1.rpp',
      // A title right under the artist.
      'Band/Artist/Lonely/v1/v1.rpp',
      // An artist that is not a known value.
      'Band/Stranger/Live/Tune/v1/v1.rpp',
      'Band/Artist/Album/Hymn/v1/v1.rpp',
    ]) {
      h.copyCleanProject(path);
    }
    h.copyFixture('render.rpp', 'Band/Artist/loose.rpp');
    // A document beside the titles.
    File(h.path('Band/Artist/notes.txt')).writeAsStringSync('notes');
    // A version and its Save As copy.
    final hymn = File(h.path('Band/Artist/Album/Hymn/v1/v1.rpp'));
    hymn.writeAsStringSync(
      setExtState(
        hymn.readAsStringSync(),
        VersionMetadata.section,
        VersionMetadata(
          id: VersionId.generate(),
          owner: MemberId.generate(),
        ).toExtState(),
      ),
    );
    hymn.copySync(h.path('Band/Artist/Album/Hymn/v1/v1 copy.rpp'));
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
    await tester.tap(find.textContaining('TO SORT //'));
    await tester.pumpAndSettle();

    // One card per candidate: what is wrong, the fix proposed.
    for (final line in [
      'Titles placed too high · 1',
      'Organize into version folders at Artist/_Unassigned/Lonely',
      'Folders at the wrong level · 1',
      'Organize into version folders at Artist/Album/Ballad',
      'Move Album → Artist/Album',
      'Projects below a version folder · 2',
      'Projects above the title level · 1',
      'Organize into version folders at Artist/_Unassigned/loose',
      'Copies of the same version (Save As) · 2',
      'Unknown folders: declare them in the library settings, or move them '
          '· 1',
    ]) {
      await showToSort(tester, inPage(find.text(line)));
    }
    // The files outside any title, apart.
    await showToSort(tester, inPage(find.text('FILES OUTSIDE ANY TITLE · 1')));
    expect(inPage(find.text('notes.txt')), findsOne);

    // The title placed too high, selected, its label changed, fixed.
    await showToSort(tester, inPage(find.text('Lonely')));
    await tester.tap(inPage(find.text('Lonely')));
    await tester.pumpAndSettle();
    final label = find.descendant(
      of: find.ancestor(
        of: inPage(find.text('Lonely')),
        matching: find.byType(CandidateCard),
      ),
      matching: find.byType(TextField),
    );
    await tester.enterText(label.first, 'First take');
    await tester.pumpAndSettle();
    await showToSort(tester, inPage(find.text('1 selected')));
    await tapText(tester, 'Fix…');
    await confirm(tester);
    expect(find.text('Folders moved · 1'), findsOne);
    await tapText(tester, 'Close');
    expect(
      File(h.path('Band/Artist/_Unassigned/Lonely/v1/v1.rpp')).existsSync(),
      isTrue,
    );
    expect(
      File(h.path('Band/Artist/_Unassigned/Lonely/.node.json'))
          .readAsStringSync(),
      contains('First take'),
    );
    expect(inPage(find.text('Lonely')), findsNothing);

    // The document attached to a title: moved into its Unsorted folder.
    await showToSort(tester, inPage(find.text('notes.txt')));
    final title = find.descendant(
      of: find.byType(OutsideFile),
      matching: find.byType(TextField),
    );
    await tester.enterText(title, 'artist/album/song');
    await tester.pumpAndSettle();
    await tapText(tester, 'Attach');
    await confirm(tester);
    expect(
      find.text('Files moved into the Unsorted folder of a title · 1'),
      findsOne,
    );
    await tapText(tester, 'Close');
    expect(
      File(h.path('Band/Artist/Album/Song/Unsorted/notes.txt')).existsSync(),
      isTrue,
    );
    expect(File(h.path('Band/Artist/notes.txt')).existsSync(), isFalse);
    expect(inPage(find.text('notes.txt')), findsNothing);
  });
}
