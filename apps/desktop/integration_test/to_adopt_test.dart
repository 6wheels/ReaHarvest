import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/ui/filter_bar.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest/ui/title_detail.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'harness.dart';

/// "To adopt": counter of titles, number of versions to adopt on the card,
/// overview and detail (#80), adoption in the title detail, Save As
/// duplicates made new versions (SPEC §4.2, §5.2, #59): `flutter test
/// integration_test/to_adopt_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  /// Version id written in the project [path], or null.
  String? versionId(String path) => RegExp(
    r'^\s*VERSIONID (\S+)',
    multiLine: true,
  ).firstMatch(File(path).readAsStringSync())?.group(1);

  /// Names of the title cards shown.
  Set<String> cards(WidgetTester tester) => {
    for (final c in tester.widgetList<TitleCard>(find.byType(TitleCard)))
      titleName(c.title),
  };

  /// Opens the detail of the title shown in the overview.
  Future<void> openOverviewDetail(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsOne);
  }

  /// Opens the detail of the title [name] from its card and its overview.
  Future<void> openDetail(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(TitleCard, name));
    await tester.pumpAndSettle();
    await openOverviewDetail(tester);
  }

  /// Back to the library with Escape, also after an adoption, whose form
  /// leaves with the focus (#59).
  Future<void> back(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsNothing);
  }

  /// Adopts the selected version of the open detail as [label].
  Future<void> adopt(WidgetTester tester, String label) async {
    await tester.enterText(find.widgetWithText(TextField, 'Label'), label);
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Adopt');
    await tester.tap(button);
    // The adoption form leaves with the rescan.
    await waitFor(tester, () => button.evaluate().isEmpty, reason: label);
    expect(find.text(label), findsWidgets);
  }

  testWidgets('adopts versions and separates Save As copies', (tester) async {
    final song = h.copyCleanProject('Band/Artist/Album/Song/v1.rpp');
    h.copyCleanProject('Band/Artist/Album/Song/v2.rpp');
    final ballad = h.copyCleanProject('Band/Artist/Album/Ballad/v1.rpp');
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(tester, 'Band', Layout.classic());

    // Counter of titles, number of versions to adopt on the card.
    expect(find.widgetWithText(Pill, 'To adopt · 2'), findsOne);
    expect(
      find.descendant(
        of: find.widgetWithText(TitleCard, 'Song'),
        matching: find.textContaining('2 to adopt'),
      ),
      findsOne,
    );

    // Adoption in the detail, on the selected version.
    await openDetail(tester, 'Ballad');
    expect(find.text('v1.rpp'), findsOne);
    expect(find.text('Not adopted'), findsWidgets);
    await adopt(tester, 'first take');
    expect(find.text('Not adopted'), findsNothing);
    // Nothing left to adopt: no count in the header.
    expect(find.textContaining('not adopted'), findsNothing);
    expect(versionId(ballad), isNotNull);
    await back(tester);

    // The filter keeps the titles having a version to adopt.
    final pill = find.widgetWithText(Pill, 'To adopt · 1');
    expect(pill, findsOne);
    await tester.tap(pill);
    await waitFor(tester, () => cards(tester).length == 1, reason: 'filter');
    expect(cards(tester), {'Song'});
    await tester.tap(pill);
    await waitFor(tester, () => cards(tester).length == 2, reason: 'all');

    // A Save As copy of an adopted version shares its identity. The
    // number of versions to adopt is in the overview and the detail header
    // (#80).
    await tester.tap(find.widgetWithText(TitleCard, 'Song'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Overview),
        matching: find.text('2 versions not adopted'),
      ),
      findsOne,
    );
    await openOverviewDetail(tester);
    expect(find.text('2 versions not adopted'), findsOne);
    // Not adopted versions are listed with their file name.
    await tester.tap(find.textContaining('v1.rpp', findRichText: true).first);
    await tester.pumpAndSettle();
    await adopt(tester, 'intro');
    expect(find.text('1 version not adopted'), findsOne);
    await back(tester);
    File(song).copySync(h.path('Band/Artist/Album/Song/v1 copy.rpp'));
    final copy = h.path('Band/Artist/Album/Song/v1 copy.rpp');
    final before = h.tasks.length;
    final scanning = h.service.scanAll();
    await waitFor(
      tester,
      () => h.tasks.length > before && !h.tasks.last.isRunning,
      reason: 'rescanned',
    );
    await scanning;
    // The overview of the title is still open.
    expect(find.text('2 duplicated versions'), findsOne);
    await openOverviewDetail(tester);
    expect(find.textContaining('Same identity as'), findsOne);
    await tapText(tester, 'Make it a new version');
    await waitFor(
      tester,
      () => find.textContaining('Same identity as').evaluate().isEmpty,
      reason: 'separated',
    );
    expect(versionId(copy), isNot(versionId(song)));
    // Its label is kept.
    expect(find.text('intro'), findsAtLeastNWidgets(2));
    await back(tester);
    expect(find.widgetWithText(Pill, 'To adopt · 1'), findsOne);
  });
}
