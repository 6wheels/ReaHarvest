import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest/ui/to_sort/version_fields.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'harness.dart';

/// Migration fixes proposed per title candidate by the scan and run as a
/// batch, the inventory check passing (SPEC §5.8 step 4, #148): a title
/// organized into version folders (a project below a version folder, a
/// status subfolder), a title placed too high moved to its position, a
/// loose project moved into a title from its card (#149); every project
/// opens with no new missing media. `flutter test integration_test/migration_fixes_test.dart
/// -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  const lost = 'Files missing or changed since the inventory';

  testWidgets('organizes the titles as proposed by the scan', (tester) async {
    for (final path in [
      'Band/Artist/Album/Song/v1/v1.rpp',
      // A project below a version folder, and one in a status subfolder.
      'Band/Artist/Album/Song/v1/Alice/take.rpp',
      'Band/Artist/Album/Song/mixing/final.rpp',
      // A title right under its artist.
      'Band/Artist/Lonely/v1/v1.rpp',
    ]) {
      h.copyCleanProject(path);
    }
    h.copyFixture('render-file.rpp', 'Band/Artist/Album/loose.rpp');
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
    final id = h.settings.libraries.single.id;
    final library = h.container.read(indexedLibrariesProvider)[id]!;
    final result = h.container.read(localIndexProvider).scanResult(id)!;

    // One fix per candidate with a problem of its folders or position.
    final fixes = [
      for (final candidate in result.candidates)
        if (candidate.root == 'Artist/Album/Song' ||
            candidate.root == 'Artist/Lonely')
          proposeFix(
            candidate,
            library,
            nodes: result.nodes,
            statusLabels: {for (final s in Title.defaultStatuses) s: s},
          ),
    ];
    expect(
      [for (final f in fixes) '${f.path} -> ${f.target}'],
      [
        'Artist/Album/Song -> Artist/Album/Song',
        'Artist/Lonely -> Artist/_Unassigned/Lonely',
      ],
    );
    await runFixes(tester, h, id, fixes);
    // The title placed too high, and the status subfolder holding one
    // project: its version folder.
    expect(find.text('Folders moved · 2'), findsOne);
    expect(find.text('Projects moved into their version folder · 1'), findsOne);
    expect(find.textContaining(lost), findsNothing);
    await tapText(tester, 'Close');

    const song = 'Band/Artist/Album/Song';
    for (final path in [
      '$song/v1/v1.rpp',
      '$song/v1/Media/01-261108_1921.wav',
      '$song/take/take.rpp',
      '$song/take/Media/01-261108_1921.wav',
      '$song/final/final.rpp',
      '$song/final/Media/02-261108_1921.wav',
      'Band/Artist/_Unassigned/Lonely/v1/v1.rpp',
    ]) {
      expect(File(h.path(path)).existsSync(), isTrue, reason: path);
    }
    // The status of its subfolder, in the node file of the title.
    final node = await tester.runAsync(
      () =>
          readNodeFile(MountedFolderStorage(h.path('Band')), song.substring(5)),
    );
    expect(node!.versionStatuses.values, ['mixing']);
    expect(node.versionLabels.values, unorderedEquals(['v1', 'take', 'final']));

    // A loose project moved into the title from its card: "Move this
    // project…" (#149), its label set first.
    await tester.tap(find.textContaining('TO SORT //'));
    await tester.pumpAndSettle();
    final loose = find.ancestor(
      of: find.text('loose.rpp'),
      matching: find.byType(VersionFields),
    );
    await showToSort(tester, loose);
    await tester.enterText(
      find.descendant(of: loose, matching: find.byType(TextField)).first,
      'Loose take',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: loose,
        matching: find.byTooltip('Move this project…'),
      ),
    );
    await tester.pumpAndSettle();
    for (final (level, value) in [
      ('Artist', 'Artist'),
      ('Album', 'Album'),
      ('Title', 'Song'),
    ]) {
      await tester.enterText(dialogField(level), value);
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Fix…'),
      ),
    );
    await tester.pumpAndSettle();
    final before = h.tasks.length;
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Fix 1 item'),
      ),
    );
    await waitFor(
      tester,
      () => h.tasks.length > before && !h.tasks[before].isRunning,
      reason: 'move done',
    );
    expect(find.text('Projects moved into their version folder · 1'), findsOne);
    expect(find.textContaining(lost), findsNothing);
    await tapText(tester, 'Close');
    expect(File(h.path('$song/loose/loose.rpp')).existsSync(), isTrue);

    // Rescanned: the projects are versions of their title, none missing a
    // media, nothing left to sort for them.
    final index = h.container.read(localIndexProvider);
    expect(index.issues(kind: ReportKind.missingMedia), isEmpty);
    expect(index.issues(kind: ReportKind.projectTooDeep), isEmpty);
    expect(index.issues(kind: ReportKind.statusFolder), isEmpty);
    expect(index.issues(kind: ReportKind.titleTooHigh), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(TitleCard, 'Song'),
        matching: find.textContaining('VER 4'),
      ),
      findsOne,
    );
    expect(find.widgetWithText(TitleCard, 'Lonely'), findsOne);
  });
}
