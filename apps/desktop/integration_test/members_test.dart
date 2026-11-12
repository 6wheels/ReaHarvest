import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'harness.dart';

/// Members list of a library, declared in the library settings, kept in
/// its `.library.json` and offered as owners on adoption (SPEC §6.5, #71):
/// `flutter test integration_test/members_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  /// Name fields of the members dialog.
  Finder names() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  List<String> typed(WidgetTester tester) => [
    for (final f in tester.widgetList<TextField>(names())) f.controller!.text,
  ];

  /// Opens the members dialog of the only library from the settings.
  Future<void> openMembers(WidgetTester tester) async {
    await tapTooltip(tester, 'Settings');
    await tapText(tester, 'Members');
    expect(find.text('Members · Band'), findsOne);
  }

  /// Members declared in `.library.json`: (memberId, name).
  List<(String, String)> declared() => [
    for (final m
        in (jsonDecode(File(h.path('Band/.library.json')).readAsStringSync())
                as Map<String, dynamic>)['members']
            as List<dynamic>)
      (m['memberId'] as String, m['name'] as String),
  ];

  testWidgets('declares the members and offers them as owners', (tester) async {
    final song = h.copyCleanProject('Band/Artist/Album/Song/v1.rpp');
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');
    await h.addLibrary(tester, 'Band', Layout.classic());
    final me = h.settings.identity.memberId;

    // The person preparing the library is proposed first.
    await openMembers(tester);
    expect(typed(tester), ['Tester']);
    final save = find.widgetWithText(FilledButton, 'Save');
    bool canSave() => tester.widget<FilledButton>(save).onPressed != null;

    // An empty name, then a name already used, are refused.
    await tapText(tester, 'Add a member');
    expect(find.text('Enter a name'), findsOne);
    expect(canSave(), isFalse);
    await tester.enterText(names().last, 'tester');
    await tester.pumpAndSettle();
    expect(find.text('Name already used'), findsOne);
    expect(canSave(), isFalse);
    await tester.enterText(names().last, 'Alice');
    await tapText(tester, 'Add a member');
    await tester.enterText(names().last, 'Bob');
    await tester.pumpAndSettle();
    // Removed before saving.
    await tapTooltip(tester, 'Remove this member');
    expect(typed(tester), ['Tester', 'Alice']);
    expect(canSave(), isTrue);
    await tester.tap(save);
    // Saved, then the library is rescanned to index them.
    await waitFor(
      tester,
      () =>
          h.container
              .read(indexedLibrariesProvider)
              .values
              .single
              .members
              .length ==
          2,
      reason: 'members indexed',
    );
    final members = declared();
    expect(members.map((m) => m.$2), ['Tester', 'Alice']);
    expect(members.first.$1, me.value);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Kept after a restart.
    await h.restart(tester);
    await openMembers(tester);
    expect(typed(tester), ['Tester', 'Alice']);
    await tapText(tester, 'Cancel');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Adoption: the owner is chosen among the declared members.
    await tester.tap(find.widgetWithText(TitleCard, 'Song'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<MemberId>));
    await tester.pumpAndSettle();
    await tapText(tester, 'Alice');
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'demo');
    await tester.pumpAndSettle();
    final adopt = find.widgetWithText(FilledButton, 'Adopt');
    await tester.tap(adopt);
    await waitFor(tester, () => adopt.evaluate().isEmpty, reason: 'adopted');
    expect(find.text('demo'), findsWidgets);
    expect(find.textContaining('Alice ·'), findsOne);
    expect(
      File(song).readAsStringSync(),
      matches(RegExp(r'^\s*VERSIONID \S+', multiLine: true)),
    );
  });
}
