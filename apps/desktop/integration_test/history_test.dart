import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import 'harness.dart';

/// History of a version: a backup opened in REAPER with its paths
/// normalized, then restored (SPEC §5.4, #50, #59): `flutter test
/// integration_test/history_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  testWidgets('opens a backup with normalized paths and restores it', (
    tester,
  ) async {
    final version = File(h.copyCleanProject('Band/Artist/Album/Song/v1.rpp'));
    final history = Directory(h.path('Band/Artist/Album/Song/.history'));
    List<File> backups() => history.existsSync()
        ? history.listSync().whereType<File>().toList()
        : const [];
    List<String> media(File file) =>
        RppProject.parse(file.readAsStringSync()).mediaFiles;
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(tester, 'Band', Layout.classic());

    // An adopted version has a history.
    await tester.tap(find.widgetWithText(TitleCard, 'Song'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'main');
    await tester.pumpAndSettle();
    final adopt = find.widgetWithText(FilledButton, 'Adopt');
    await tester.tap(adopt);
    await waitFor(tester, () => adopt.evaluate().isEmpty, reason: 'adopted');
    expect(find.text('No backup point yet.'), findsOne);

    // Backup point, its paths rebased onto the title folder.
    await tapText(tester, 'Create a backup point');
    await waitFor(
      tester,
      () => find.text('No backup point yet.').evaluate().isEmpty,
      reason: 'backup listed',
    );
    final backup = backups().single;
    expect(media(backup), everyElement(startsWith(r'..\Media\')));

    // REAPER lengthens the paths of a backup on every save; they are
    // normalized before it is opened.
    backup.writeAsStringSync(
      rewriteMediaPaths(
        backup.readAsStringSync(),
        (ref) => ref.replaceFirst(r'..\Media\', r'..\Media\..\Media\'),
      ),
    );
    await tester.tap(find.byTooltip('Open in REAPER').last);
    await waitFor(tester, () => h.launched.isNotEmpty, reason: 'opened');
    expect(h.launched.single, (h.detectedReaper, backup.path));
    expect(
      media(backup),
      everyElement(
        allOf(startsWith(r'..\Media\'), isNot(contains(r'..\Media\..'))),
      ),
    );

    // Restore: the current state is backed up first, then replaced.
    version.writeAsStringSync(
      rewriteMediaPaths(
        version.readAsStringSync(),
        (ref) => ref.replaceFirst('01-261108_1921', 'changed'),
      ),
    );
    final id = RegExp(r'VERSIONID (\S+)')
        .firstMatch(version.readAsStringSync());
    await tapText(tester, 'Restore');
    expect(find.text('Restore this backup point?'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await waitForText(tester, 'Backup point restored');
    await waitFor(
      tester,
      () => find.text('Restore').evaluate().length == 2,
      reason: 'two backups listed',
    );
    expect(backups(), hasLength(2));
    final restored = version.readAsStringSync();
    expect(restored, isNot(contains('changed')));
    expect(media(version), contains(r'Media\01-261108_1921.wav'));
    expect(restored, contains(id!.group(0)!));
    expect(p.basename(backup.path), startsWith('v1 '));
  });
}
