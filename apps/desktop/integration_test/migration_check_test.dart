import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'harness.dart';

/// No-loss guard of the migration fixes: inventory before the first
/// change, originals kept before a rewrite, check after the batch (#66);
/// an interrupted inventory resumed by the next batch, a file changed
/// during a batch reported as an error (SPEC §5.8 steps 2 and 5):
/// `flutter test integration_test/migration_check_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  const lost = 'Files missing or changed since the inventory';
  const wrongLevel = 'FOLDERS AT THE WRONG LEVEL · 1';
  const tooDeep = 'PROJECTS TOO DEEP (MEMBER OR STATUS SUBFOLDER) · 1';

  String band() => h.path('Band');

  /// A title in place, a project in a member subfolder, an album at the
  /// artist level, then the app started on the library.
  Future<void> start(WidgetTester tester) async {
    h.copyCleanProject('Band/Artist/Album/Song/v1.rpp');
    h.copyCleanProject('Band/Artist/Album/Song/Alice/take.rpp');
    h.copyCleanProject('Band/Live/Ballad/v1.rpp');
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(
      tester,
      'Band',
      Layout.classic(),
      knownValues: const [
        KnownValue('Artist', [KnownValue('Album'), KnownValue('Live')]),
      ],
    );
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
  }

  /// Latest migration of the library.
  Future<Migration?> latest(WidgetTester tester) => tester.runAsync<Migration?>(
    () => Migration.latest(MountedFolderStorage(band())),
  );

  /// Migration folders of the library, one per batch.
  List<String> migrations() => [
    for (final e in Directory(p.join(band(), '.migration')).listSync())
      if (e is Directory) p.basename(e.path),
  ];

  /// Fixes every item of the section [header] through its preview, and
  /// waits for the report.
  Future<void> fixSection(WidgetTester tester, String header) async {
    final before = h.tasks.length;
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text(header), matching: find.byType(Row))
            .first,
        matching: find.text('Fix…'),
      ),
    );
    await tester.pumpAndSettle();
    // The tasks zone may show an earlier task with the same label.
    await tester.tap(find.widgetWithText(FilledButton, 'Fix 1 item'));
    await waitFor(
      tester,
      () => h.tasks.length > before && !h.tasks[before].isRunning,
      reason: 'batch done',
    );
  }

  testWidgets('inventories, keeps the originals and checks the batch', (
    tester,
  ) async {
    await start(tester);
    final take = h.path('Band/Artist/Album/Song/Alice/take.rpp');
    final original = File(take).readAsBytesSync();

    await fixSection(tester, tooDeep);
    expect(find.text('Project moved · 1'), findsOne);
    expect(find.textContaining(lost), findsNothing);
    expect(h.tasks.last.state, TaskState.done);
    await tapText(tester, 'Close');

    // Every file inventoried before the first change, the library
    // description left out.
    final migration = (await latest(tester))!;
    expect(migration.inventoryComplete, isTrue);
    expect(
      migration.files.keys,
      containsAll([
        'Artist/Album/Song/v1.rpp',
        'Artist/Album/Song/Alice/take.rpp',
        'Artist/Album/Song/Alice/Media/01-261108_1921.wav',
        'Live/Ballad/v1.rpp',
      ]),
    );
    expect(migration.files.keys, isNot(contains('.library.json')));
    // The rewritten project's raw original is kept in the migration.
    expect(File(take).existsSync(), isFalse);
    final kept = [
      for (final f in Directory(
        p.joinAll([band(), ...migration.folder.split('/')]),
      ).listSync(recursive: true))
        if (f is File && p.basename(f.path) == 'take.rpp') f,
    ];
    expect(kept, hasLength(1));
    expect(kept.single.readAsBytesSync(), original);
    expect(migrations(), hasLength(1));
  });

  testWidgets('resumes the inventory of a cancelled batch', (tester) async {
    await start(tester);
    final library = h.settings.libraries.single.id;

    // Cancelled as soon as started: during its inventory, before any fix.
    // Driven through the service, as the cancel button would be tapped too
    // late for a library this small.
    final fixing = h.service.fix(library, [
      const MoveFolder('Live', 'Artist/Live'),
    ]);
    h.container.read(tasksProvider.notifier).cancel(h.tasks.last.id);
    await waitFor(tester, () => !h.tasks.last.isRunning, reason: 'cancelled');
    await fixing;
    expect(h.tasks.last.state, TaskState.cancelled);
    // Its report opens, empty: nothing was done.
    expect(find.text('Nothing to report.'), findsOne);
    await tapText(tester, 'Close');
    expect(File(h.path('Band/Live/Ballad/v1.rpp')).existsSync(), isTrue);
    final interrupted = (await latest(tester))!;
    expect(interrupted.inventoryComplete, isFalse);
    // The item is still to sort.
    expect(find.text(wrongLevel), findsOne);

    // The next batch resumes that inventory instead of starting another.
    await fixSection(tester, wrongLevel);
    expect(find.text('Folders moved · 1'), findsOne);
    expect(find.textContaining(lost), findsNothing);
    await tapText(tester, 'Close');
    expect(File(h.path('Band/Artist/Live/Ballad/v1.rpp')).existsSync(), isTrue);
    final resumed = (await latest(tester))!;
    expect(resumed.folder, interrupted.folder);
    expect(resumed.inventoryComplete, isTrue);
    expect(migrations(), hasLength(1));
  });

  testWidgets('reports a file changed during a batch', (tester) async {
    await start(tester);
    final media = File(
      h.path('Band/Artist/Album/Song/Media/01-261108_1921.wav'),
    );

    // Another member's change lands while the fix runs, after the
    // inventory.
    final en = lookupAppLocalizations(const Locale('en'));
    var changed = false;
    final listening = h.container.listen<List<BackgroundTask>>(tasksProvider, (
      _,
      tasks,
    ) {
      final step = tasks.lastOrNull?.step?.call(en);
      if (!changed && step == 'Fix 1 of 1') {
        changed = true;
        media.writeAsStringSync('changed', mode: FileMode.append);
      }
    });
    addTearDown(listening.close);

    await fixSection(tester, wrongLevel);
    expect(changed, isTrue);
    // The gap is an error: the batch failed, the move it did is kept.
    expect(find.text('$lost · 1'), findsOne);
    expect(h.tasks.last.state, TaskState.failed);
    expect(
      h.tasks.last.report!.items[ReportKind.fileLost]!.single.path,
      endsWith('01-261108_1921.wav'),
    );
    expect(find.text('Folders moved · 1'), findsOne);
    await tapText(tester, 'Close');
    expect(File(h.path('Band/Artist/Live/Ballad/v1.rpp')).existsSync(), isTrue);

    // The next batch takes a fresh inventory, holding the change: no gap.
    await fixSection(tester, tooDeep);
    expect(find.text('Project moved · 1'), findsOne);
    expect(find.textContaining(lost), findsNothing);
    expect(h.tasks.last.state, TaskState.done);
    await tapText(tester, 'Close');
    expect(migrations(), hasLength(2));
  });
}
