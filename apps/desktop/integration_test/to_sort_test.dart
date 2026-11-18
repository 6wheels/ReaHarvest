import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'harness.dart';

/// "To sort" of a misorganized folder: typed issues with a counter per
/// kind, their expected level and proposed place (#67); their fixes are
/// offered per title candidate by #149. SPEC
/// §5.2, §5.8 steps 3 and 4: `flutter test integration_test/to_sort_test.dart
/// -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  testWidgets('lists typed issues', (tester) async {
    for (final path in [
      'Band/Artist/Album/Song/v1/v1.rpp',
      // Member and status subfolders in a version folder.
      'Band/Artist/Album/Song/v1/Alice/take.rpp',
      'Band/Artist/Album/Song/v1/mix/final.rpp',
      // An album at the artist level.
      'Band/Album/Ballad/v1/v1.rpp',
      // Titles right under the artist.
      'Band/Artist/Lonely/v1/v1.rpp',
      'Band/Artist/Single/v1/v1.rpp',
      'Band/Artist/Bside/v1/v1.rpp',
      // An artist that is not a known value.
      'Band/Stranger/Live/Tune/v1/v1.rpp',
      'Band/Artist/Album/Hymn/v1/v1.rpp',
    ]) {
      h.copyCleanProject(path);
    }
    h.copyFixture('render.rpp', 'Band/Artist/loose.rpp');
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
        'PROJECTS BELOW A VERSION FOLDER · 2',
        ['take.rpp', 'final.rpp', 'Proposed place: Artist/Album/Song'],
      ),
      ('PROJECTS ABOVE THE TITLE LEVEL · 1', ['loose.rpp']),
      ('COPIES OF THE SAME VERSION (SAVE AS) · 2', ['v1 copy.rpp']),
    ]) {
      await showToSort(tester, find.text(header));
      for (final line in lines) {
        await showToSort(tester, find.text(line));
      }
    }

    // Fixed from the page of #149: no fix offered meanwhile.
    expect(find.text('Fix…'), findsNothing);
  });
}
