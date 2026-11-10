import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/report_dialog.dart';
import 'package:reaharvest/ui/tasks_zone.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

void main() {
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
    expect(find.text('Tasks · 3'), findsOneWidget);

    // Expanded: every task, the sub-step under the label, the error of the
    // failed one.
    await tester.tap(find.text('Tasks · 3'));
    await tester.pump();
    await tester.pump(Motion.medium);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Reading the folders'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Cancelling…'), findsOneWidget);
    step.complete();
    await running;
    await tester.pumpAndSettle();
    expect(find.text('Reading the folders'), findsNothing);
    expect(find.text('Broken'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Cancelled'), findsNWidgets(2));

    await tasks().run((l10n) => 'Done', (_) async {});
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNWidgets(2), reason: 'label and state');

    await tester.tap(find.text('Clear finished'));
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);

    // A finished task is shown when nothing runs, then the zone collapses.
    await tasks().run((l10n) => 'Last', (_) async {});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Last'), findsOneWidget);
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
    await tester.pumpAndSettle();

    // Problems expanded, the rest collapsed.
    expect(find.text('Move'), findsNWidgets(2));
    expect(find.text('Scan failed · 1'), findsOneWidget);
    expect(find.text('Media not found · 1'), findsOneWidget);
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media moved · 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kick.wav'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Media moved · 1'), findsNothing);

    // Without openReport, the report waits in the zone.
    await tasks().run((l10n) => 'Scan', (_) async => const Report());
    await tester.pumpAndSettle();
    expect(find.text('Nothing to report.'), findsNothing);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
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
}
