import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart' show xxh3Hasher;
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'harness.dart';

/// Interrupted fix offered to be undone at startup and before any other
/// fix of its library, then undone (SPEC §5.8 step 5, #94):
/// `flutter test integration_test/interrupted_fix_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  const title = 'A fix was interrupted';
  const tooDeep = 'PROJECTS TOO DEEP (MEMBER OR STATUS SUBFOLDER) · 1';
  const take = 'Artist/Album/Song/Alice/take.rpp';
  const lifted = 'Artist/Album/Song/take.rpp';

  testWidgets('offers the undo, runs no fix meanwhile, undoes it', (
    tester,
  ) async {
    h.copyCleanProject('Band/Artist/Album/Song/v1.rpp');
    h.copyCleanProject('Band/$take');
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
    final library = h.settings.libraries.single.id;
    final original = File(h.path('Band/$take')).readAsBytesSync();

    // The application stops during a lift, right after its move: its
    // journal has the start of the fix and the move, no end.
    await tester.runAsync(() async {
      final storage = MountedFolderStorage(h.path('Band'));
      final migration = Migration.start(storage);
      await migration.inventory.take(xxh3Hasher(storage));
      await migration.journal.startFix('liftProject', take);
      await migration.storage.move(take, lifted);
    });
    await h.restart(tester);

    // Offered at the end of the startup scan.
    final starting = h.migration.startup();
    await waitForText(tester, title);
    await starting;
    expect(
      find.text(
        'The fix of $take in Band did not finish. Undo it to put its files '
        'back; no other fix can run on this library until then.',
      ),
      findsOne,
    );
    await tapText(tester, 'Later');
    expect(find.text(title), findsNothing);

    // Offered again instead of a new batch.
    final tasks = h.tasks.length;
    final fixing = h.migration.fix(library, [
      const MoveFolder('Live', 'Artist/Live'),
    ]);
    await waitForText(tester, title);
    expect(await fixing, isNull);
    expect(h.tasks.length, tasks);
    expect(File(h.path('Band/Live/Ballad/v1.rpp')).existsSync(), isTrue);

    // Undone, after the warning that REAPER is open: the project back in
    // its member subfolder, nothing lost.
    h.reaperRunning = true;
    await tapText(tester, 'Undo');
    await waitForText(tester, 'REAPER is open');
    expect(h.tasks.length, tasks);
    h.reaperRunning = false;
    await tapText(tester, 'Continue anyway');
    await waitFor(
      tester,
      () => h.tasks.length > tasks && !h.tasks.last.isRunning,
      reason: 'undo done',
    );
    expect(h.tasks.last.state, TaskState.done);
    expect(find.text('Fix undone · 1'), findsOne);
    expect(
      find.textContaining('Files missing or changed since the inventory'),
      findsNothing,
    );
    await tapText(tester, 'Close');
    expect(File(h.path('Band/$take')).readAsBytesSync(), original);
    expect(File(h.path('Band/$lifted')).existsSync(), isFalse);
    expect(
      await tester.runAsync(
        () => unfinishedFixIn(MountedFolderStorage(h.path('Band'))),
      ),
      isNull,
    );

    // Its item is to sort again, and can be fixed.
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
    await openSectionFix(tester, tooDeep);
    await confirmFix(tester, h, 1);
    expect(find.text('Project moved · 1'), findsOne);
    expect(h.tasks.last.state, TaskState.done);
    await tapText(tester, 'Close');
    expect(find.text(title), findsNothing);
  });
}
