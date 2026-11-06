import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/app.dart';
import 'package:reaharvest/demo_titles.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/ui/aurora.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

/// Keeps settings in memory instead of writing a file.
class MemorySettings extends SettingsNotifier {
  final saved = <AppSettings>[];

  @override
  Future<void> persist(AppSettings settings) async => saved.add(settings);
}

void main() {
  late MemorySettings settings;

  Future<void> pumpApp(
    WidgetTester tester, {
    List<TitleView> titles = const [],
    String language = 'en',
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = MemorySettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            AppSettings(
              identity: const LocalIdentity(MemberId('M'), 'Alice'),
              language: language,
            ),
          ),
          settingsProvider.overrideWith(() => settings),
          titleViewsProvider.overrideWithValue(titles),
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
