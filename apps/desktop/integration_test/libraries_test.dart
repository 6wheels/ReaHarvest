import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import 'harness.dart';

/// Libraries added, attached, refused and removed from the settings (SPEC
/// §5.1, #46, #59): `flutter test integration_test/libraries_test.dart -d
/// windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  Finder submit() => find.widgetWithText(FilledButton, 'Add a library');

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(submit());
    await tester.pumpAndSettle();
    await tester.tap(submit());
    await tester.pumpAndSettle();
  }

  /// Opens the "Add a library" dialog of the open settings.
  Future<void> openForm(WidgetTester tester) async {
    await tapText(tester, 'Add a library');
    expect(submit(), findsOne);
  }

  /// Chooses [folder] in the open library form.
  Future<void> choose(WidgetTester tester, String folder) async {
    h.picks.add(folder);
    await tapText(tester, 'Choose…');
  }

  /// Submits the open library form, then closes the report of its scan.
  Future<void> add(WidgetTester tester) async {
    await tapSubmit(tester);
    await waitForText(tester, 'Libraries scanned · 1');
    // The form is closed, the report stays (#59).
    expect(submit(), findsNothing);
    await tapText(tester, 'Close');
  }

  testWidgets('adds, attaches, refuses and removes libraries', (tester) async {
    h.copyFixture('tracks.rpp', 'Fresh/Artist/Album/Song/v1.rpp');
    // A library already described, holding titles.
    final ballad = h.copyFixture('tracks.rpp', 'Shared/Artist/Ballad/v1.rpp');
    final shared = Library(
      id: LibraryId.generate(),
      mode: LibraryMode.local,
      layout: Layout.projectOriented(),
    );
    await tester.runAsync(
      () => writeLibrary(MountedFolderStorage(h.path('Shared')), shared),
    );
    File(h.path('Broken/.library.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{ not json');
    await h.writeSettings();

    await h.start(tester);
    await tapText(tester, 'Later');
    await tapTooltip(tester, 'Settings');
    expect(find.text('No library yet.'), findsOne);

    // New library, with the recommended organization.
    await openForm(tester);
    await choose(tester, h.path('Fresh'));
    expect(find.text('Fresh'), findsOne);
    await add(tester);
    expect(find.text(h.path('Fresh')), findsOne);
    expect(File(h.path('Fresh/.library.json')).existsSync(), isTrue);

    // Unreadable description: refused at once.
    await openForm(tester);
    await choose(tester, h.path('Broken'));
    expect(
      find.text('This folder holds an unreadable .library.json file.'),
      findsOne,
    );
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    // A folder inside another library: refused when submitted.
    await choose(tester, h.path('Fresh/Artist'));
    await tapText(tester, 'Free tree');
    await tapSubmit(tester);
    expect(
      find.text('This folder is, contains or is inside another library.'),
      findsOne,
    );
    await tapText(tester, 'Cancel');
    expect(h.settings.libraries, hasLength(1));

    // Existing description: attached with its id and fixed organization.
    await openForm(tester);
    await choose(tester, h.path('Shared'));
    expect(find.textContaining('organization is fixed'), findsOne);
    expect(find.text('Project-oriented'), findsOne);
    expect(find.text('Classic'), findsNothing);
    await add(tester);
    expect(h.settings.libraries.last.id, shared.id);
    final attached = await tester.runAsync(
      () => readLibrary(MountedFolderStorage(h.path('Shared'))),
    );
    expect(attached!.layout!.levels, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TitleCard, 'Song'), findsOne);
    expect(find.widgetWithText(TitleCard, 'Ballad'), findsOne);

    // Removal, after confirmation: the projects stay.
    await tapTooltip(tester, 'Settings');
    await tapText(tester, 'Remove');
    expect(find.text('Remove “Shared”?'), findsOne);
    await tapText(tester, 'Cancel');
    expect(h.settings.libraries, hasLength(2));
    await tapText(tester, 'Remove');
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text(h.path('Shared')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TitleCard, 'Ballad'), findsNothing);
    expect(find.widgetWithText(TitleCard, 'Song'), findsOne);
    expect(File(ballad).existsSync(), isTrue);
    final saved = (await tester.runAsync(h.savedSettings))!;
    expect(saved.libraries.map((l) => l.displayName), ['Fresh']);
  });
}
