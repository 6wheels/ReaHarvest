import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest/ui/title_detail.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'harness.dart';

/// Opening in REAPER from the card, the overview and the detail, and the
/// warning before a project is changed while REAPER runs (SPEC §5.7, #15,
/// #59): `flutter test integration_test/open_in_reaper_test.dart -d
/// windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  testWidgets('opens versions in REAPER and waits for it to close', (
    tester,
  ) async {
    final older = h.copyCleanProject('Band/Artist/Album/Song/v1.rpp');
    final latest = h.copyCleanProject('Band/Artist/Album/Song/v2.rpp');
    File(older).setLastModifiedSync(DateTime(2026, 1, 1));
    File(latest).setLastModifiedSync(DateTime(2026, 2, 1));
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(tester, 'Band', Layout.classic());
    final reaper = h.detectedReaper!;

    // Quick action of the selected card: the latest version.
    final card = find.widgetWithText(TitleCard, 'Song');
    await tester.tap(card);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Open in REAPER')),
    );
    await waitFor(tester, () => h.launched.length == 1, reason: 'card');
    expect(h.launched.last, (reaper, latest));

    // Recent versions of the overview, the latest first.
    final recent = find.descendant(
      of: find.byType(Overview),
      matching: find.byTooltip('Open in REAPER'),
    );
    expect(recent, findsNWidgets(2));
    await tester.tap(recent.last);
    await waitFor(tester, () => h.launched.length == 2, reason: 'overview');
    expect(h.launched.last, (reaper, older));

    // Selected version of the detail.
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsOne);
    final open = find.widgetWithText(FilledButton, 'Open in REAPER');
    await tester.tap(open);
    await waitFor(tester, () => h.launched.length == 3, reason: 'detail');
    expect(h.launched.last, (reaper, latest));

    // REAPER not found: nothing is launched, the user is told.
    h.detectedReaper = null;
    h.container.invalidate(detectedReaperProvider);
    await tester.tap(open);
    await waitForText(
      tester,
      'REAPER was not found. Set its location in the settings.',
    );
    expect(h.launched, hasLength(3));

    // A project change waits while REAPER runs: cancelled, the file is
    // left as it was.
    final before = File(latest).readAsStringSync();
    h.reaperRunning = true;
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'final');
    await tester.pumpAndSettle();
    final adopt = find.widgetWithText(FilledButton, 'Adopt');
    await tester.tap(adopt);
    await waitForText(tester, 'REAPER is open');
    await tapText(tester, 'Cancel');
    expect(find.text('REAPER is open'), findsNothing);
    expect(File(latest).readAsStringSync(), before);
    expect(adopt, findsOne);

    // REAPER closed: the change goes through.
    h.reaperRunning = false;
    await tester.tap(adopt);
    await waitFor(tester, () => adopt.evaluate().isEmpty, reason: 'adopted');
    expect(find.text('REAPER is open'), findsNothing);
    expect(File(latest).readAsStringSync(), contains('VERSIONID'));
  });
}
