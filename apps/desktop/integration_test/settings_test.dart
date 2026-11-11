import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/ui/first_run_wizard.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'harness.dart';

/// First-run wizard and settings popup (SPEC §5.1, #59):
/// `flutter test integration_test/settings_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() {
    h = Harness();
    // Peak files next to the projects: the wizard warns about it.
    writeReaperIni(h.resources, recommended: false);
    h.copyFixture('tracks.rpp', 'Band/Artist/Album/Song/v1.rpp');
  });

  tearDown(() => h.dispose());

  /// "Choose…" button of the REAPER path row [index] (application,
  /// resource folder, project templates).
  Future<void> choosePath(WidgetTester tester, int index, String path) async {
    h.picks.add(path);
    await tester.tap(find.text('Choose…').at(index));
    await tester.pumpAndSettle();
  }

  testWidgets('first run sets up the member, a library and REAPER', (
    tester,
  ) async {
    final band = h.path('Band');
    final resources = h.path('Other REAPER');
    Directory(resources).createSync();
    writeReaperIni(resources, recommended: true);
    final templates = h.path('Templates');
    Directory(templates).createSync();
    final executable = h.path('Apps/reaper.exe');

    // No settings file: first run.
    await h.start(tester);
    expect(find.byType(FirstRunWizard), findsOne);
    expect(find.text('STEP 1 OF 3'), findsOne);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tapText(tester, 'Continue');

    // First library, scanned as soon as it is created.
    expect(find.text('Your first library'), findsOne);
    h.picks.add(band);
    await tapText(tester, 'Choose…');
    expect(find.text(band), findsOne);
    expect(find.text('Classic'), findsOne);
    await tapText(tester, 'Create library');
    await waitForText(tester, 'Libraries scanned · 1');
    await tapText(tester, 'Close');

    // REAPER: detected application, default resource folder and templates.
    expect(find.text('STEP 3 OF 3'), findsOne);
    expect(find.text(h.detectedReaper!), findsOne);
    expect(find.text(h.resources), findsOne);
    expect(find.text(p.join(h.resources, 'ProjectTemplates')), findsOne);
    expect(find.textContaining('alternate path'), findsOne);
    // Another resource folder, where the peaks are centralized.
    await choosePath(tester, 1, resources);
    await waitFor(
      tester,
      () => find.textContaining('alternate path').evaluate().isEmpty,
      reason: 'peaks warning gone',
    );
    expect(find.text(p.join(resources, 'ProjectTemplates')), findsOne);
    await choosePath(tester, 2, templates);
    expect(find.text(templates), findsOne);
    await choosePath(tester, 0, executable);
    expect(find.text(executable), findsOne);
    // The application row comes first.
    await tester.tap(find.byTooltip('Reset to default').first);
    await waitForText(tester, h.detectedReaper!);
    await tapText(tester, 'Finish');
    expect(find.byType(FirstRunWizard), findsNothing);
    expect(find.widgetWithText(TitleCard, 'Song'), findsOne);

    // Settings popup.
    await tapTooltip(tester, 'Settings');
    expect(find.text('APPEARANCE'), findsOne);
    expect(find.text(band), findsOne);
    await tester.enterText(find.widgetWithText(TextField, 'Alice'), 'Alice B');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tapText(tester, 'Dark');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    // One tap at the end of the slider: a drag saves the settings once per
    // step, concurrently (reported on #59).
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(slider.centerRight - const Offset(4, 0));
    await tester.pumpAndSettle();
    expect(h.settings.textScale, 1.3);
    await tester.ensureVisible(find.text(h.logs));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Open'));
    expect(h.openedFolders, [h.logs]);
    await tester.ensureVisible(find.text('Français'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(find.text('APPARENCE'), findsOne);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Everything is saved, and found again on the next start.
    final saved = (await tester.runAsync(h.savedSettings))!;
    expect(saved.identity.displayName, 'Alice B');
    expect(saved.libraries.single.workspaceRoot, band);
    expect(saved.reaperExecutable, isNull);
    expect(saved.reaperResources, resources);
    expect(saved.templatesFolder, templates);
    expect(saved.theme, ThemePreference.dark);
    expect(saved.textScale, 1.3);
    expect(saved.language, 'fr');
    await h.restart(tester);
    expect(find.byType(FirstRunWizard), findsNothing);
    expect(find.widgetWithText(TitleCard, 'Song'), findsOne);
    await tapTooltip(tester, 'Paramètres');
    expect(find.text('APPARENCE'), findsOne);
    expect(find.widgetWithText(TextField, 'Alice B'), findsOne);
  });

  testWidgets('first run can be postponed until the next start', (
    tester,
  ) async {
    await h.start(tester);
    await tapText(tester, 'Later');
    expect(find.byType(FirstRunWizard), findsNothing);
    expect(find.text('Your library is empty'), findsOne);

    // Still no library: the wizard is offered again.
    await h.restart(tester);
    expect(find.byType(FirstRunWizard), findsOne);
  });
}
