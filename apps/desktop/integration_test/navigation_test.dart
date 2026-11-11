import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/ui/filter_bar.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest/ui/title_detail.dart';
import 'package:reaharvest/ui/title_views.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'harness.dart';

/// Search, filters, display modes and saved views kept after a restart;
/// overview dock and back navigation from the title detail (SPEC §5.2,
/// #59): `flutter test integration_test/navigation_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  Finder search() =>
      find.widgetWithText(TextField, 'Search titles, tags, versions…');
  Finder chip(String label) => find.widgetWithText(Pill, label);

  /// Names of the title cards shown.
  Set<String> cards(WidgetTester tester) => {
    for (final c in tester.widgetList<TitleCard>(find.byType(TitleCard)))
      titleName(c.title),
  };

  Future<void> showsCards(WidgetTester tester, Set<String> names) => waitFor(
    tester,
    () =>
        cards(tester).length == names.length &&
        cards(tester).containsAll(names),
    reason: '$names',
  );

  testWidgets('keeps search, filters, views and modes after a restart', (
    tester,
  ) async {
    for (final title in [
      'Artist/Album/Song',
      'Artist/Album/Ballad',
      'Other/Live/Encore',
    ]) {
      h.copyCleanProject('Band/$title/v1.rpp');
    }
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(tester, 'Band', Layout.classic());
    await showsCards(tester, {'Song', 'Ballad', 'Encore'});

    // Search.
    await tester.enterText(search(), 'ballad');
    await showsCards(tester, {'Ballad'});
    await tester.enterText(search(), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No title matches “zzz”'), findsOne);
    await tester.enterText(search(), '');
    await showsCards(tester, {'Song', 'Ballad', 'Encore'});

    // Tag filter, saved as a view.
    await tester.tap(chip('Artist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Other'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Artist: Other'));
    await tester.pumpAndSettle();
    await showsCards(tester, {'Encore'});
    await tester.tap(chip('Views'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Save current view…');
    await tester.enterText(dialogField('View name'), 'Live');
    await tapText(tester, 'Save');
    await tapText(tester, 'Clear filters');
    await showsCards(tester, {'Song', 'Ballad', 'Encore'});

    // List: a click on a row opens the overview, pinned below the titles.
    await tapTooltip(tester, 'List');
    expect(find.byType(TitleList), findsOne);
    await tapText(tester, 'Song');
    expect(find.byType(Overview), findsOne);
    expect(find.text('RECENT VERSIONS'), findsOne);
    await tapTooltip(tester, 'Pin below the titles');
    expect(h.settings.navigation.overviewPinned, isTrue);

    // Title detail, and back with Escape, the back button or the mouse.
    Future<void> openDetail() async {
      await tester.tap(
        find.descendant(
          of: find.byType(Overview),
          matching: find.byTooltip('Open detail'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TitleDetailPage), findsOne);
    }

    Future<void> isBack() async {
      await tester.pumpAndSettle();
      expect(find.byType(TitleDetailPage), findsNothing);
      expect(find.byType(TitleList), findsOne);
      expect(find.byType(Overview), findsOne);
    }

    await openDetail();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await isBack();
    await openDetail();
    await tapTooltip(tester, 'Back');
    await isBack();
    await openDetail();
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await mouse.down(tester.getCenter(find.byType(TitleDetailPage)));
    await mouse.up();
    await isBack();
    // Enter in the search bar opens the detail of the overview title.
    await tester.enterText(search(), 'son');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsOne);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await isBack();
    expect(find.widgetWithText(TextField, 'son'), findsOne);
    // The query is saved once typing pauses.
    await waitFor(
      tester,
      () => h.settings.navigation.query == 'son',
      reason: 'query saved',
    );

    // Everything is back after a restart.
    await h.restart(tester);
    expect(find.widgetWithText(TextField, 'son'), findsOne);
    expect(find.byType(TitleList), findsOne);
    expect(find.text('Song'), findsOne);
    expect(find.text('Ballad'), findsNothing);
    final navigation = h.settings.navigation;
    expect(navigation.displayMode, DisplayMode.list);
    expect(navigation.overviewPinned, isTrue);
    await tester.tap(chip('Views'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Live');
    await tester.pumpAndSettle();
    expect(find.text('Encore'), findsOne);
    expect(find.text('Song'), findsNothing);
    expect(chip('Artist: Other'), findsOne);
    expect(find.widgetWithText(TextField, 'son'), findsNothing);
    await tapTooltip(tester, 'Cards');
    await showsCards(tester, {'Encore'});
  });
}
