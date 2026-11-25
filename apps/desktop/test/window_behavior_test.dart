import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/state/window_behavior.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';
import 'package:reaharvest/ui/quit_dialog.dart';
import 'package:reaharvest/ui/settings/system_page.dart';
import 'package:reaharvest/ui/tasks_zone.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import 'helpers.dart';

void main() {
  late FakeShell shell;
  late ProviderContainer container;
  late List<BackgroundTask> asked;
  var answer = true;

  setUp(() {
    shell = FakeShell();
    asked = [];
    answer = true;
    container = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings(identity: const LocalIdentity(MemberId('M'), 'Alice')),
        ),
        settingsProvider.overrideWith(MemorySettings.new),
        logFolderProvider.overrideWithValue('/data/logs'),
        detectedReaperProvider.overrideWith((ref) async => null),
        defaultReaperResourcesProvider.overrideWithValue(null),
        windowShellProvider.overrideWithValue(shell),
        quitConfirmerProvider.overrideWithValue((tasks) async {
          asked = tasks;
          return answer;
        }),
      ],
    );
    addTearDown(container.dispose);
  });

  WindowBehavior behavior() => container.read(windowBehaviorProvider);
  Future<void> change(AppSettings Function(AppSettings) edit) =>
      container.read(settingsProvider.notifier).change(edit);

  /// A task that runs until the returned completer completes.
  Completer<void> runTask() {
    final end = Completer<void>();
    container.read(tasksProvider.notifier).run((l10n) => 'Scan', (_) {
      return end.future;
    });
    return end;
  }

  test('the tray icon follows the settings', () async {
    behavior().start();
    await pumpEventQueue();
    expect(shell.calls, ['tray off']);

    await change((s) => s.copyWith(showInTray: true, language: 'fr'));
    await pumpEventQueue();
    expect(shell.calls.last, 'tray Ouvrir ReaHarvest');

    // A language without translation falls back to English.
    await change((s) => s.copyWith(language: 'xx'));
    await pumpEventQueue();
    expect(shell.calls.last, 'tray Open ReaHarvest');

    await change((s) => s.copyWith(showInTray: false));
    await pumpEventQueue();
    expect(shell.calls.last, 'tray off');
  });

  test('closing hides to the tray when shown there, else quits', () async {
    await change((s) => s.copyWith(showInTray: true));
    await behavior().closeRequested();
    expect(shell.calls, ['hide']);
    await behavior().open();

    await change((s) => s.copyWith(showInTray: false));
    await behavior().closeRequested();
    expect(shell.calls, ['hide', 'show', 'destroy']);
    expect(asked, isEmpty);
  });

  test('quitting asks first while a task runs or waits', () async {
    final end = runTask();
    await pumpEventQueue();

    answer = false;
    await behavior().quit();
    expect(
      asked.map((t) => t.label(lookupAppLocalizations(const Locale('en')))),
      ['Scan'],
    );
    expect(shell.calls, ['show']);
    expect(container.read(tasksProvider).single.cancelling, isFalse);

    answer = true;
    await behavior().quit();
    expect(shell.calls, ['show', 'show', 'destroy']);
    expect(container.read(tasksProvider).single.cancelling, isTrue);
    end.complete();
  });

  test('a project opening does nothing, minimizes or closes', () async {
    await behavior().projectOpened();
    expect(shell.calls, isEmpty);

    await change((s) => s.copyWith(onProjectOpen: ProjectOpenAction.minimize));
    await behavior().projectOpened();
    expect(shell.calls, ['minimize']);

    shell.calls.clear();
    await change((s) => s.copyWith(onProjectOpen: ProjectOpenAction.close));
    await behavior().projectOpened();
    expect(shell.calls, ['destroy']);

    shell.calls.clear();
    await change((s) => s.copyWith(showInTray: true));
    await behavior().projectOpened();
    expect(shell.calls, ['hide']);

    // A running task: minimized instead, nothing asked.
    shell.calls.clear();
    final end = runTask();
    await pumpEventQueue();
    await behavior().projectOpened();
    expect(shell.calls, ['minimize']);
    expect(asked, isEmpty);
    end.complete();
  });

  testWidgets('the System page sets the tray and the project option', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: SystemPage()),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(CheckRow));
    await tester.pump();
    expect(container.read(settingsProvider).showInTray, isTrue);
    // With the tray, "Close" becomes "Minimize to tray".
    expect(find.text('Close ReaHarvest'), findsNothing);
    expect(find.text('Minimize to tray'), findsOneWidget);
    await tester.tap(find.text('Minimize ReaHarvest'));
    await tester.pump();
    expect(
      container.read(settingsProvider).onProjectOpen,
      ProjectOpenAction.minimize,
    );
  });

  testWidgets('the quit dialog lists the tasks and answers', (tester) async {
    final end = runTask();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          navigatorKey: appNavigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox(),
        ),
      ),
    );
    final tasks = container.read(tasksProvider);

    var result = confirmQuit(tasks);
    await tester.pumpAndSettle();
    expect(find.text('• Scan'), findsOneWidget);
    await tester.tap(find.text('Keep running'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);

    result = confirmQuit(tasks);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel the tasks and quit'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    end.complete();
  });
}
