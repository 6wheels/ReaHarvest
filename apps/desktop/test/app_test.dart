import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:flutter/material.dart' hide Title;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/app.dart';
import 'package:reaharvest/demo_titles.dart';
import 'package:reaharvest/state/library_catalog.dart';
import 'package:reaharvest/state/migration_actions.dart';
import 'package:reaharvest/state/reaper_actions.dart';
import 'package:reaharvest/state/version_actions.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/pickers.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/ui/aurora.dart';
import 'package:reaharvest/ui/first_run_wizard.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/ui/known_values_editor.dart';
import 'package:reaharvest/ui/labels.dart';
import 'package:reaharvest/ui/title_detail/title_detail_page.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

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

/// Whether the folder picked in the library form holds projects.
var existingProjects = false;

/// Outcome of opening a backup: a bool, or an error thrown.
Object backupOpening = true;

/// Folders opened in the file manager.
final openedFolders = <String>[];
final revealed = <String>[];

/// When set, adopt and addVersion of the fake service wait for it (spinners).
Completer<void>? pending;

/// Normalization plans returned by the fake previewNormalization, by title
/// (an empty plan for the others); the error of a library when set.
Map<String, MediaPlan> previewPlans = const {};
Map<LibraryId, Object> previewErrors = const {};

/// When set, the fake preview waits for it; whether it was cancelled.
Completer<void>? previewPending;
bool previewCancelled = false;

/// Library catalog recording calls, without file system access.
class FakeLibraryCatalog extends LibraryCatalog {
  FakeLibraryCatalog(super.ref);

  final added = <(String, String, Layout?)>[];
  final removed = <LibraryId>[];

  /// Known values given to addLocal or setKnownValues.
  List<KnownValue>? knownValues;

  /// Members returned by membersOf, then given to setMembers.
  List<Member> members = const [];

  @override
  Future<Library?> existing(String folder) async => existingLibrary;

  @override
  Future<bool> hasProjects(String folder) async => existingProjects;

  @override
  Future<List<KnownValue>> prefillKnownValues(
    String folder,
    Layout layout,
  ) async => const [
    KnownValue('Band', [KnownValue('First album')]),
  ];

  @override
  Future<({List<KnownValue> values, Set<String> used})> knownValuesOf(
    LibraryEntry entry,
  ) async => (
    values: const [
      KnownValue('Band', [KnownValue('First album'), KnownValue('Live')]),
    ],
    used: {'Band', 'Band/First album'},
  );

  @override
  Future<List<Member>> membersOf(LibraryEntry entry) async => members;

  @override
  Future<void> setMembers(LibraryEntry entry, List<Member> members) async =>
      this.members = members;

  @override
  Future<void> setKnownValues(
    LibraryEntry entry,
    List<KnownValue> values,
  ) async => knownValues = values;

