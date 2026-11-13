import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'harness.dart';

/// Tasks of one library run one at a time: a batch asked while the library
/// is busy waits, queued and cancellable, in the tasks zone (SPEC §5.2,
/// #101): `flutter test integration_test/library_turns_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  const wrongLevel = 'FOLDERS AT THE WRONG LEVEL · 1';

  testWidgets('a batch waits for the turn of its library, cancellable', (
    tester,
  ) async {
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
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
    final library = h.settings.libraries.single.id;
    final moved = h.path('Band/Artist/Live/Ballad/v1.rpp');

    // Another writer holds the turn of the library.
    var hold = Completer<void>();
    final turns = h.container.read(libraryTurnsProvider);
    var holding = turns.run(library, () => hold.future);

    // Asked meanwhile: shown at once, waiting, then cancelled before it
    // starts; nothing moved.
    final before = h.tasks.length;
    await openSectionFix(tester, wrongLevel);
    await tester.tap(find.widgetWithText(FilledButton, 'Fix 1 item'));
    await waitFor(
      tester,
      () => h.tasks.length > before && h.tasks.last.isQueued,
      reason: 'queued',
    );
    expect(find.text('Fix 1 item  ·  Waiting'), findsOne);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
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
    await openSectionFix(tester, wrongLevel);
    await tester.tap(find.widgetWithText(FilledButton, 'Fix 1 item'));
    await waitFor(
      tester,
      () => h.tasks.length > queued && h.tasks.last.isQueued,
      reason: 'queued again',
    );
    hold.complete();
    await tester.runAsync(() => holding);
    await waitFor(tester, () => h.tasks.last.isFinished, reason: 'batch done');
    expect(h.tasks.last.state, TaskState.done);
    expect(find.text('Folders moved · 1'), findsOne);
    await tapText(tester, 'Close');
    expect(File(moved).existsSync(), isTrue);
  });
}
