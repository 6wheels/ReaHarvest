import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'harness.dart';

/// Tasks of one library run one at a time: a batch asked while the library
/// is busy waits, queued and cancellable, in its popup and the tasks zone
/// (SPEC §5.2, #101, #150):
/// `flutter test integration_test/library_turns_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  /// The issue line of the title card in "To sort" (#149).
  const wrongLevel = 'Folders at the wrong level · 1';

  testWidgets(
    'a batch waits for the turn of its library, in its popup, cancellable',
    (tester) async {
      h.copyCleanProject('Band/Artist/Album/Song/v1.rpp');
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
      await tester.tap(find.textContaining('TO SORT //'));
      await tester.pumpAndSettle();
      final library = h.settings.libraries.single.id;
      final moved = h.path('Band/Artist/Live/Ballad/v1/v1.rpp');
      final ballad = OrganizeTitle('Live/Ballad', 'Artist/Live/Ballad', [
        const FixVersion('Live/Ballad/v1.rpp', folder: 'v1', label: 'v1'),
      ], level: 'title');

      // Another writer holds the turn of the library.
      var hold = Completer<void>();
      final turns = h.container.read(libraryTurnsProvider);
      var holding = turns.run(library, () => hold.future);

      // Asked meanwhile: shown at once, waiting, then cancelled before it
      // starts; nothing moved.
      final before = h.tasks.length;
      unawaited(h.migration.fix(library, [ballad]));
      await waitFor(
        tester,
        () => h.tasks.length > before && h.tasks.last.isQueued,
        reason: 'queued',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Fix 1 item  ·  Waiting'), findsOne, reason: 'zone');
      final popup = find.byType(AlertDialog);
      expect(
        find.descendant(of: popup, matching: find.text('Fix 1 item')),
        findsOne,
      );
      expect(
        find.descendant(of: popup, matching: find.text('Waiting')),
        findsOne,
      );
      // Cancel asks first; a refusal leaves the task waiting.
      final cancel = find.descendant(of: popup, matching: find.text('Cancel'));
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.text('Cancel this action?'), findsOne);
      await tester.tap(find.text('Keep running'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this action?'), findsNothing);
      expect(h.tasks.last.isQueued, isTrue);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop it'));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(h.tasks.last.state, TaskState.cancelled);
      expect(find.text('Cancelled'), findsOne);
      hold.complete();
      await tester.runAsync(() => holding);
      expect(File(moved).existsSync(), isFalse);
      expect(find.text(wrongLevel), findsOne);

      // Asked again while the turn is held: runs once it is given back.
      hold = Completer<void>();
      holding = turns.run(library, () => hold.future);
      final queued = h.tasks.length;
      unawaited(h.migration.fix(library, [ballad]));
      await waitFor(
        tester,
        () => h.tasks.length > queued && h.tasks.last.isQueued,
        reason: 'queued again',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsOne, reason: 'waits in its popup');
      hold.complete();
      await tester.runAsync(() => holding);
      await waitFor(
        tester,
        () => h.tasks.last.isFinished,
        reason: 'batch done',
      );
      expect(h.tasks.last.state, TaskState.done);
      expect(find.text('Folders moved · 1'), findsOne);
      await tapText(tester, 'Close');
      expect(File(moved).existsSync(), isTrue);
    },
  );
}