  @override
  Future<void> addLocal({
    required String folder,
    required String displayName,
    required Layout? layout,
    List<KnownValue> knownValues = const [],
  }) async {
    added.add((folder, displayName, layout));
    this.knownValues = knownValues;
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

/// Version actions recording calls, without file system access.
class FakeVersionActions extends VersionActions {
  FakeVersionActions(super.ref);

  final adopted = <(String, String)>[];
  final adoptedOwners = <MemberId?>[];
  final separated = <String>[];
  final created = <(String, String, String?)>[];
  final edited = <(String, String, String)>[];
  final statuses = <(String, String?)>[];
  final trashed = <String>[];
  final restored = <String>[];

  @override
  Future<void> restore(Title title, Version version, Backup backup) async =>
      restored.add(version.fileName);

  @override
  Future<String> addVersion(
    Title title,
    String fileName,
    String label, {
    Version? source,
    String? template,
  }) async {
    await pending?.future;
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
  Future<void> adopt(
    Title title,
    Version version,
    String label, {
    MemberId? owner,
  }) async {
    await pending?.future;
    adopted.add((version.fileName, label));
    adoptedOwners.add(owner);
  }

  @override
  Future<void> separateDuplicate(Title title, Version version) async =>
      separated.add(version.fileName);
}

/// Migration actions recording calls, without file system access.
class FakeMigrationActions extends MigrationActions {
  FakeMigrationActions(super.ref);

  final orphansDeleted = <String>[];
  final moved = <(String, List<String>)>[];
  final fixed = <(LibraryId, List<MigrationFix>)>[];

  @override
  Future<void> deleteOrphanNode(LibraryId library, String path) async {
    if (path.startsWith('locked/')) throw StateError('locked');
    orphansDeleted.add(path);
  }

  @override
  PlanPreview previewNormalization(LibraryId library, List<String> titles) {
    previewCancelled = false;
    return (
      plans: () async {
        if (previewErrors[library] case final error?) throw error;
        if (previewPending case final pending?) await pending.future;
        return {
          for (final title in titles)
            title:
                previewPlans[title] ??
                (operations: const <MediaOperation>[], blocked: const Report()),
        };
      }(),
      cancel: () async => previewCancelled = true,
    );
  }

  /// Whether [fix] runs as a task whose report opens at the end, like the
  /// real one.
  bool fixAsTask = false;

  @override
  Future<Report?> fix(LibraryId library, List<MigrationFix> fixes) async {
    fixed.add((library, fixes));
    if (!fixAsTask) return const Report();
    return ref
        .read(tasksProvider.notifier)
        .run(
          (l10n) => l10n.taskFix(fixes.length),
          (_) async => Report({
            ReportKind.folderMoved: [ReportItem(fixes.first.path)],
          }),
          openReport: true,
        );
  }

  @override
  Future<Report?> moveToTitle(
    LibraryId library,
    String path,
    List<String> folders,
  ) async {
    moved.add((path, folders));
    return const Report();
  }
}

/// REAPER actions recording calls, without launching REAPER.
class FakeReaperActions extends ReaperActions {
  FakeReaperActions(super.ref);

  final opened = <String>[];

  @override
  Future<bool> openBackup(Title title, Backup backup) async {
    if (backupOpening case final Error error) throw error;
    return backupOpening as bool;
  }

  @override
  Future<bool> openVersion(Title title, Version version) async {
    opened.add(version.fileName);
    return true;
  }
}

void main() {
  late MemorySettings settings;
  late FakeLibraryCatalog catalog;
  late FakeVersionActions versions;
  late FakeMigrationActions migration;
  late FakeReaperActions reaper;

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
    List<LibraryIssue> issues = const [],
    List<LibraryEntry> configured = const [band],
    Map<LibraryId, Library>? indexed,
    Map<VersionId, List<Backup>> history = const {},
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
    revealed.clear();
    pending = null;
    previewPlans = const {};
    previewErrors = const {};
    previewPending = null;
    existingProjects = false;
    backupOpening = true;
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
          indexedLibrariesProvider.overrideWithValue(
            indexed ?? {demoLibrary.id: demoLibrary},
          ),
          issuesProvider.overrideWithValue(issues),
          historyProvider.overrideWith((ref, id) async => history),
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
          logFolderProvider.overrideWithValue('/data/logs'),
          openFolderProvider.overrideWithValue(
            (folder) async => openedFolders.add(folder),
          ),
          fileRevealerProvider.overrideWithValue(
            (file) async => revealed.add(file),
          ),
          libraryCatalogProvider.overrideWith(
            (ref) => catalog = FakeLibraryCatalog(ref),
          ),
          versionActionsProvider.overrideWith(
            (ref) => versions = FakeVersionActions(ref),
          ),
          migrationActionsProvider.overrideWith(
            (ref) => migration = FakeMigrationActions(ref),
          ),
          reaperActionsProvider.overrideWith(
            (ref) => reaper = FakeReaperActions(ref),
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

    // The log folder opens in the file manager.
    openedFolders.clear();
    await tester.ensureVisible(find.text('/data/logs'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Open'));
    expect(openedFolders, ['/data/logs']);

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
    final (folder, name, layout) = catalog.added.single;
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
    expect(catalog.removed, isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(catalog.removed, [band.id]);
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
    expect(catalog.added.single.$3, isNull);
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
    expect(catalog.added.single.$3, same(custom));
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
    expect(catalog.added.single.$3!.leaf.key, 'scene');
  });

  testWidgets('a library holding titles shows its layout only', (tester) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    existingLibrary = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: Layout.projectOriented(),
    ).withKnownValues([KnownValue('Band')]);
    existingProjects = true;
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('organization is fixed'), findsOneWidget);
    expect(find.text('Project-oriented'), findsOneWidget);
    expect(find.text('Classic'), findsNothing);
    expect(find.text('Free tree'), findsNothing);

    await tester.ensureVisible(find.text('Create library'));
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(catalog.added.single.$3!.levels, hasLength(2));
  });

  testWidgets('a folder holding projects asks its known values', (
    tester,
  ) async {
    await pumpApp(tester, configured: const []);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    existingProjects = true;
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    expect(find.text('Known values'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(KnownValuesEditor),
        matching: find.text('Band'),
      ),
      findsOneWidget,
    );
    expect(find.text('First album'), findsOneWidget);

    // No known values for the free tree.
    await tester.ensureVisible(find.text('Free tree'));
    await tester.tap(find.text('Free tree'));
    await tester.pumpAndSettle();
    expect(find.text('Known values'), findsNothing);
    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(find.text('First album'), findsOneWidget);

    FilledButton submit() =>
        tester.widget(find.widgetWithText(FilledButton, 'Create library'));
    await tester.ensureVisible(find.byTooltip('Remove “First album”'));
    await tester.tap(find.byTooltip('Remove “First album”'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least one value below it'), findsOneWidget);
    expect(submit().onPressed, isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Unassigned'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least one value below it'), findsNothing);

    // Add an artist, then its album.
    await tester.enterText(
      find.widgetWithText(TextField, 'Add Artist'),
      'Solo',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Add Artist'));
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Add Album').last,
      'Live',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create library'));
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(catalog.knownValues, const [
      KnownValue('Band', [KnownValue(Layout.unassigned)]),
      KnownValue('Solo', [KnownValue('Live')]),
    ]);
  });

  testWidgets('level chips hide a single value and offer unassigned', (
    tester,
  ) async {
    Title title(String album, String name) => Title(
      id: NodeId.generate(),
      libraryId: demoLibrary.id,
      path: 'Band/$album/$name',
      tags: {'artist': 'Band', 'album': album, 'title': name},
      // Two versions to adopt: the counter still counts one title.
      versions: [
        for (final file in ['$name.rpp', '$name 2.rpp'])
          Version(fileName: file, modified: DateTime(2026), size: 1),
      ],
    );
    await pumpApp(
      tester,
      titles: [
        title(Layout.unassigned, 'First song'),
        title('Live', 'Other song'),
      ],
    );
    expect(find.text('Artist'), findsNothing);
    expect(find.text('To adopt · 2'), findsOneWidget);
    // The card counts the versions to adopt of its title.
    expect(
      find.descendant(
        of: find.widgetWithText(TitleCard, 'First song'),
        matching: find.textContaining('2 to adopt'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Album'));
    await tester.pumpAndSettle();
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('a library without titles still leads to its items to sort', (
    tester,
  ) async {
    await pumpApp(
      tester,
      issues: [
        (
          library: band.id,
          kind: ReportKind.orphanNode,
          item: const ReportItem('Band/Old/.node.json'),
        ),
      ],
    );
    expect(find.text('To sort · 1'), findsOneWidget);
  });

  testWidgets('settings edit the known values of a library', (tester) async {
    await pumpApp(
      tester,
      indexed: {
        band.id: Library(
          id: band.id,
          mode: LibraryMode.local,
          layout: Layout.classic(),
        ),
      },
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Known values'));
    await tester.pumpAndSettle();
    expect(find.text('Known values · Band'), findsOneWidget);
    expect(find.textContaining('still used by a folder'), findsOneWidget);

    IconButton remove(String value) => tester.widget(
      find.ancestor(
        of: find.byTooltip('Remove “$value”'),
        matching: find.byType(IconButton),
      ),
    );
    expect(remove('First album').onPressed, isNull);
    expect(remove('Band').onPressed, isNull);
    await tester.tap(find.byTooltip('Remove “Live”'));
    await tester.pumpAndSettle();
    expect(find.text('Live'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(catalog.knownValues, const [
      KnownValue('Band', [KnownValue('First album')]),
    ]);
  });

  testWidgets('settings declare the members of a library', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.text('Members · Band'), findsOneWidget);
    Finder field([String? text]) => find.descendant(
      of: find.byType(AlertDialog),
      matching: text == null
          ? find.byType(TextField)
          : find.widgetWithText(TextField, text),
    );
    // Without declared members, the local member is proposed.
    expect(field('Alice'), findsOneWidget);

    FilledButton save() =>
        tester.widget(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.text('Add a member'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(save().onPressed, isNull);
    await tester.enterText(field().last, 'alice ');
    await tester.pumpAndSettle();
    expect(find.text('Name already used'), findsOneWidget);
    await tester.enterText(field().last, 'Bob');
    await tester.tap(find.text('Add a member'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove this member').last);
    await tester.pumpAndSettle();
    expect(field(), findsNWidgets(2));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(catalog.members, [
      const Member(MemberId('M'), 'Alice'),
      isA<Member>().having((m) => m.name, 'name', 'Bob'),
    ]);

    // Declared members are loaded as they are.
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(field('Bob'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Members · Band'), findsNothing);
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

  testWidgets('filters by library, mode, status, owner and plugins', (
    tester,
  ) async {
    const demo = LibraryEntry(
      id: LibraryId('demo'),
      displayName: 'Demo',
      workspaceRoot: '/music/Demo',
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      configured: const [
        demo,
        LibraryEntry(
          id: LibraryId('empty'),
          displayName: 'Empty',
          workspaceRoot: '/music/Empty',
        ),
      ],
      navigation: const NavigationSettings(
        filter: TitleFilter(
          // A saved filter may name a library without titles, or a removed
          // one.
          libraries: {LibraryId('demo'), LibraryId('empty'), LibraryId('gone')},
          modes: {LibraryMode.local},
          owners: {MemberId('demo-member')},
          missingPlugins: true,
        ),
      ),
    );
    TitleFilter filter() => settings.saved.last.navigation.filter;

    Future<void> toggle(String chip, String value) async {
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxMenuButton, value));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(1200, 790));
      await tester.pumpAndSettle();
    }

    await toggle('Library: 3', 'gone');
    await toggle('Library: 2', 'Empty');
    expect(filter().libraries, {const LibraryId('demo')});
    await toggle('Library: Demo', 'Demo');
    expect(filter().libraries, isEmpty);
    await toggle('Mode: Local', 'Local');
    expect(filter().modes, isEmpty);
    // An owner without a known name is shown as unknown, never as an id.
    await toggle('Owner: Unknown', 'Unknown');
    expect(filter().owners, isEmpty);
    await toggle('Status', 'Mixing');
    expect(filter().statuses, {'mixing'});

    await tester.tap(find.text('Missing plugins'));
    await tester.pumpAndSettle();
    expect(filter().missingPlugins, isFalse);
    expect(find.text('Missing plugins'), findsNothing);
  });

  testWidgets('list view sorts by every column and opens the overview', (
    tester,
  ) async {
    final titles = demoTitles();
    await pumpApp(tester, titles: titles);
    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    final headers = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_HeaderCell',
    );
    expect(headers, findsNWidgets(6));

    // Name: ascending, then descending, then unsorted.
    final names = [for (final t in titles) titleName(t)]..sort();
    double top(String name) => tester.getTopLeft(find.text(name).first).dy;
    await tester.tap(headers.first);
    await tester.pumpAndSettle();
    expect(top(names.first), lessThan(top(names[1])));
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    await tester.tap(headers.first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    await tester.tap(headers.first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);

    for (var i = 1; i < 6; i++) {
      for (var tap = 0; tap < 2; tap++) {
        await tester.tap(headers.at(i));
        await tester.pumpAndSettle();
      }
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text(names.first).first));
    await tester.pumpAndSettle();
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.text(names.first).first);
    await tester.pumpAndSettle();
    expect(find.byType(Overview), findsOneWidget);
  });

  testWidgets('tree view groups several libraries', (tester) async {
    const other = LibraryEntry(
      id: LibraryId('L2'),
      displayName: 'Side project',
      workspaceRoot: '/music/Side',
    );
    const demo = LibraryEntry(
      id: LibraryId('demo'),
      displayName: 'Demo',
      workspaceRoot: '/music/Demo',
    );
    final titles = [
      for (final (i, t) in demoTitles().indexed)
        i.isEven
            ? t
            : Title(
                id: t.id,
                libraryId: other.id,
                path: t.path,
                tags: t.tags,
                versions: t.versions,
                status: t.status,
              ),
    ];
    await pumpApp(
      tester,
      titles: titles,
      configured: const [demo, other],
      navigation: const NavigationSettings(displayMode: DisplayMode.tree),
    );
    expect(find.text('Demo'), findsWidgets);
    expect(find.text('Side project'), findsOneWidget);
    final hidden = titleName(titles[1]);
    expect(find.text(hidden), findsOneWidget);

    await tester.tap(find.text('Side project'));
    await tester.pumpAndSettle();
    expect(find.text(hidden), findsNothing);
    await tester.tap(find.text('Side project'));
    await tester.pumpAndSettle();
    expect(find.text(hidden), findsOneWidget);
  });

  testWidgets('another member\'s version opens after confirmation', (
    tester,
  ) async {
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {
        demoLibrary.id: Library(
          id: demoLibrary.id,
          mode: LibraryMode.collab,
          layout: demoLibrary.layout,
          collab: const CollabSettings(groupId: GroupId('G')),
        ),
      },
    );
    Future<void> open() async {
      await tester.tap(find.text('Midnight Ferry'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(TitleCard, 'Midnight Ferry'),
          matching: find.byTooltip('Open in REAPER'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not your version'), findsOneWidget);
    }

    await open();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Not your version'), findsNothing);

    await tester.tapAt(const Offset(1200, 790));
    await tester.pumpAndSettle();
    await open();
    await tester.tap(find.text('Open anyway'));
    await tester.pumpAndSettle();
    expect(reaper.opened, ['Midnight Ferry v1.rpp']);
  });

  testWidgets('opens and restores the backup points of a version', (
    tester,
  ) async {
    final titles = demoTitles();
    final ferry = titles.firstWhere((t) => titleName(t) == 'Midnight Ferry');
    await pumpApp(
      tester,
      titles: titles,
      history: {
        for (final v in ferry.versions)
          if (v.metadata case final m?)
            m.id: [
              Backup(
                path: 'x/.history/b.rpp',
                versionId: m.id,
                created: DateTime(2026, 11, 2, 10, 30),
              ),
            ],
      },
    );
    await tester.tap(find.text('Midnight Ferry'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    final backupRow = find.ancestor(
      of: find.byIcon(Icons.history_rounded),
      matching: find.byType(Row),
    );
    final open = find.descendant(
      of: backupRow.first,
      matching: find.byTooltip('Open in REAPER'),
    );

    Future<void> expectSnack(String text) async {
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    backupOpening = false;
    await tester.tap(open);
    await expectSnack(
      'REAPER was not found. Set its location in the settings.',
    );
    backupOpening = StateError('boom');
    await tester.tap(open);
    await expectSnack('The operation failed: Bad state: boom');

    final restore = find.descendant(
      of: backupRow.first,
      matching: find.text('Restore'),
    );
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('Restore this backup point?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await expectSnack('Backup point restored');
    expect(versions.restored, hasLength(1));
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
    // The versions list shows the labels, not the file names.
    expect(find.text('take 5'), findsOneWidget);
    expect(find.text('Create a backup point'), findsOneWidget);
    expect(find.text('No backup point yet.'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('TRACKS'), findsOneWidget);

    // The pane shows the label as heading, not the file name.
    await tester.tap(find.text('take 5'));
    await tester.pumpAndSettle();
    expect(find.text('take 5'), findsNWidgets(2));
    expect(find.text('Midnight Ferry v5'), findsNothing);

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
    expect(reaper.opened, ['Midnight Ferry v1.rpp']);

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
    // Hidden on the cards of titles without versions to adopt.
    expect(find.textContaining('to adopt'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(TitleCard, 'Glass Garden'),
        matching: find.textContaining('1 to adopt'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('To adopt · 1'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleCard), findsOneWidget);
    await tester.tap(find.text('Glass Garden'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Overview),
        matching: find.text('1 version not adopted'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TitleDetailPage),
        matching: find.text('1 version not adopted'),
      ),
      findsOneWidget,
    );

    // The label is required.
    Finder adoptButton() => find.widgetWithText(FilledButton, 'Adopt');
    expect(tester.widget<FilledButton>(adoptButton()).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'intro');
    await tester.pump();
    final slow = pending = Completer<void>();
    await tester.tap(find.text('Adopt'));
    await tester.pumpAndSettle();
    expect(find.text('REAPER is open'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Continue anyway'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    slow.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(versions.adopted, [('Glass Garden v1.rpp', 'intro')]);
  });

  testWidgets('shows the absolute path of the selected version', (
    tester,
  ) async {
    await pumpApp(
      tester,
      titles: demoTitles(),
      configured: const [
        LibraryEntry(
          id: LibraryId('demo'),
          displayName: 'Demo',
          workspaceRoot: '/music/Demo',
        ),
      ],
    );
    await tester.tap(find.text('Glass Garden'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        p.joinAll([
          '/music/Demo',
          'Sample Artist',
          'Album 1',
          'Glass Garden',
          'Glass Garden v1.rpp',
        ]),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Show in file explorer'));
    expect(revealed, [
      p.joinAll([
        '/music/Demo',
        'Sample Artist',
        'Album 1',
        'Glass Garden',
        'Glass Garden v1.rpp',
      ]),
    ]);
  });

  testWidgets('lists the versions by label, adoption and status', (
    tester,
  ) async {
    Version version(String file, {String? label}) => Version(
      fileName: file,
      modified: DateTime(2026, 11, 2),
      size: 1,
      metadata: label == null
          ? null
          : VersionMetadata(
              id: VersionId('id-$file'),
              owner: const MemberId('M'),
              label: label,
            ),
    );
    final title = Title(
      id: const NodeId('t'),
      libraryId: demoLibrary.id,
      path: 'Band/First album/Opening',
      tags: const {
        'artist': 'Band',
        'album': 'First album',
        'title': 'Opening',
      },
      versions: [
        version('Opening mix.rpp', label: 'mix'),
        // Label from the file name fallback of the scan (SPEC §4.2).
        version('Opening raw.rpp', label: 'Opening raw'),
        version('Opening old.rpp'),
      ],
      versionStatuses: const {'id-Opening mix.rpp': 'mixing'},
    );
    await pumpApp(tester, titles: [title]);
    await tester.tap(find.text('Opening'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();

    // Labels only; generic labels followed by the file name, in italic.
    expect(find.text('mix'), findsNWidgets(2)); // list and pane heading
    expect(find.textContaining('Opening mix'), findsNothing);
    expect(find.text('Opening raw'), findsOneWidget);
    expect(find.textContaining('· Opening raw.rpp'), findsNothing);
    expect(find.textContaining('· Opening old.rpp'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNWidgets(2));
    expect(find.text('Mixing'), findsWidgets);

    // Not adopted: list label and badge next to the version name.
    await tester.tap(find.textContaining('· Opening old.rpp'));
    await tester.pumpAndSettle();
    expect(find.text('Not adopted'), findsNWidgets(2));
    // Pane heading: the file name with its extension, in italic.
    expect(
      tester.widget<Text>(find.text('Opening old.rpp')).style?.fontStyle,
      FontStyle.italic,
    );
  });

  testWidgets('adopts a version for a declared member', (tester) async {
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {
        demoLibrary.id: demoLibrary.withMembers(const [
          Member(MemberId('B'), 'Bob'),
          Member(MemberId('demo-member'), 'Carol'),
        ]),
      },
    );
    await tester.tap(find.text('To adopt · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Glass Garden'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();

    // The local member is not declared: the first member is proposed.
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carol').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'intro');
    await tester.pump();
    await tester.tap(find.text('Adopt'));
    await tester.pumpAndSettle();
    expect(versions.adoptedOwners, [const MemberId('demo-member')]);
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
    expect(versions.separated, hasLength(1));
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
    // The label is required.
    Finder createButton() => find.widgetWithText(FilledButton, 'Create');
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Label'), ' ');
    await tester.pump();
    expect(find.text('A label is required'), findsOne);
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'bridge');
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'Midnight Ferry - bridge.RPP'),
      findsOne,
    );
    await tester.tap(find.text('Copy of “Midnight Ferry v1”'));
    final slow = pending = Completer<void>();
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    slow.complete();
    await tester.pumpAndSettle();
    expect(versions.created, [
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
    // An adopted version keeps a label.
    await tester.enterText(find.widgetWithText(TextField, 'Label'), ' ');
    await tester.pump();
    expect(find.text('A label is required'), findsOne);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'first');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(versions.edited, [('Midnight Ferry v1.rpp', 'intro.RPP', 'first')]);
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
    expect(versions.statuses, [('Midnight Ferry v1.rpp', 'mixing')]);

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
    expect(versions.trashed, ['Midnight Ferry v1.rpp']);
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

  testWidgets('groups the issues by kind and moves misplaced projects', (
    tester,
  ) async {
    const other = LibraryId('L2');
    const title = LayoutLevel('title');
    LibraryIssue issue(LibraryId library, ReportKind kind, ReportItem item) =>
        (library: library, kind: kind, item: item);
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {
        band.id: demoLibrary,
        other: demoLibrary,
        demoLibrary.id: demoLibrary,
      },
      issues: [
        issue(
          band.id,
          ReportKind.projectTooDeep,
          const ReportItem.misplaced(
            'Artist/Album/Song/Alice/mix/a.rpp',
            level: title,
            target: 'Artist/Album/Song',
          ),
        ),
        // In the library of the demo titles, for the autocompletion.
        issue(
          demoLibrary.id,
          ReportKind.projectTooShallow,
          const ReportItem.misplaced('loose.rpp', level: title),
        ),
        issue(
          band.id,
          ReportKind.titleTooHigh,
          const ReportItem.misplaced(
            'Old',
            level: title,
            target: '_Unassigned/_Unassigned/Old',
          ),
        ),
        issue(
          other,
          ReportKind.duplicateVersionId,
          const ReportItem('A/B/C/x.rpp', 'id'),
        ),
        issue(band.id, ReportKind.corrupted, const ReportItem('A/bad.rpp')),
      ],
    );
    await tester.tap(find.text('To sort · 5'));
    await tester.pumpAndSettle();

    expect(
      find.text('PROJECTS TOO DEEP (MEMBER OR STATUS SUBFOLDER) · 1'),
      findsOne,
    );
    expect(find.text('UNREADABLE FILES · 1'), findsOne);
    expect(find.text('Band · Artist/Album/Song/Alice/mix'), findsOne);
    expect(find.text('Expected: Title'), findsWidgets);
    expect(find.text('Proposed place: Artist/Album/Song'), findsOne);
    expect(find.text('Old'), findsOne);

    // Without declared members, the lifted projects get no owner; the
    // preview shows their label, the file name (SPEC §4.2).
    await tester.tap(find.text('Fix…').at(1));
    await tester.pumpAndSettle();
    expect(
      find.text('Owner of the projects outside a member folder'),
      findsNothing,
    );
    expect(find.text('→ Artist/Album/Song · a · Mixing'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Too deep (after the folder placed too high): prefilled with its title.
    await tester.tap(find.text('Move…').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Move “a.rpp”'), findsOne);
    expect(find.widgetWithText(TextField, 'Song'), findsOne);
    await tester.tap(find.text('Move').last);
    await tester.pumpAndSettle();
    final (movedPath, folders) = migration.moved.single;
    expect(movedPath, 'Artist/Album/Song/Alice/mix/a.rpp');
    expect(folders, ['Artist', 'Album', 'Song']);

    // Too shallow: prefilled from its folders and file name.
    await tester.ensureVisible(find.text('Move…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move…').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'loose'), findsOne);
    final artist = find.widgetWithText(TextField, 'Artist');
    await tester.enterText(artist, 'a/b');
    await tester.pumpAndSettle();
    expect(find.text('Invalid folder name'), findsOne);
    await tester.enterText(artist, 'Sample');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample Artist').last);
    await tester.pumpAndSettle();
    expect(find.text('Invalid folder name'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(migration.moved, hasLength(1));

    final hint = find.text('Open the title to make each copy a new version.');
    await tester.scrollUntilVisible(hint, 200);
    // The second library has no configured name.
    expect(find.text('A/B/C'), findsOne);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsNothing);
  });

  testWidgets('fixes projects too deep in batch, with owner and status', (
    tester,
  ) async {
    const title = LayoutLevel('title');
    const alice = Member(MemberId('alice'), 'Alice');
    LibraryIssue deep(String sub) => (
      library: band.id,
      kind: ReportKind.projectTooDeep,
      item: ReportItem.misplaced(
        'Artist/Album/Song/$sub',
        level: title,
        target: 'Artist/Album/Song',
      ),
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {
        band.id: demoLibrary.withMembers(const [
          alice,
          Member(MemberId('bob'), 'Bob'),
          // The local member, owner by default.
          Member(MemberId('M'), 'Me'),
        ]),
      },
      issues: [
        deep('Alice/mix/a.rpp'),
        deep('demo/b.rpp'),
        deep('old/c.rpp'),
        deep('Alice/d.rpp'),
      ],
    );
    await tester.tap(find.text('To sort · 4'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    expect(find.text('Status for the “mix” folders'), findsOne);
    expect(find.text('→ Artist/Album/Song · a · Alice · Mixing'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Status for the “mix” folders'), findsNothing);

    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    // Projects outside a member folder go to Bob.
    await tester.tap(find.text('Me').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();
    // "demo" matches no status: set one by hand.
    await tester.tap(find.text('No status').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recording').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artist/Album/Song/old/c.rpp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix 3 items'));
    await tester.pumpAndSettle();

    final (library, fixes) = migration.fixed.single;
    expect(library, band.id);
    expect(
      [
        for (final f in fixes.cast<LiftProject>())
          (f.path, f.titleDir, f.owner, f.status, f.statusFolder),
      ],
      [
        (
          'Artist/Album/Song/Alice/mix/a.rpp',
          'Artist/Album/Song',
          alice.id,
          'mixing',
          null,
        ),
        (
          'Artist/Album/Song/demo/b.rpp',
          'Artist/Album/Song',
          const MemberId('bob'),
          'recording',
          null,
        ),
        (
          'Artist/Album/Song/Alice/d.rpp',
          'Artist/Album/Song',
          alice.id,
          null,
          null,
        ),
      ],
    );
  });

  testWidgets('lifts projects of several libraries, each with its owner', (
    tester,
  ) async {
    const title = LayoutLevel('title');
    const other = LibraryEntry(
      id: LibraryId('L2'),
      displayName: 'Other',
      workspaceRoot: '/music/Other',
    );
    LibraryIssue deep(LibraryId library, String path) => (
      library: library,
      kind: ReportKind.projectTooDeep,
      item: ReportItem.misplaced('Song/$path', level: title, target: 'Song'),
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      configured: const [band, other],
      indexed: {
        band.id: demoLibrary.withMembers(const [
          Member(MemberId('M'), 'Me'),
          Member(MemberId('alice'), 'Alice'),
        ]),
        // The default owner (the local member) is not declared here.
        other.id: Library(
          id: other.id,
          mode: LibraryMode.local,
          layout: Layout.classic(),
        ).withMembers(const [Member(MemberId('bob'), 'Bob')]),
        const LibraryId('L3'): Library(
          id: const LibraryId('L3'),
          mode: LibraryMode.local,
          layout: Layout.classic(),
        ),
      },
      issues: [
        deep(band.id, 'mix/a.rpp'),
        deep(other.id, 'mix/b.rpp'),
        deep(const LibraryId('L3'), 'mix/c.rpp'),
      ],
    );
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    expect(find.text('→ Song · b · Bob · Mixing'), findsOne);
    // No declared members: no owner.
    expect(find.text('→ Song · c · Mixing'), findsOne);
    await tester.tap(find.text('Fix 3 items'));
    await tester.pumpAndSettle();

    expect(
      {
        for (final (library, fixes) in migration.fixed)
          library: [for (final f in fixes.cast<LiftProject>()) f.owner],
      },
      {
        band.id: [const MemberId('M')],
        other.id: [const MemberId('bob')],
        const LibraryId('L3'): [null],
      },
    );
  });

  testWidgets('normalizes the media of the titles of the projects', (
    tester,
  ) async {
    LibraryIssue outside(String path) => (
      library: band.id,
      kind: ReportKind.mediaOutsidePool,
      item: ReportItem(path, 'audio-files\\kick.wav\naudio-files\\snare.wav'),
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {band.id: demoLibrary},
      issues: [
        outside('Artist/Album/Song/a.rpp'),
        outside('Artist/Album/Song/b.rpp'),
        outside('Artist/Album/Other/c.rpp'),
        // A subproject of the pool stands for its title.
        outside('Artist/Album/Other/Media/sub.rpp'),
      ],
    );
    await tester.tap(find.text('To sort · 4'));
    await tester.pumpAndSettle();
    // The references are listed on the card.
    expect(find.text('audio-files\\snare.wav'), findsNWidgets(4));

    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'whole title Artist/Album/Song: media into Media, record path Media',
      ),
      findsNWidgets(2),
    );
    await tester.tap(find.text('Fix 4 items'));
    await tester.pumpAndSettle();

    final (library, fixes) = migration.fixed.single;
    expect(library, band.id);
    expect(fixes.cast<NormalizeMedia>().map((f) => f.path), [
      'Artist/Album/Song',
      'Artist/Album/Other',
    ]);
  });

  testWidgets('previews the operations of the normalization', (tester) async {
    const song = 'Artist/Album/Song';
    LibraryIssue outside(String path) => (
      library: band.id,
      kind: ReportKind.mediaOutsidePool,
      item: ReportItem(path, r'audio\kick.wav'),
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {band.id: demoLibrary},
      issues: [
        outside('$song/a.rpp'),
        outside('$song/c.rpp'),
        outside('Artist/Album/Other/d.rpp'),
      ],
    );
    previewPlans = {
      song: (
        operations: const [
          MoveFile('$song/audio/kick.wav', '$song/Media/kick.wav'),
          CopyFile('Artist/x.wav', '$song/Media/x (2).wav'),
          TrashDuplicate(
            '$song/old/snare.wav',
            '$song/.trash/snare.wav',
            '$song/Media/snare.wav',
          ),
          ReuseDuplicate('Artist/hat.wav', '$song/Media/hat.wav'),
          RewriteProject('$song/a.rpp', {r'audio\kick.wav': r'Media\kick.wav'}),
        ],
        blocked: const Report({
          ReportKind.missingMedia: [ReportItem('$song/b.rpp', 'gone.wav')],
        }),
      ),
    };
    await tester.tap(find.text('To sort · 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();

    // One preview per title, collapsed.
    expect(
      find.text(
        '1 moved · 1 copied · 1 duplicate to the trash · 1 renamed · '
        '1 project rewritten · 1 left intact',
      ),
      findsOne,
    );
    expect(find.text('Nothing to change'), findsOne);
    expect(find.text('Rewrite a.rpp'), findsNothing);
    await tester.tap(find.text(song).last);
    await tester.pumpAndSettle();
    expect(find.text('Media not found: b.rpp · gone.wav'), findsOne);
    expect(find.text('Move audio/kick.wav → Media/kick.wav'), findsOne);
    expect(find.text('Copy Artist/x.wav → Media/x (2).wav'), findsOne);
    expect(
      find.text(
        'Duplicate of Media/snare.wav: old/snare.wav → .trash/snare.wav',
      ),
      findsOne,
    );
    expect(
      find.text(
        'Use Media/hat.wav, identical to Artist/hat.wav, left in place',
      ),
      findsOne,
    );
    expect(find.text('Rewrite a.rpp'), findsOne);

    // Only the checked titles are previewed.
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(find.text('Nothing to change'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('confirms the fix once the preview is shown', (tester) async {
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {band.id: demoLibrary},
      issues: [
        (
          library: band.id,
          kind: ReportKind.mediaOutsidePool,
          item: const ReportItem('Artist/Album/Song/a.rpp', r'audio\kick.wav'),
        ),
      ],
    );
    previewPending = Completer();
    await tester.tap(find.text('To sort · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix…'));
    await tester.pump();
    await tester.pump();

    FilledButton fix() => tester.widget(
      find.ancestor(
        of: find.text('Fix 1 item'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(find.text('Preparing the preview of the operations…'), findsOne);
    expect(fix().onPressed, isNull);

    // Closing the dialog stops the preview.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(previewCancelled, isTrue);
    previewPending!.complete();
    await tester.pumpAndSettle();

    previewPending = null;
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    expect(fix().onPressed, isNotNull);
  });

  testWidgets('keeps the previews of a library when another fails', (
    tester,
  ) async {
    const other = LibraryEntry(
      id: LibraryId('L2'),
      displayName: 'Other',
      workspaceRoot: '/music/Other',
    );
    LibraryIssue outside(LibraryId library, String path) => (
      library: library,
      kind: ReportKind.mediaOutsidePool,
      item: ReportItem(path, r'audio\kick.wav'),
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      configured: const [band, other],
      indexed: {
        band.id: demoLibrary,
        other.id: Library(
          id: other.id,
          mode: LibraryMode.local,
          layout: Layout.classic(),
        ),
      },
      issues: [
        outside(band.id, 'Artist/Album/Song/a.rpp'),
        outside(other.id, 'A/B/C/d.rpp'),
      ],
    );
    previewErrors = {other.id: StateError('unreadable')};
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable: Bad state: unreadable'), findsOne);
    expect(find.text('Nothing to change'), findsOne);
  });

  testWidgets('fixes folders in batch or moves one anywhere', (tester) async {
    LibraryIssue folder(
      ReportKind kind,
      String path,
      String level, [
      String? target,
    ]) => (
      library: demoLibrary.id,
      kind: kind,
      item: ReportItem.misplaced(
        path,
        level: LayoutLevel(level),
        target: target,
      ),
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      indexed: {demoLibrary.id: demoLibrary},
      issues: [
        folder(
          ReportKind.titleTooHigh,
          'Old',
          'title',
          '_Unassigned/_Unassigned/Old',
        ),
        folder(
          ReportKind.titleTooHigh,
          'Band/Loose',
          'title',
          'Band/_Unassigned/Loose',
        ),
        folder(ReportKind.unknownValue, 'Stranger', 'artist'),
        folder(ReportKind.unknownValue, 'Sample Artist/Odd', 'album'),
      ],
    );
    await tester.tap(find.text('To sort · 4'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.widgetWithText(TextField, label);
    String fieldText(String label) =>
        tester.widget<TextField>(field(label)).controller!.text;
    FilledButton confirm(String label) =>
        tester.widget(find.widgetWithText(FilledButton, label));

    // Titles placed too high: the album is proposed for all, the artists
    // differ and stay per folder.
    await tester.tap(find.text('Fix…').first);
    await tester.pumpAndSettle();
    expect(fieldText('Artist'), isEmpty);
    expect(fieldText('Album'), '_Unassigned');
    expect(find.text('→ Band/_Unassigned/Loose'), findsOne);
    await tester.enterText(field('Album'), 'Live');
    await tester.pumpAndSettle();
    expect(find.text('→ _Unassigned/Live/Old'), findsOne);
    await tester.enterText(field('Artist'), 'a/b');
    await tester.pumpAndSettle();
    expect(find.text('Invalid folder name'), findsOne);
    expect(confirm('Fix 2 items').onPressed, isNull);
    await tester.enterText(field('Artist'), 'Sample');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample Artist').last);
    await tester.pumpAndSettle();
    // Unchecked: left as it is.
    await tester.tap(find.text('Band/Loose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix 1 item'));
    await tester.pumpAndSettle();
    final batch = migration.fixed.single.$2.single as MoveFolder;
    expect((batch.path, batch.target), ('Old', 'Sample Artist/Live/Old'));

    // Unknown folders: their level is chosen; at their own level, an
    // artist folder is only declared.
    await tester.tap(find.text('Fix…').last);
    await tester.pumpAndSettle();
    expect(find.text('These folders are at the level'), findsOne);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Sample Artist/Odd'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix 1 item'));
    await tester.pumpAndSettle();
    final declared = migration.fixed.last.$2.single as MoveFolder;
    expect((declared.path, declared.target), ('Stranger', 'Stranger'));

    await tester.tap(find.text('Fix…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artist').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    expect(fieldText('Album'), '_Unassigned');
    await tester.enterText(field('Artist'), 'Band');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix 2 items'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final f in migration.fixed.last.$2.cast<MoveFolder>())
          (f.path, f.target),
      ],
      [
        ('Stranger', 'Band/_Unassigned/Stranger'),
        ('Sample Artist/Odd', 'Band/_Unassigned/Odd'),
      ],
    );

    // One unknown folder anywhere: one level to type. The dialog closes
    // when the move starts; its report opens over the page.
    migration.fixAsTask = true;
    await tester.ensureVisible(find.text('Move…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move…').at(2));
    await tester.pumpAndSettle();
    expect(find.text('Move “Stranger”'), findsOne);
    expect(find.text('This folder is at the level'), findsOne);
    expect(find.byType(TextField), findsOne);
    expect(find.textContaining('both are merged'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Sample Artist');
    await tester.pumpAndSettle();
    // An existing folder: both are merged.
    expect(find.textContaining('both are merged'), findsOne);
    await tester.tap(find.text('Move').last);
    await tester.pumpAndSettle();
    final moved = migration.fixed.last.$2.single as MoveFolder;
    expect((moved.path, moved.target), ('Stranger', 'Sample Artist'));
    expect(find.text('Move “Stranger”'), findsNothing);
    expect(find.text('Folders moved · 1'), findsOne);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    migration.fixAsTask = false;

    // Or at another level: the levels above it are proposed.
    await tester.ensureVisible(find.text('Move…').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move…').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.tap(find.text('Move').last);
    await tester.pumpAndSettle();
    final title = migration.fixed.last.$2.single as MoveFolder;
    expect(
      (title.path, title.target),
      ('Stranger', '_Unassigned/_Unassigned/Stranger'),
    );
  });

  testWidgets('fixes the selected To sort items, kept through a rescan', (
    tester,
  ) async {
    LibraryIssue high(String name) => (
      library: demoLibrary.id,
      kind: ReportKind.titleTooHigh,
      item: ReportItem.misplaced(
        name,
        level: const LayoutLevel('title'),
        target: '_Unassigned/_Unassigned/$name',
      ),
    );
    await pumpApp(
      tester,
      titles: demoTitles(),
      issues: [high('A'), high('B'), high('C')],
    );
    await tester.tap(find.text('To sort · 3'));
    await tester.pumpAndSettle();
    Checkbox box(int i) => tester.widget(find.byType(Checkbox).at(i));

    // Box 0 selects the section, then one box per card.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();
    expect(find.text('2 selected'), findsOne);
    expect(box(0).value, isNull);

    // A rescan without "A": "B" stays selected.
    await pumpApp(tester, titles: demoTitles(), issues: [high('B'), high('C')]);
    await tester.pumpAndSettle();
    expect(find.textContaining(' · 2'), findsOne);
    expect(find.text('1 selected'), findsOne);
    expect([box(1).value, box(2).value], [true, false]);

    // "Fix…" previews the selected items only.
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOne);
    await tester.tap(find.text('Fix 1 item'));
    await tester.pumpAndSettle();
    expect([for (final f in migration.fixed.single.$2) f.path], ['B']);

    // Select all, then none: "Fix…" applies to the whole section again.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('2 selected'), findsOne);
    expect(box(0).value, isTrue);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.textContaining('selected'), findsNothing);
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    expect(find.text('Fix 2 items'), findsOne);
  });

  testWidgets('lists and deletes node files without project', (tester) async {
    LibraryIssue orphan(String path) =>
        (library: band.id, kind: ReportKind.orphanNode, item: ReportItem(path));
    await pumpApp(
      tester,
      titles: demoTitles(),
      issues: [
        orphan('Artist/render/.node.json'),
        orphan('locked/sub/.node.json'),
      ],
    );
    await tester.tap(find.text('To sort · 2'));
    await tester.pumpAndSettle();
    expect(find.text('REAHARVEST FILES WITHOUT PROJECT · 2'), findsOne);
    expect(find.text('render'), findsOne);
    expect(find.text('Artist'), findsWidgets);

    await tester.tap(find.text('Delete this file').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this ReaHarvest file?'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(migration.orphansDeleted, isEmpty);

    await tester.tap(find.text('Delete this file').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this file').last);
    await tester.pumpAndSettle();
    expect(migration.orphansDeleted, ['Artist/render/.node.json']);

    await tester.tap(find.text('Delete this file').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this file').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('The operation failed'), findsOne);
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

  test('every known values problem has a label', () {
    final l10n = lookupAppLocalizations(const Locale('fr'));
    expect(
      {
        for (final problem in KnownValuesProblem.values)
          knownValuesProblemLabel(l10n, problem),
      },
      hasLength(KnownValuesProblem.values.length - 1),
      reason: 'tooDeep and duplicate share a label',
    );
  });
}
