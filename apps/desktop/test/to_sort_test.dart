import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/migration_actions.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';
import 'package:reaharvest/ui/to_sort/candidate_card.dart';
import 'package:reaharvest/ui/to_sort/to_sort_list.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

const _band = LibraryEntry(
  id: LibraryId('band'),
  displayName: 'Band',
  workspaceRoot: '/music/Band',
);
const _archive = LibraryEntry(
  id: LibraryId('archive'),
  displayName: 'Archive',
  workspaceRoot: '/music/Archive',
);
const _alice = Member(MemberId('alice'), 'Alice');
const _title = LayoutLevel('title');

Library _library(LibraryEntry entry, {List<Member> members = const []}) =>
    Library(
      id: entry.id,
      mode: LibraryMode.local,
      layout: Layout.classic(),
      members: members,
    );

Version _version(String fileName) =>
    Version(fileName: fileName, modified: DateTime(2026), size: 0);

Title _indexed(LibraryEntry entry, String path) =>
    Title(id: NodeId(path), libraryId: entry.id, path: path, levels: const {});

/// A title placed too high under a folder at the wrong level: both moves
/// composed (SPEC §5.8 step 4), a member subfolder.
final _composed = ScanCandidate(
  root: 'Jazz/Song',
  versions: [_version('Alice/take.rpp'), _version('mix.rpp')],
  issues: Report({
    ReportKind.titleTooHigh: const [
      ReportItem.misplaced(
        'Jazz/Song',
        level: _title,
        target: 'Jazz/_Unassigned/Song',
      ),
    ],
    ReportKind.misplacedLevel: [
      ReportItem.misplaced(
        'Jazz',
        level: Layout.classic().levels.first,
        target: 'Rock',
      ),
    ],
    ReportKind.memberFolder: const [ReportItem('Jazz/Song/Alice', 'Alice')],
  }),
);

/// A copy of a version of another title.
final _copy = ScanCandidate(
  root: 'Artist/Album/Copy',
  title: 'Artist/Album/Song',
  versions: [_version('v/v.rpp')],
  issues: const Report({
    ReportKind.knownVersionElsewhere: [
      ReportItem.misplaced(
        'Artist/Album/Copy/v/v.rpp',
        level: _title,
        target: 'Artist/Album/Song',
      ),
    ],
  }),
);

/// A title without problem: no card.
final _clean = ScanCandidate(
  root: 'Artist/Album/Song',
  title: 'Artist/Album/Song',
  versions: [_version('v1/v1.rpp')],
);

/// The libraries shown, changed by a rescan.
class _ToSort extends Notifier<List<ToSortLibrary>> {
  _ToSort(this.initial);

  final List<ToSortLibrary> initial;

  @override
  List<ToSortLibrary> build() => initial;

  void rescan(List<ToSortLibrary> libraries) => state = libraries;
}

/// Migration actions recording the fixes, their plans given by [plans].
class _Migration extends MigrationActions {
  _Migration(super.ref);

  final fixed = <(LibraryId, List<MigrationFix>)>[];
  final previewed = <List<MigrationFix>>[];
  Map<String, MediaPlan> plans = const {};
  Object? previewError;
  Object? fixError;
  var cancelled = 0;

  @override
  PlanPreview preview(LibraryId library, List<MigrationFix> fixes) {
    previewed.add(fixes);
    return (
      plans: switch (previewError) {
        final error? => Future.error(error),
        null => Future.value({
          for (final f in fixes)
            f.path:
                plans[f.path] ??
                (operations: const <MediaOperation>[], blocked: const Report()),
        }),
      },
      cancel: () async => cancelled++,
    );
  }

  @override
  Future<Report?> fix(LibraryId library, List<MigrationFix> fixes) async {
    if (fixError case final error?) throw error;
    fixed.add((library, fixes));
    return const Report();
  }
}

