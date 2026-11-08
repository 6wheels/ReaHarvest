import 'package:flutter/material.dart' hide Title;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/app.dart';
import 'package:reaharvest/demo_titles.dart';
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/pickers.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/ui/aurora.dart';
import 'package:reaharvest/ui/first_run_wizard.dart';
import 'package:reaharvest/ui/title_detail.dart';
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
  final adopted = <(String, String)>[];
  final separated = <String>[];
  final opened = <String>[];
  final created = <(String, String, String?)>[];
  final edited = <(String, String, String)>[];
  final statuses = <(String, String?)>[];
  final trashed = <String>[];
  final orphansDeleted = <String>[];

  @override
  Future<void> deleteOrphanNode(LibraryId library, String path) async =>
      orphansDeleted.add(path);

  @override
  Future<String> addVersion(
    Title title,
    String fileName,
    String label, {
    Version? source,
    String? template,
  }) async {
    created.add((fileName, label, source?.fileName));
    return fileName;
  }

  @override
  Future<String> editVersion(
    Title title,
    Version version, {
    required String fileName,
    required String label,
  }) async {
    edited.add((version.fileName, fileName, label));
    return fileName;
  }

  @override
  Future<void> setStatusOf(
    Title title,
    Version version,
    String? status,
  ) async => statuses.add((version.fileName, status));

  @override
  Future<void> trashVersion(Title title, Version version) async =>
      trashed.add(version.fileName);

  @override
  Future<bool> openVersion(Title title, Version version) async {
    opened.add(version.fileName);
    return true;
  }

  @override
  Future<void> adopt(Title title, Version version, String label) async =>
      adopted.add((version.fileName, label));

  @override
  Future<void> separateDuplicate(Title title, Version version) async =>
      separated.add(version.fileName);

  @override
  Future<Library?> existing(String folder) async => existingLibrary;

  @override
  Future<bool> isLayoutLocked(String folder) async => existingLocked;

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
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.addLibrary(entry));
  }

  @override
  Future<void> remove(LibraryId id) async {
    removed.add(id);
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.removeLibrary(id));
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
    List<Title> titles = const [],
    bool reaperRunning = false,
    NavigationSettings navigation = const NavigationSettings(),
    String language = 'en',
    List<String> orphanNodes = const [],
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
              navigation: navigation,
            ),
          ),
          settingsProvider.overrideWith(() => settings),
          titlesProvider.overrideWithValue(titles),
          indexedLibrariesProvider.overrideWithValue({
            demoLibrary.id: demoLibrary,
          }),
          toSortProvider.overrideWithValue(const []),
          scanIssuesProvider.overrideWith(
            (ref, kind) => kind == 'orphanNode'
                ? [for (final o in orphanNodes) (library: band.id, path: o)]
                : const [],
          ),
          historyProvider.overrideWith((ref, id) async => const {}),
          trashProvider.overrideWith(
            (ref, id) async => [
              StorageEntry(
                path: 'Sample Artist/Album 2/Midnight Ferry/.trash/old.rpp',
                isDirectory: false,
                size: 2048,
                modified: DateTime(2026, 11, 1),
              ),
            ],
          ),
          projectTemplatesProvider.overrideWith((ref, id) async => const []),
          pluginCacheProvider.overrideWith((ref) async => null),
          reaperRunningProvider.overrideWithValue(() async => reaperRunning),
          libraryServiceProvider.overrideWith(
            (ref) => libraries = FakeLibraryService(ref),
          ),
          pickersProvider.overrideWithValue(const FakePickers()),
          detectedReaperProvider.overrideWith(
            (ref) async => '/detected/reaper',
          ),
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
    expect(find.text('Mixing'), findsWidgets);

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

  testWidgets('first run wizard sets name, library and REAPER', (tester) async {
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
      layout: Layout.film(),
    );
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    expect(find.text('Current organization'), findsNothing);
    await tester.ensureVisible(find.text('Create library'));
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(libraries.added.single.$3!.leaf.key, 'scene');
  });

  testWidgets('a library holding titles shows its layout only', (tester) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    existingLibrary = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: Layout.projectOriented(),
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

  testWidgets('filters by tag and saves the filter', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    expect(find.byType(TitleCard), findsNWidgets(12));

    await tester.tap(find.text('Artist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Other Artist'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1200, 790));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxMenuButton), findsNothing);
    expect(find.byType(TitleCard), findsNWidgets(6));
    expect(find.text('Artist: Other Artist'), findsOneWidget);
    expect(settings.saved.last.navigation.filter.tags, {
      'artist': {'Other Artist'},
    });

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleCard), findsNWidgets(12));
  });

  testWidgets('restores the search query', (tester) async {
    await pumpApp(
      tester,
      titles: demoTitles(),
      navigation: const NavigationSettings(query: 'tide'),
    );
    expect(find.byType(TitleCard), findsOneWidget);
    expect(find.widgetWithText(TextField, 'tide'), findsOneWidget);
  });

  testWidgets('switches to list and tree views', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleCard), findsNothing);
    expect(find.text('Northern Lights'), findsOneWidget);
    expect(settings.saved.last.navigation.displayMode, DisplayMode.list);

    await tester.tap(find.byTooltip('Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Other Artist'), findsOneWidget);
    expect(find.text('Paper Boats'), findsOneWidget);
    await tester.tap(find.text('Other Artist'));
    await tester.pumpAndSettle();
    expect(find.text('Paper Boats'), findsNothing);
    expect(find.text('Northern Lights'), findsOneWidget);
  });

  testWidgets('shows a title overview with its recent versions', (
    tester,
  ) async {
    await pumpApp(tester, titles: demoTitles());
    await tester.tap(find.text('Midnight Ferry'));
    await tester.pumpAndSettle();
    expect(find.byType(Overview), findsOneWidget);
    expect(find.text('Midnight Ferry v1'), findsOneWidget);
    expect(find.text('Midnight Ferry v3'), findsOneWidget);
    expect(find.text('Midnight Ferry v4'), findsNothing);
    expect(find.text('All 5 versions'), findsOneWidget);
    expect(find.text('Create a backup point'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Midnight Ferry v1'), findsNothing);
  });

  testWidgets('floating overview closes on a click outside, pinned stays', (
    tester,
  ) async {
    await pumpApp(tester, titles: demoTitles());
    await tester.tap(find.text('Midnight Ferry'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(find.byType(Overview), findsNothing);

    await tester.tap(find.text('Midnight Ferry').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin below the titles'));
    await tester.pumpAndSettle();
    expect(settings.saved.last.navigation.overviewPinned, isTrue);
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(find.byType(Overview), findsOneWidget);
  });

  testWidgets('opens the title detail over the library and goes back', (
    tester,
  ) async {
    await pumpApp(tester, titles: demoTitles());
    await tester.tap(find.text('Midnight Ferry'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsOneWidget);
    expect(find.text('Midnight Ferry v5'), findsOneWidget);
    expect(find.text('Create a backup point'), findsOneWidget);
    expect(find.text('No backup point yet.'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('TRACKS'), findsOneWidget);

    await tester.tap(find.text('Midnight Ferry v5'));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp('^take 5 · ')), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsNothing);
    expect(find.byType(Overview), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsNothing);
  });

  testWidgets('a card opens its latest version in REAPER', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    await tester.tap(find.text('Midnight Ferry'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(TitleCard, 'Midnight Ferry'),
        matching: find.byTooltip('Open in REAPER'),
      ),
    );
    await tester.pumpAndSettle();
    expect(libraries.opened, ['Midnight Ferry v1.rpp']);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(TitleCard, 'Midnight Ferry'),
        matching: find.byTooltip('More actions'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Show in file explorer'), findsOneWidget);
  });

  testWidgets('saves and applies a view', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    await tester.enterText(find.byType(TextField), 'tide');
    await tester.tap(find.text('Views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save current view…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Tide');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(settings.saved.last.navigation.savedViews.single.query, 'tide');

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(TitleCard), findsNWidgets(12));
    await tester.tap(find.text('Views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tide'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleCard), findsOneWidget);
    expect(find.widgetWithText(TextField, 'tide'), findsOneWidget);
  });

  testWidgets('adopts a version after the REAPER warning', (tester) async {
    await pumpApp(tester, titles: demoTitles(), reaperRunning: true);
    await tester.tap(find.text('To adopt · 1'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleCard), findsOneWidget);
    await tester.tap(find.text('Glass Garden'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'intro');
    await tester.tap(find.text('Adopt'));
    await tester.pumpAndSettle();
    expect(find.text('REAPER is open'), findsOneWidget);
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();
    expect(libraries.adopted, [('Glass Garden v1.rpp', 'intro')]);
  });

  testWidgets('offers to make a duplicate a new version', (tester) async {
    final metadata = VersionMetadata(
      id: VersionId.generate(),
      owner: const MemberId('M'),
      label: 'take',
    );
    Version version(String name) => Version(
      fileName: name,
      modified: DateTime(2026, 11, 1),
      size: 1,
      metadata: metadata,
    );
    await pumpApp(
      tester,
      titles: [
        Title(
          id: NodeId.generate(),
          libraryId: demoLibrary.id,
          path: 'Band/Album/Song',
          tags: const {'artist': 'Band', 'album': 'Album', 'title': 'Song'},
          versions: [version('Song.rpp'), version('Song copy.rpp')],
        ),
      ],
    );
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 duplicated versions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Same identity as'), findsOneWidget);

    await tester.tap(find.text('Make it a new version'));
    await tester.pumpAndSettle();
    expect(libraries.separated, hasLength(1));
  });

  Future<void> openMidnightFerry(WidgetTester tester) async {
    await tester.tap(find.text('Midnight Ferry'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('creates a version with a suggested file name', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    await openMidnightFerry(tester);
    await tester.tap(find.text('New version'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Midnight Ferry.RPP'), findsOne);

    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'bridge');
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'Midnight Ferry - bridge.RPP'),
      findsOne,
    );
    await tester.tap(find.text('Copy of “Midnight Ferry v1”'));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(libraries.created, [
      ('Midnight Ferry - bridge.RPP', 'bridge', 'Midnight Ferry v1.rpp'),
    ]);
  });

  testWidgets('refuses the name of another version', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    await openMidnightFerry(tester);
    await tester.tap(find.byTooltip('More actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'File name'),
      'Midnight Ferry v2',
    );
    await tester.pumpAndSettle();
    expect(find.text('A version already has this name'), findsOne);

    await tester.enterText(
      find.widgetWithText(TextField, 'File name'),
      'intro',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'first');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(libraries.edited, [('Midnight Ferry v1.rpp', 'intro.RPP', 'first')]);
  });

  testWidgets('sets the status and deletes a version', (tester) async {
    await pumpApp(tester, titles: demoTitles(), reaperRunning: true);
    await openMidnightFerry(tester);
    await tester.tap(find.byTooltip('More actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mixing').last);
    await tester.pumpAndSettle();
    expect(libraries.statuses, [('Midnight Ferry v1.rpp', 'mixing')]);

    await tester.tap(find.byTooltip('More actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to the trash'));
    await tester.pumpAndSettle();
    expect(find.text('Move “Midnight Ferry v1” to the trash?'), findsOne);
    await tester.tap(find.text('Move to the trash').last);
    await tester.pumpAndSettle();
    expect(find.text('REAPER is open'), findsOne);
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();
    expect(libraries.trashed, ['Midnight Ferry v1.rpp']);
  });

  testWidgets('shows the trash of a title', (tester) async {
    await pumpApp(tester, titles: demoTitles());
    await openMidnightFerry(tester);
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Empty the trash'), findsOne);
    expect(find.text('old.rpp'), findsOne);
    expect(find.textContaining('2.0 KB'), findsWidgets);
  });

  testWidgets('lists and deletes node files without project', (tester) async {
    await pumpApp(
      tester,
      titles: demoTitles(),
      orphanNodes: ['Artist/render/.node.json'],
    );
    await tester.tap(find.text('To sort · 1'));
    await tester.pumpAndSettle();
    expect(find.text('REAHARVEST FILES WITHOUT PROJECT'), findsOne);
    expect(find.text('Artist/render'), findsOne);

    await tester.tap(find.text('Delete this file'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this ReaHarvest file?'), findsOne);
    await tester.tap(find.text('Delete this file').last);
    await tester.pumpAndSettle();
    expect(libraries.orphansDeleted, ['Artist/render/.node.json']);
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
