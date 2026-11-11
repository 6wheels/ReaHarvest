import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/ui/filter_bar.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest/ui/title_views.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'harness.dart';

/// Libraries scanned with each layout template and as a free tree: titles,
/// "To sort", tags, level labels in English and French, filters and tree
/// view (SPEC §3, §5.2, #59): `flutter test
/// integration_test/layout_scan_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  Finder card(String name) => find.widgetWithText(TitleCard, name);

  /// Names of the titles shown, scrolled out of view included: the grid
  /// only builds the cards on screen.
  Set<String> cards(WidgetTester tester) => {
    for (final t in h.container.read(visibleTitlesProvider)) titleName(t),
  };

  testWidgets('scans each layout and the free tree', (tester) async {
    // Classic, with an unassigned artist and album, and a project placed
    // above the title level.
    for (final path in [
      'Band/Artist/Album/Song/v1.rpp',
      'Band/Other Artist/Live/Encore/v1.rpp',
      'Band/_Unassigned/_Unassigned/Demo/v1.rpp',
      'Duo/Artist/Hymn/v1.rpp',
      'Movie/Feature/Act 1/Opening/v1.rpp',
      'Movie/Feature/Act 2/Finale/v1.rpp',
      'Movie/Short/Intro/Titles/v1.rpp',
      // Free tree: the topmost folder holding a project is the title, the
      // projects below it are its versions.
      'Sketches/Ideas/Riff/v1.rpp',
      'Sketches/Ideas/Riff/Alice/v2/take.rpp',
    ]) {
      h.copyCleanProject(path);
    }
    h.copyFixture('render.rpp', 'Band/Artist/loose.rpp');
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(tester, 'Band', Layout.classic());
    await h.addLibrary(tester, 'Duo', Layout.projectOriented());
    await h.addLibrary(tester, 'Movie', Layout.film());
    await h.addLibrary(tester, 'Sketches', null);

    // Titles at the leaf level only.
    expect(cards(tester), {
      'Song',
      'Encore',
      'Demo',
      'Hymn',
      'Opening',
      'Finale',
      'Titles',
      'Riff',
    });
    expect(
      find.descendant(
        of: card('Demo'),
        matching: find.textContaining('Unassigned'),
      ),
      findsOne,
    );

    // The misplaced project is to sort.
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
    expect(find.text('PROJECTS ABOVE THE TITLE LEVEL · 1'), findsOne);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // One filter per level, labelled by level; a common key is shared
    // across layouts.
    Finder chip(String label) => find.widgetWithText(Pill, label);
    for (final label in ['Artist', 'Album', 'Project', 'Chapter', 'Library']) {
      expect(chip(label), findsOne, reason: label);
    }
    expect(chip('Title'), findsNothing);
    await tester.tap(chip('Artist'));
    await tester.pumpAndSettle();
    final menu = find.byType(CheckboxMenuButton);
    expect(find.widgetWithText(CheckboxMenuButton, 'Other Artist'), findsOne);
    expect(menu, findsNWidgets(3));
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Unassigned'));
    await tester.pumpAndSettle();
    // The chip closes its menu.
    await tester.tap(chip('Artist: Unassigned'));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    await waitFor(tester, () => cards(tester).length == 1, reason: 'filtered');
    expect(cards(tester), {'Demo'});
    await tapText(tester, 'Clear filters');
    await waitFor(tester, () => cards(tester).length == 8, reason: 'cleared');

    // Tree: libraries, then the levels above the titles; a collapsed group
    // hides what it holds.
    await tapTooltip(tester, 'Tree');
    void shown(List<String> rows) {
      for (final row in rows) {
        expect(find.text(row), findsWidgets, reason: row);
      }
    }

    shown(['Band', 'Artist', 'Album', 'Song', 'Other Artist', 'Unassigned']);
    shown(['Demo', 'Duo']);
    await tapText(tester, 'Band');
    expect(find.text('Demo'), findsNothing);
    await tapText(tester, 'Duo');
    shown(['Movie', 'Feature', 'Act 2', 'Finale', 'Sketches', 'Ideas', 'Riff']);
    // The free tree title holds the projects below it.
    expect(
      find.descendant(
        of: find.widgetWithText(TitleRow, 'Riff'),
        matching: find.text('2 versions'),
      ),
      findsOne,
    );
    // The free tree title holds the projects below it.
    expect(
      find.descendant(
        of: find.widgetWithText(TitleRow, 'Riff'),
        matching: find.text('2 versions'),
      ),
      findsOne,
    );
    await tapText(tester, 'Band');
    expect(find.text('Demo'), findsOne);

    // French labels.
    await tapTooltip(tester, 'Settings');
    await tester.ensureVisible(find.text('Français'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    for (final label in [
      'Artiste',
      'Album',
      'Projet',
      'Chapitre',
      'Bibliothèque',
    ]) {
      expect(chip(label), findsOne, reason: label);
    }
    expect(find.text('Non classé'), findsWidgets);
    expect(find.textContaining('À ranger ·'), findsOne);
  });
}
