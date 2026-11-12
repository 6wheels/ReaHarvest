import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/ui/to_sort_page.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'harness.dart';

/// "To sort" of a misorganized folder: typed issues with a counter per
/// kind, their expected level and proposed place (#67); items selected
/// across a section, kept through a rescan, fixed in bulk (#82). SPEC
/// §5.2, §5.8 steps 3 and 4: `flutter test integration_test/to_sort_test.dart
/// -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  /// Scrolls the "To sort" list from its top until [finder] is built and
  /// visible: the list only builds the items near the screen.
  Future<void> show(WidgetTester tester, Finder finder) async {
    final list = find
        .descendant(
          of: find.byType(ToSortPage),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    while (finder.evaluate().isEmpty) {
      if (position.pixels >= position.maxScrollExtent) fail('Not found');
      position.jumpTo(position.pixels + 200);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }

  /// Header row of the section labelled [label].
  Finder section(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Row)).first;

  /// Checkbox of the item [title].
  Finder box(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
    matching: find.byType(Checkbox),
  );

  bool? checked(WidgetTester tester, Finder checkbox) =>
      tester.widget<Checkbox>(checkbox).value;

  /// Rescans every library from the page, and waits for the end.
  Future<void> fullScan(WidgetTester tester) async {
    final before = h.tasks.length;
    await tester.tap(find.text('Full scan'));
    await waitFor(
      tester,
      () => h.tasks.length > before && !h.tasks.last.isRunning,
      reason: 'rescanned',
    );
  }

  testWidgets('lists typed issues and fixes a selection in bulk', (
    tester,
  ) async {
    for (final path in [
      'Band/Artist/Album/Song/v1.rpp',
      // Member and status subfolders.
      'Band/Artist/Album/Song/Alice/take.rpp',
      'Band/Artist/Album/Song/mix/final.rpp',
      // An album at the artist level.
      'Band/Album/Ballad/v1.rpp',
      // Titles right under the artist.
      'Band/Artist/Lonely/v1.rpp',
      'Band/Artist/Single/v1.rpp',
      'Band/Artist/Bside/v1.rpp',
      // An artist that is not a known value.
      'Band/Stranger/Live/Tune/v1.rpp',
      'Band/Artist/Album/Hymn/v1.rpp',
    ]) {
      h.copyCleanProject(path);
    }
    h.copyFixture('render.rpp', 'Band/Artist/loose.rpp');
    // A version and its Save As copy.
    final hymn = File(h.path('Band/Artist/Album/Hymn/v1.rpp'));
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
    hymn.copySync(h.path('Band/Artist/Album/Hymn/v1 copy.rpp'));
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
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();

    // One section per kind, with its counter; folders and projects with
    // their expected level and proposed place.
    const tooHigh = 'TITLES PLACED TOO HIGH · 3';
    for (final (header, lines) in [
      (tooHigh, ['Proposed place: Artist/_Unassigned/Lonely']),
      (
        'FOLDERS AT THE WRONG LEVEL · 1',
        ['Expected: Album', 'Proposed place: Artist/Album'],
      ),
      (
        'UNKNOWN FOLDERS: DECLARE THEM IN THE LIBRARY SETTINGS, OR MOVE THEM '
            '· 1',
        ['Expected: Artist'],
      ),
      (
        'PROJECTS TOO DEEP (MEMBER OR STATUS SUBFOLDER) · 2',
        ['take.rpp', 'final.rpp', 'Proposed place: Artist/Album/Song'],
      ),
      ('PROJECTS ABOVE THE TITLE LEVEL · 1', ['loose.rpp']),
      ('COPIES OF THE SAME VERSION (SAVE AS) · 2', ['v1 copy.rpp']),
    ]) {
      await show(tester, find.text(header));
      for (final line in lines) {
        await show(tester, find.text(line));
      }
    }

    // Two items of a section selected, with their counter; "select all"
    // is then partly checked.
    await show(tester, find.text(tooHigh));
    final all = find.descendant(
      of: section(tooHigh),
      matching: find.byType(Checkbox),
    );
    await tester.tap(box('Lonely'));
    await tester.pumpAndSettle();
    await show(tester, box('Single'));
    await tester.tap(box('Single'));
    await tester.pumpAndSettle();
    await show(tester, find.text(tooHigh));
    expect(find.text('2 selected'), findsOne);
    expect(checked(tester, all), isNull);
    // Select all, then none.
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOne);
    expect(checked(tester, all), isTrue);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
    await tester.tap(box('Lonely'));
    await show(tester, box('Single'));
    await tester.tap(box('Single'));
    await tester.pumpAndSettle();

    // The selection is kept through a rescan.
    await fullScan(tester);
    await show(tester, find.text(tooHigh));
    expect(find.text('2 selected'), findsOne);
    expect(checked(tester, box('Lonely')), isTrue);
    expect(checked(tester, box('Bside')), isFalse);

    // "Fix…" previews the selected items only, then fixes them.
    await tester.tap(
      find.descendant(of: section(tooHigh), matching: find.text('Fix…')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Artist/Lonely'), findsOne);
    expect(find.text('Artist/Single'), findsOne);
    expect(find.text('Artist/Bside'), findsNothing);
    expect(find.text('→ Artist/_Unassigned/Lonely'), findsOne);
    await tapText(tester, 'Fix 2 items');
    await waitForText(tester, 'Folders moved · 2');
    expect(find.textContaining('Files missing or changed'), findsNothing);
    await tapText(tester, 'Close');
    await waitForText(tester, 'TITLES PLACED TOO HIGH · 1');
    // The fixed items left the selection.
    expect(find.textContaining('selected'), findsNothing);
    for (final name in ['Lonely', 'Single']) {
      expect(
        File(h.path('Band/Artist/_Unassigned/$name/v1.rpp')).existsSync(),
        isTrue,
      );
    }
    expect(File(h.path('Band/Artist/Bside/v1.rpp')).existsSync(), isTrue);
  });
}
