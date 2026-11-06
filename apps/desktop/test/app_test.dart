import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/app.dart';
import 'package:reaharvest/demo_titles.dart';
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/state/pickers.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/ui/aurora.dart';
import 'package:reaharvest/ui/first_run_wizard.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';

import 'helpers.dart';

/// Pickers answering with fixed paths.
class FakePickers extends Pickers {
  const FakePickers();

  @override
  Future<String?> folder({String? initial}) async => '/music/Band';

  @override
  Future<String?> reaperExecutable() async => '/apps/reaper';
}

/// Library found in any chosen folder.
Library? existingLibrary;

/// Whether [existingLibrary] holds titles.
var existingLocked = false;

/// Library service recording calls, without file system access.
class FakeLibraryService extends LibraryService {
  FakeLibraryService(super.ref);

  final added = <(String, String, Layout?)>[];
  final removed = <LibraryId>[];

  @override
  Future<Library?> existing(String folder) async => existingLibrary;

  @override
  Future<bool> isLayoutLocked(String folder, Library library) async =>
      existingLocked;

  @override
  Future<void> addLocal({
    required String folder,
    required String displayName,
    required Layout? layout,
  }) async {
    added.add((folder, displayName, layout));
    final entry = LibraryEntry(
      id: LibraryId.generate(),
      displayName: displayName,
      workspaceRoot: folder,
    );
    await ref.read(settingsProvider.notifier).change((s) => s.addLibrary(entry));
  }

  @override
  Future<void> remove(LibraryId id) async {
    removed.add(id);
    await ref.read(settingsProvider.notifier).change((s) => s.removeLibrary(id));
  }
}

void main() {
  late MemorySettings settings;
  late FakeLibraryService libraries;

  const band = LibraryEntry(
    id: LibraryId('L1'),
    displayName: 'Band',
    workspaceRoot: '/music/Old',
  );

  Future<void> pumpApp(
    WidgetTester tester, {
    List<TitleView> titles = const [],
    String language = 'en',
    List<LibraryEntry> configured = const [band],
    PeaksPreference? peaks = const PeaksPreference(
      altPeaks: true,
      altPeaksPath: '/peaks',
    ),
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = MemorySettings();
    existingLibrary = null;
    existingLocked = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            AppSettings(
              identity: const LocalIdentity(MemberId('M'), 'Alice'),
              language: language,
              libraries: configured,
            ),
          ),
          settingsProvider.overrideWith(() => settings),
          titleViewsProvider.overrideWithValue(titles),
          libraryServiceProvider.overrideWith(
            (ref) => libraries = FakeLibraryService(ref),
          ),
          pickersProvider.overrideWithValue(const FakePickers()),
          detectedReaperProvider.overrideWith((ref) async => '/detected/reaper'),
          defaultReaperResourcesProvider.overrideWithValue('/resources'),
          peaksPreferenceProvider.overrideWith((ref) async => peaks),
        ],
        child: const ReaHarvestApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state without titles', (tester) async {
    await pumpApp(tester);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.byType(TitleCard), findsNothing);
  });

  testWidgets('shows title cards and filters them by search', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    expect(find.byType(TitleCard), findsWidgets);
    expect(find.text('Northern Lights'), findsOneWidget);
    expect(find.text('MIXING'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'tide');
    await tester.pumpAndSettle();
    expect(find.byType(TitleCard), findsOneWidget);
    expect(find.text('Slow Tide'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No title matches “zzzz”'), findsOneWidget);
  });

  testWidgets('settings popup changes and saves the theme', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('APPEARANCE'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.saved.last.theme, ThemePreference.dark);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('APPEARANCE'), findsNothing);
  });

  testWidgets('first run wizard sets name, library and REAPER', (
    tester,
  ) async {
    await pumpApp(
      tester,
      configured: const [],
      peaks: const PeaksPreference(altPeaks: false, altPeaksPath: null),
    );
    expect(find.byType(FirstRunWizard), findsOneWidget);
    expect(find.text('STEP 1 OF 3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bob');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(settings.saved.last.identity.displayName, 'Bob');
    expect(find.text('Your first library'), findsOneWidget);
    expect(find.text('Artist / Album / Title'), findsOneWidget);

    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Film-oriented'));
    await tester.ensureVisible(find.text('Create library'));
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    final (folder, name, layout) = libraries.added.single;
    expect((folder, name), ('/music/Band', 'Band'));
    expect(layout!.levels.first.key, 'project');

    expect(find.text('STEP 3 OF 3'), findsOneWidget);
    expect(find.text('/detected/reaper'), findsOneWidget);
    expect(find.text('/resources'), findsOneWidget);
    expect(find.textContaining('alternate path'), findsOneWidget);
    await tester.tap(find.text('Choose…').first);
    await tester.pumpAndSettle();
    expect(settings.saved.last.reaperExecutable, '/apps/reaper');
    await tester.tap(find.byTooltip('Reset to default'));
    await tester.pumpAndSettle();
    expect(settings.saved.last.reaperExecutable, isNull);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunWizard), findsNothing);
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('first run wizard can be postponed', (tester) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunWizard), findsNothing);
    expect(settings.saved, isEmpty);
  });

  testWidgets('settings remove a library after confirmation', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('/music/Old'), findsOneWidget);
    expect(find.textContaining('alternate path'), findsNothing);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove “Band”?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(libraries.removed, isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(libraries.removed, [band.id]);
    expect(find.text('No library yet.'), findsOneWidget);
  });

  testWidgets('settings add a library', (tester) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add a library'));
    await tester.tap(find.text('Add a library'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free tree'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add a library'));
    await tester.pumpAndSettle();
    expect(libraries.added.single.$3, isNull);
    expect(find.text('/music/Band'), findsOneWidget);
  });

  testWidgets('an existing library keeps or changes its layout', (
    tester,
  ) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final custom = Layout(const [LayoutLevel('client'), LayoutLevel('spot')]);
    existingLibrary = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: custom,
    );
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already holds a library'), findsOneWidget);
    expect(find.text('client / spot'), findsOneWidget);

    await tester.ensureVisible(find.text('Create library'));
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(libraries.added.single.$3, same(custom));
  });

  testWidgets('an existing template library is preselected', (tester) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    existingLibrary = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: Layout.film().freeze(),
    );
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    expect(find.text('Current organization'), findsNothing);
    await tester.ensureVisible(find.text('Create library'));
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(libraries.added.single.$3!.leaf.key, 'scene');
  });

  testWidgets('a library holding titles shows its layout only', (
    tester,
  ) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    existingLibrary = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: Layout.projectOriented().freeze(),
    );
    existingLocked = true;
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('organization is fixed'), findsOneWidget);
    expect(find.text('Project-oriented'), findsOneWidget);
    expect(find.text('Classic'), findsNothing);
    expect(find.text('Free tree'), findsNothing);

    await tester.ensureVisible(find.text('Create library'));
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(libraries.added.single.$3!.levels, hasLength(2));
  });

  testWidgets('uses French when chosen', (tester) async {
    await pumpApp(tester, language: 'fr');
    expect(find.text('Votre bibliothèque est vide'), findsOneWidget);
  });

  test('aurora colors are stable per title and differ between titles', () {
    expect(AuroraPalette.of('01JC1'), AuroraPalette.of('01JC1'));
    expect(
      AuroraPalette.of('01JC1').lights.first,
      isNot(AuroraPalette.of('01JC2').lights.first),
    );
  });
}