void main() {
  late _Migration migration;
  late _ToSort toSort;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, List<ToSortLibrary> libraries) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    toSort = _ToSort(libraries);
    final provider = NotifierProvider<_ToSort, List<ToSortLibrary>>(
      () => toSort,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          toSortProvider.overrideWith((ref) => ref.watch(provider)),
          migrationActionsProvider.overrideWith(
            (ref) => migration = _Migration(ref),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: buildTheme(Brightness.dark),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: ToSortList()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    container.read(migrationActionsProvider);
  }

  ToSortLibrary band({
    List<ScanCandidate> candidates = const [],
    List<Title> titles = const [],
    Report issues = const Report(),
    List<String> corrupted = const [],
    List<String> orphanNodes = const [],
    List<Member> members = const [],
  }) => (
    entry: _band,
    library: _library(_band, members: members),
    scan: ScanResult(
      candidates: candidates,
      titles: titles,
      issues: issues,
      corrupted: corrupted,
      orphanNodes: orphanNodes,
    ),
  );

  /// The text field labeled [label] in the card of the project [project].
  Finder field(String label, {int index = 0}) => find
      .ancestor(of: find.text(label), matching: find.byType(TextField))
      .at(index);

  Future<void> pick(WidgetTester tester, Finder dropdown, String option) async {
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  /// Presses "Fix…", then confirms the preview.
  Future<void> fixAll(WidgetTester tester, String confirm) async {
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(confirm).last);
    await tester.pumpAndSettle();
  }

  testWidgets('one card per title candidate with a problem, with its fix', (
    tester,
  ) async {
    await pump(tester, [
      band(candidates: [_composed, _copy, _clean], members: [_alice]),
    ]);

    expect(find.byType(CheckRow), findsWidgets);
    expect(find.text('Song'), findsOne);
    expect(find.text('Copy'), findsOne);
    expect(find.text('Titles placed too high · 1'), findsOne);
    expect(find.text('Member subfolders · 1'), findsOne);
    expect(
      find.text('Organize into version folders at Rock/_Unassigned/Song'),
      findsOne,
    );
    expect(find.text('Move Jazz/Song → Jazz/_Unassigned/Song'), findsOne);
    expect(
      find.text('Attach the versions to the title Artist/Album/Song'),
      findsOne,
    );
    // The member from its subfolder, the label from the file name.
    expect(find.text('Alice'), findsOne);
    // The other card has a member field too.
    expect(find.text('No member'), findsNWidgets(2));
    expect(find.text('Alice/take.rpp'), findsOne);
    expect(find.text('0 selected'), findsOne);

    // The ancestor move dropped: the target computed without it.
    await tester.tap(find.text('Move Jazz → Rock'));
    await tester.pumpAndSettle();
    expect(
      find.text('Organize into version folders at Jazz/_Unassigned/Song'),
      findsOne,
    );

    // A label is required, a folder name checked.
    await tester.enterText(field('Label', index: 1), '');
    await tester.pumpAndSettle();
    expect(find.text('A label is required'), findsOne);
    expect(
      find.text('Check the label and the folder of every version.'),
      findsOne,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Fix…'))
          .onPressed,
      isNull,
    );
    await tester.enterText(field('Label', index: 1), 'Final mix');
    await tester.enterText(field('Folder', index: 1), 'a/b');
    await tester.pumpAndSettle();
    expect(find.text('Invalid folder name'), findsOne);
    await tester.enterText(field('Folder', index: 1), 'Assets');
    await tester.pumpAndSettle();
    expect(find.text('Invalid folder name'), findsNothing);
    expect(find.text('Reserved name: “ (2)” will be added'), findsOne);

    // A member, one status for every version, forced.
    await pick(tester, find.text('No member').first, 'Alice');
    await pick(tester, find.text('No status').first, 'Mixing');
    await tester.tap(find.byType(LightSwitch).first);
    await tester.pumpAndSettle();

    // Only the selected card is fixed.
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOne);
    await fixAll(tester, 'Fix 1 item');

    final (library, [fix]) = migration.fixed.single;
    expect(library, _band.id);
    expect('$fix', '''
organizeTitle Jazz/Song -> Jazz/_Unassigned/Song, forced
  Jazz/Song/Alice/take.rpp -> take, take, alice, mixing
  Jazz/Song/mix.rpp -> Assets, Final mix, alice, mixing''');

    // One status per version, a version without any.
    await tester.tap(find.text('Same status for every version').first);
    await tester.pumpAndSettle();
    await pick(tester, find.text('No status').first, 'Done');
    await fixAll(tester, 'Fix 1 item');
    expect(
      [for (final v in migration.fixed.last.$2.single.versions) v.status],
      ['done', null],
    );

    // Select all, then none: every card fixed.
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOne);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOne);
    await fixAll(tester, 'Fix 2 items');
    expect(
      [for (final f in migration.fixed.last.$2) f.kind],
      ['organizeTitle', 'attachVersions'],
    );
  });

  testWidgets('a change on a card rebuilds that card and the counter only', (
    tester,
  ) async {
    await pump(tester, [
      band(candidates: [_composed, _copy]),
    ]);
    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await tester.enterText(field('Label'), '');
    await tester.pump();

    expect(
      [
        for (final w in rebuilt)
          if (w is CandidateCard) w.title,
      ],
      ['Song'],
    );
    expect(rebuilt.whereType<ToSortList>(), isEmpty);
    // The counter follows: the empty label blocks "Fix…".
    expect(
      find.text('Check the label and the folder of every version.'),
      findsOne,
    );
  });

  testWidgets('keeps the selection through a rescan', (tester) async {
    await pump(tester, [
      band(candidates: [_composed, _copy]),
    ]);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOne);

    // Gone, then back: still selected.
    toSort.rescan([
      band(candidates: [_composed]),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOne);
    toSort.rescan([
      band(candidates: [_copy, _composed]),
      (
        entry: _archive,
        library: _library(_archive),
        scan: ScanResult(candidates: [_copy]),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOne);
    // The library named when several are shown.
    expect(find.text('Archive · Artist/Album'), findsOne);
    await fixAll(tester, 'Fix 1 item');
    expect(migration.fixed.single.$1, _band.id);
    expect(migration.fixed.single.$2.single.path, 'Artist/Album/Copy');
  });

  testWidgets('previews the plan of each fix before running it', (
    tester,
  ) async {
    await pump(tester, [
      band(candidates: [_composed, _copy]),
    ]);
    migration.plans = {
      'Jazz/Song': (
        operations: const [
          CreateFolder('Jazz/Song/mix'),
          MoveFile('Jazz/Song/mix.rpp', 'Jazz/Song/mix/mix.rpp'),
          CopyFile('Jazz/x.wav', 'Jazz/Song/mix/Media/x.wav'),
          RewriteProject('Jazz/Song/mix/mix.rpp', {'x': 'y'}),
        ],
        blocked: const Report({
          ReportKind.missingMedia: [ReportItem('Jazz/Song/take.rpp', 'a.wav')],
        }),
      ),
      'Artist/Album/Copy': (
        operations: const [],
        blocked: const Report({
          ReportKind.fixFailed: [ReportItem('Artist/Album/Copy')],
        }),
      ),
    };
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();

    expect(find.text('Move Jazz/Song → Rock/_Unassigned/Song'), findsOne);
    expect(
      find.text('1 moved · 1 copied · 1 project rewritten · 1 left intact'),
      findsOne,
    );
    await tester.tap(find.text('Move Jazz/Song → Rock/_Unassigned/Song'));
    await tester.pumpAndSettle();
    expect(
      find.text('Move Jazz/Song/mix.rpp → Jazz/Song/mix/mix.rpp'),
      findsOne,
    );
    expect(find.text('Rewrite Jazz/Song/mix/mix.rpp'), findsOne);
    expect(find.textContaining('a.wav'), findsOne);
    expect(find.byType(Led), findsNWidgets(2));

    // Cancelled: nothing fixed.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(migration.fixed, isEmpty);

    // A preview that fails.
    migration.previewError = StateError('unmounted');
    await tester.tap(find.text('Fix…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Preview unavailable'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(migration.cancelled, greaterThan(0));

    // A fix that throws is notified.
    migration
      ..previewError = null
      ..fixError = StateError('busy');
    await fixAll(tester, 'Fix 2 items');
    expect(
      container
          .read(tasksProvider)
          .single
          .label(lookupAppLocalizations(const Locale('en'))),
      contains('busy'),
    );
  });

  testWidgets('moves a project to the title the user names', (tester) async {
    await pump(tester, [
      band(
        candidates: [_composed],
        titles: [_indexed(_band, 'Artist/Album/Song')],
      ),
    ]);
    await tester.tap(find.byTooltip('Move this project…').last);
    await tester.pumpAndSettle();
    expect(find.text('Move mix.rpp'), findsOne);
    FilledButton move() =>
        tester.widget(find.widgetWithText(FilledButton, 'Fix…').last);
    expect(move().onPressed, isNull);

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Art');
    await tester.pumpAndSettle();
    // Suggested from the indexed titles.
    expect(find.text('Artist'), findsWidgets);
    expect(find.text('This level will be created'), findsOne);
    await tester.enterText(fields.at(0), 'Artist');
    await tester.enterText(fields.at(2), 'New song');
    await tester.pumpAndSettle();
    expect(find.text('This level will be created'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Fix…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix 1 item').last);
    await tester.pumpAndSettle();

    expect('${migration.fixed.single.$2.single}', '''
moveProject Jazz/Song/mix.rpp -> Artist/_Unassigned/New song
  Jazz/Song/mix.rpp -> mix, mix''');

    // Cancelled: nothing moved.
    await tester.tap(find.byTooltip('Move this project…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(migration.fixed, hasLength(1));
  });

  testWidgets('attaches the files outside any title, lists the others', (
    tester,
  ) async {
    await pump(tester, [
      band(
        titles: [_indexed(_band, 'Artist/Album/Song')],
        issues: const Report({
          ReportKind.fileOutsideTitle: [ReportItem('Artist/cover.jpg')],
          ReportKind.outsideLayout: [ReportItem('Odd')],
        }),
        orphanNodes: ['Old/.node.json'],
        corrupted: ['A/bad.rpp'],
      ),
    ]);

    expect(find.text('FILES OUTSIDE ANY TITLE · 2'), findsOne);
    expect(find.text('cover.jpg'), findsOne);
    expect(find.text('.node.json'), findsOne);
    expect(find.text('UNREADABLE FILES · 1'), findsOne);
    expect(find.text('bad.rpp'), findsOne);
    expect(find.text('TO SORT · 1'), findsOne);
    expect(find.text('Odd'), findsOne);
    expect(find.text('Select all'), findsNothing);

    Finder attach() => find.widgetWithText(OutlinedButton, 'Attach');
    final title = find.byType(TextField).first;
    await tester.enterText(title, 'Nowhere');
    await tester.pumpAndSettle();
    expect(find.text('Not a title of this library'), findsOne);
    expect(tester.widget<OutlinedButton>(attach().first).onPressed, isNull);
    await tester.enterText(title, 'artist/album/song');
    await tester.pumpAndSettle();
    await tester.tap(attach().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix 1 item').last);
    await tester.pumpAndSettle();

    expect(
      '${migration.fixed.single.$2.single}',
      'attachFile Artist/cover.jpg -> Artist/Album/Song',
    );
  });
}
