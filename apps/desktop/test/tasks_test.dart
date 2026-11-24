import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/error_dialog.dart';
import 'package:reaharvest/ui/kit/kit.dart' show Led, LedMode, Meter;
import 'package:reaharvest/ui/progress_popup.dart';
import 'package:reaharvest/ui/report_dialog.dart';
import 'package:reaharvest/ui/tasks_zone.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

void main() {
  /// Lets the frames run for a while: a failed task blinks without end, so
  /// the tree never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The lit status light of [color], steady unless said otherwise (a failed
  /// task blinks).
  Finder light(Color color, {LedMode mode = LedMode.steady}) =>
      find.byWidgetPredicate(
        (w) => w is Led && w.lit && w.color == color && w.mode == mode,
      );

  late ProviderContainer container;
  TasksNotifier tasks() => container.read(tasksProvider.notifier);
  List<TaskState> states() => [
    for (final t in container.read(tasksProvider)) t.state,
  ];

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('tasks', () {
    test('report progress and their result', () async {
      final step = Completer<void>();
      final result = tasks().run((l10n) => 'A', (task) async {
        task.progress(0.5);
        await step.future;
        return 42;
      });
      await pumpEventQueue();
      expect(container.read(tasksProvider).single.progress, 0.5);
      expect(states(), [TaskState.running]);

      step.complete();
      expect(await result, 42);
      expect(states(), [TaskState.done]);
      expect(container.read(tasksProvider).single.progress, 1);
    });

    test('keep the error of a failure', () async {
      expect(
        await tasks().run<int>((l10n) => 'A', (_) async => throw 'boom'),
        isNull,
      );
      expect(states(), [TaskState.failed]);
      expect(container.read(tasksProvider).single.error, 'boom');
    });

    test('stop at their next step once cancelled', () async {
      final step = Completer<void>();
      var steps = 0;
      final result = tasks().run((l10n) => 'A', (task) async {
        for (var i = 0; i < 3; i++) {
          task.checkCancelled();
          steps++;
          await step.future;
        }
        return true;
      });
      await pumpEventQueue();
      tasks().cancel(container.read(tasksProvider).single.id);
      expect(container.read(tasksProvider).single.cancelling, isTrue);
      expect(states(), [TaskState.running]);

      step.complete();
      expect(await result, isNull);
      expect(steps, 1);
      expect(states(), [TaskState.cancelled]);
    });

    test('tell their cancellation when it is asked', () async {
      final step = Completer<void>();
      var told = false;
      final result = tasks().run((l10n) => 'A', (task) async {
        unawaited(task.whenCancelled.then((_) => told = true));
        await step.future;
        expect(task.isCancelled, isTrue);
        return true;
      });
      await pumpEventQueue();
      expect(told, isFalse);
      final id = container.read(tasksProvider).single.id;
      tasks()
        ..cancel(id)
        ..cancel(id);
      await pumpEventQueue();
      expect(told, isTrue);

      step.complete();
      expect(await result, isTrue);
    });

    test('clear the finished ones only', () async {
      final step = Completer<void>();
      await tasks().run((l10n) => 'A', (_) async {});
      final running = tasks().run((l10n) => 'B', (_) => step.future);
      tasks().clearFinished();
      expect(states(), [TaskState.running]);
      step.complete();
      await running;
    });
  });

  group('tasks of a library', () {
    const band = LibraryId('band');
    const other = LibraryId('other');

    test('wait, queued, for the turn of their library, in order', () async {
      final first = Completer<void>();
      final log = <String>[];
      final one = tasks().run((l10n) => 'A', (_) async {
        log.add('A');
        await first.future;
        return 1;
      }, library: band);
      final two = tasks().run((l10n) => 'B', (_) async {
        log.add('B');
        return 2;
      }, library: band);
      expect(states(), [TaskState.queued, TaskState.queued]);
      await pumpEventQueue();
      expect(states(), [TaskState.running, TaskState.queued]);
      expect(log, ['A']);

      first.complete();
      expect(await one, 1);
      expect(await two, 2);
      expect(log, ['A', 'B']);
      expect(states(), [TaskState.done, TaskState.done]);
    });

    test('of different libraries run together', () async {
      final first = Completer<void>();
      final one = tasks().run(
        (l10n) => 'A',
        (_) => first.future,
        library: band,
      );
      expect(
        await tasks().run((l10n) => 'B', (_) async => 2, library: other),
        2,
      );
      expect(states(), [TaskState.running, TaskState.done]);
      first.complete();
      await one;
    });

    test('cancelled while queued, end at once and never run', () async {
      final first = Completer<void>();
      var ran = false;
      final one = tasks().run(
        (l10n) => 'A',
        (_) => first.future,
        library: band,
      );
      final two = tasks().run((l10n) => 'B', (_) async {
        ran = true;
      }, library: band);
      final three = tasks().run((l10n) => 'C', (_) async => 3, library: band);
      await pumpEventQueue();
      final id = container.read(tasksProvider)[1].id;
      tasks()
        ..cancel(id)
        ..cancel(id);
      expect(await two, isNull);
      expect(container.read(tasksProvider)[1].cancelling, isFalse);
      expect(states(), [
        TaskState.running,
        TaskState.cancelled,
        TaskState.queued,
      ]);
      tasks().clearFinished();
      expect(states(), [TaskState.running, TaskState.queued]);

      first.complete();
      await one;
      expect(await three, 3, reason: 'the queue goes on');
      expect(ran, isFalse);
    });
  });

  Future<void> pumpZone(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: TasksZone()),
        ),
      ),
    ),
  );

  testWidgets('tasks zone', (tester) async {
    await pumpZone(tester);
    expect(find.byType(TextButton), findsNothing, reason: 'hidden if empty');

    await tasks().run((l10n) => 'Broken', (_) async => throw 'boom');
    await tasks().run((l10n) => 'Stopped', (_) async {
      throw const TaskCancelled();
    });
    final step = Completer<void>();
    final running = tasks().run((l10n) => 'Scan', (task) async {
      task.step((l10n) => 'Reading the folders');
      task.progress(0.25);
      await step.future;
      task.checkCancelled();
    });
    await tester.pump();
    await tester.pump(Motion.medium);

    // Collapsed: the running task, its sub-step on the same line.
    expect(find.text('Scan  ·  Reading the folders'), findsOneWidget);
    expect(find.text('Broken'), findsNothing);
    expect(find.text('TASKS // 3'), findsOneWidget);

    // Expanded: every task, the sub-step under the label, the error of the
    // failed one.
    await tester.tap(find.text('TASKS // 3'));
    await tester.pump();
    await tester.pump(Motion.medium);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Reading the folders'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Cancelling…'), findsOneWidget);
    step.complete();
    await running;
    await settle(tester);
    expect(find.text('Reading the folders'), findsNothing);
    expect(find.text('Broken'), findsOneWidget);
    expect(light(AppColors.light.ledRed, mode: LedMode.blink), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Cancelled'), findsNWidgets(2));

    await tasks().run((l10n) => 'Done', (_) async {});
    await settle(tester);
    expect(find.text('Done'), findsOneWidget, reason: 'label, no state text');
    expect(light(AppColors.light.ledGreen), findsOneWidget);

    await tester.tap(find.text('Clear finished'));
    await settle(tester);
    expect(find.byType(TextButton), findsNothing);

    // A finished task is shown when nothing runs, then the zone collapses.
    await tasks().run((l10n) => 'Last', (_) async {});
    await settle(tester);
    expect(find.text('TASKS'), findsOneWidget, reason: 'no counter for one');
    await tester.tap(find.text('TASKS'));
    await settle(tester);
    expect(find.text('Last'), findsOneWidget);
  });

  testWidgets('warning, notices and the clear button of the bar', (
    tester,
  ) async {
    await pumpZone(tester);
    await tasks().run(
      (l10n) => 'Fix',
      (_) async => const Report({
        ReportKind.titleTooHigh: [ReportItem('a')],
      }),
    );
    expect(states(), [TaskState.warning]);
    tasks().notify('Backup point created');
    tasks().notify('Boom', level: NoticeLevel.error);
    await settle(tester);

    // Collapsed: the latest entry, with its state light.
    expect(find.text('Boom'), findsOneWidget);
    expect(light(AppColors.light.ledRed, mode: LedMode.blink), findsOneWidget);
    expect(find.text('TASKS // 3'), findsOneWidget);
    await tester.tap(find.text('TASKS // 3'));
    await settle(tester);
    expect(find.text('Backup point created'), findsOneWidget);
    expect(light(AppColors.light.ledGreen), findsOneWidget);
    expect(light(AppColors.light.ledAmber), findsOneWidget);
    await tester.tap(find.text('TASKS // 3'));
    await settle(tester);

    // The bar clears the finished entries without opening the zone.
    await tester.tap(find.byIcon(Icons.clear_all));
    await settle(tester);
    expect(container.read(tasksProvider), isEmpty);
  });

  testWidgets('the error dialog shows the detail and copies it', (
    tester,
  ) async {
    await pumpZone(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    showErrorDialog('boom', StackTrace.fromString('#0 here'));
    await tester.pumpAndSettle();
    expect(find.text('Unexpected error'), findsOneWidget);
    expect(find.textContaining('#0 here'), findsOneWidget);
    expect(find.text('Open the logs'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    expect(copied, 'boom\n\n#0 here');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Unexpected error'), findsNothing);
  });

  testWidgets('a queued task shows that it waits, cancellable', (tester) async {
    await pumpZone(tester);
    const band = LibraryId('band');
    final step = Completer<void>();
    final running = tasks().run((l10n) => 'Fix', (task) async {
      task.step((l10n) => 'Fix 1 of 2');
      await step.future;
    }, library: band);
    final queued = tasks().run((l10n) => 'Scan', (_) async {}, library: band);
    await tester.pump();
    await tester.pump(Motion.medium);
    await tester.tap(find.text('TASKS // 2'));
    await tester.pump();
    await tester.pump(Motion.medium);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Cancel'), findsNWidgets(2));

    await tester.tap(find.text('Cancel').first);
    await tester.pump();
    expect(await queued, isNull);
    expect(find.text('Waiting'), findsNothing);
    expect(find.text('Cancelled'), findsOneWidget);
    step.complete();
    await running;
    await tester.pumpAndSettle();
  });

  test('a quiet task leaves the list when it ends and throws its failure or '
      'cancel', () async {
    const band = LibraryId('band');
    expect(await tasks().run((l10n) => 'A', (_) async => 1, quiet: true), 1);
    await expectLater(
      tasks().run<int>((l10n) => 'B', (_) async => throw 'boom', quiet: true),
      throwsA('boom'),
    );
    final hold = Completer<void>();
    final running = tasks().run(
      (l10n) => 'C',
      (_) => hold.future,
      library: band,
    );
    final queued = tasks().run(
      (l10n) => 'D',
      (_) async {},
      quiet: true,
      library: band,
    );
    tasks().cancel(container.read(tasksProvider).last.id);
    await expectLater(queued, throwsA(isA<TaskCancelled>()));
    hold.complete();
    await running;
    expect(states(), [TaskState.done], reason: 'only the one not quiet');
  });

  test('a task not cancellable is only cancelled while queued', () async {
    const band = LibraryId('band');
    final hold = Completer<void>();
    final running = tasks().run(
      (l10n) => 'A',
      (_) => hold.future,
      cancellable: false,
      library: band,
    );
    final queued = tasks().run(
      (l10n) => 'B',
      (_) async {},
      cancellable: false,
      library: band,
    );
    await Future<void>.delayed(Duration.zero);
    final [a, b] = container.read(tasksProvider);
    expect(a.canCancel, isFalse);
    expect(b.canCancel, isTrue);
    tasks().cancel(a.id);
    tasks().cancel(b.id);
    expect(container.read(tasksProvider).first.cancelling, isFalse);
    expect(await queued, isNull);
    hold.complete();
    await running;
    expect(states(), [TaskState.done, TaskState.cancelled]);
  });

  test('a report with errors fails its task', () async {
    const report = Report({
      ReportKind.corrupted: [ReportItem('x')],
    });
    expect(await tasks().run((l10n) => 'A', (_) async => report), report);
    final task = container.read(tasksProvider).single;
    expect(task.state, TaskState.failed);
    expect(task.report, report);
    expect(task.error, isNull);
  });

  testWidgets('reports open at the end, then from the zone', (tester) async {
    await pumpZone(tester);
    await tasks().run(
      (l10n) => 'Move',
      (_) async => const Report({
        ReportKind.missingMedia: [ReportItem('/lib/a.rpp', 'gone.wav')],
        ReportKind.referencedByPlugin: [
          ReportItem('/lib/hat.wav', '/lib/a.rpp'),
        ],
        ReportKind.libraryUnavailable: [ReportItem('/other')],
        ReportKind.mediaMoved: [ReportItem('/lib/Media/kick.wav')],
        ReportKind.scanFailed: [ReportItem('/broken', 'boom')],
        ReportKind.titleTooHigh: [
          ReportItem.misplaced(
            '/lib/Loose',
            level: LayoutLevel('title'),
            target: '_Unassigned/_Unassigned/Loose',
          ),
        ],
      }),
      openReport: true,
    );
    await settle(tester);

    // Problems expanded, the rest collapsed.
    expect(find.text('Move'), findsNWidgets(2));
    expect(find.text('Scan failed · 1'), findsOneWidget);
    expect(find.text('Media not found · 1'), findsOneWidget);
    expect(find.text('Named by a plugin · 1'), findsOneWidget);
    expect(
      find.text(
        'A plugin of these projects names this file: move it by hand if '
        'needed.',
      ),
      findsOneWidget,
    );
    expect(find.text('Libraries not available · 1'), findsOneWidget);
    expect(find.text('Media moved · 1'), findsOneWidget);
    expect(find.textContaining('gone.wav'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.textContaining('Expected level: Title'), findsOneWidget);
    expect(
      find.textContaining('Proposed target: _Unassigned/_Unassigned/Loose'),
      findsOneWidget,
    );
    expect(find.textContaining('kick.wav'), findsNothing);
    await tester.ensureVisible(find.text('Media moved · 1'));
    await settle(tester);
    await tester.tap(find.text('Media moved · 1'));
    await settle(tester);
    expect(find.textContaining('kick.wav'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.text('Media moved · 1'), findsNothing);

    // Without openReport, the report waits in the zone.
    await tasks().run((l10n) => 'Scan', (_) async => const Report());
    await settle(tester);
    expect(find.text('Nothing to report.'), findsNothing);
    await tester.tap(find.text('Report'));
    await settle(tester);
    expect(find.text('Nothing to report.'), findsOneWidget);
  });

  test('every report kind has a label', () {
    final l10n = lookupAppLocalizations(const Locale('fr'));
    final labels = {
      for (final k in ReportKind.values) reportKindLabel(l10n, k),
    };
    expect(labels, hasLength(ReportKind.values.length));
  });

  test(
    'tasks log their start, steps, outcome and report, in English',
    () async {
      final records = <String>[];
      final sub = Logger.root.onRecord.listen(
        (r) => records.add('${r.level.name} ${r.message} ${r.error ?? ''}'),
      );
      addTearDown(sub.cancel);
      await tasks().run(
        (l10n) => l10n.taskScanAll,
        (_) async => const Report({
          ReportKind.projectTooShallow: [ReportItem('/x')],
        }),
      );
      await tasks().run((l10n) => 'B', (_) async => throw 'boom');
      await tasks().run((l10n) => 'C', (task) async {
        task.step((l10n) => l10n.taskStepCheck);
      });
      expect(records, [
        'INFO Scan of the libraries: started ',
        'INFO Scan of the libraries: done\nprojectTooShallow (1)\n  /x ',
        'INFO B: started ',
        'SEVERE B boom',
        'WARNING B: failed ',
        'INFO C: started ',
        'INFO C: Checking that no file is lost ',
        'INFO C: done ',
      ]);
    },
  );

  testWidgets('a foreground task blocks the interface in a popup', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          theme: buildTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: ForegroundTaskHost()),
        ),
      ),
    );
    const band = LibraryId('band');
    final step = Completer<void>();
    final scan = tasks().run(
      (l10n) => 'Scan',
      (_) => step.future,
      library: band,
    );
    expect(find.text('Fix'), findsNothing, reason: 'background: no popup');

    // Waits for the scan, shown in its popup; Escape leaves it.
    final queued = tasks().run(
      (l10n) => 'Fix',
      (_) async {},
      foreground: true,
      library: band,
    );
    await settle(tester);
    expect(find.text('Fix'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(await queued, isNull);
    expect(find.text('Fix'), findsNothing);

    // Running: step and progress; a click on the barrier does nothing,
    // Cancel asks to stop, the popup stays until the task ends.
    step.complete();
    await scan;
    final hold = Completer<void>();
    final running = tasks().run((l10n) => 'Fix', (task) async {
      task.step((l10n) => 'Fix 1 of 2');
      task.progress(0.5);
      await hold.future;
      task.checkCancelled();
    }, foreground: true);
    await settle(tester);
    expect(find.text('Fix 1 of 2'), findsOneWidget);
    expect(tester.widget<Meter>(find.byType(Meter)).value, 0.5);
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);
    expect(find.text('Fix'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Cancelling…'), findsOneWidget);
    hold.complete();
    await running;
    await settle(tester);
    expect(find.text('Fix'), findsNothing);
    expect(states().last, TaskState.cancelled);

    // Not cancellable: no Cancel once running, Escape does nothing.
    final slow = Completer<void>();
    final change = tasks().run(
      (l10n) => 'Trash',
      (_) => slow.future,
      foreground: true,
      cancellable: false,
    );
    await settle(tester);
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Cancelling…'), findsNothing);
    slow.complete();
    await change;
    await settle(tester);
    expect(states().last, TaskState.done);

    // Ended before its popup was built: its route is removed at once, a
    // dialog under it stays the top route.
    final under = Completer<String?>();
    final navigator = appNavigatorKey.currentState!;
    unawaited(
      navigator
          .push<String>(MaterialPageRoute(builder: (_) => const Text('Under')))
          .then(under.complete),
    );
    await settle(tester);
    await tasks().run((l10n) => 'Quick', (_) async {}, foreground: true);
    navigator.pop('created');
    expect(await under.future, 'created');
    await settle(tester);
    expect(find.text('Quick'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
