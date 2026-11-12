import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/ui/settings_recovery.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

void main() {
  late Directory dir;
  late String path;
  Widget? shown;
  final opened = <String>[];
  var quit = 0;
  late Future<AppSettings> pending;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('reaharvest_recovery');
    path = p.join(dir.path, 'settings.json');
    shown = null;
    opened.clear();
    quit = 0;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Starts the load, stored in [pending] (unresolved while the recovery
  /// screen waits), and shows the recovery screen.
  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async {
      pending = loadSettingsOrRecover(
        SettingsFile(path),
        show: (app) => shown = app,
        open: (folder) async => opened.add(folder),
        quit: () => quit++,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpWidget(shown!);
    await tester.pumpAndSettle();
  }

  Future<void> showScreen(WidgetTester tester, String content) async {
    File(path).writeAsStringSync(content);
    await start(tester);
  }

  testWidgets('truncated file: screen shown, file kept', (tester) async {
    await showScreen(tester, '{"schemaVersion": 1, "identity": {');
    expect(find.text('Settings cannot be read'), findsOneWidget);
    expect(find.textContaining(path), findsOneWidget);
    expect(find.text('Start with new settings'), findsOneWidget);
    expect(File(path).readAsStringSync(), '{"schemaVersion": 1, "identity": {');
  });

  testWidgets('open folder and quit', (tester) async {
    await showScreen(tester, '[]');
    await tester.tap(find.text('Open folder'));
    await tester.tap(find.text('Quit'));
    expect(opened, [dir.path]);
    expect(quit, 1);
  });

  testWidgets('newer schema: no way to start over, file kept', (tester) async {
    const content = '{"schemaVersion": 99}';
    await showScreen(tester, content);
    expect(find.text('Settings come from a newer version'), findsOneWidget);
    expect(find.text('Start with new settings'), findsNothing);
    expect(find.text('Open folder'), findsOneWidget);
    expect(File(path).readAsStringSync(), content);
  });

  testWidgets('start with new settings: file set aside, new settings', (
    tester,
  ) async {
    File(path).writeAsStringSync('broken');
    await start(tester);
    // The button starts real file access: run it in the real async zone.
    final settings = await tester.runAsync<AppSettings>(() async {
      await tester.tap(find.text('Start with new settings'));
      return pending;
    });
    expect(settings!.libraries, isEmpty);
    final aside = dir
        .listSync()
        .map((e) => p.basename(e.path))
        .where((n) => n.startsWith('settings.json.broken-'));
    expect(aside, hasLength(1));
    expect(File(p.join(dir.path, aside.single)).readAsStringSync(), 'broken');
  });
}
