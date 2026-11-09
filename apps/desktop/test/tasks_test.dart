import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/tasks_zone.dart';

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

  testWidgets('tasks zone', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: TasksZone()),
          ),
        ),
      ),
    );
    expect(find.byType(TextButton), findsNothing, reason: 'hidden if empty');

    await tasks().run((l10n) => 'Broken', (_) async => throw 'boom');
    await tasks().run((l10n) => 'Stopped', (_) async {
      throw const TaskCancelled();
    });
    final step = Completer<void>();
    final running = tasks().run((l10n) => 'Scan', (task) async {
      task.progress(0.25);
      await step.future;
      task.checkCancelled();
    });
    await tester.pump();
    await tester.pump(Motion.medium);

    // Collapsed: the running task.
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Broken'), findsNothing);
    expect(find.text('Tasks · 3'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Cancelling…'), findsOneWidget);
    step.complete();
    await running;
    await tester.pump();
    expect(find.text('Cancelled'), findsOneWidget);

    // Expanded: every task, with the error of the failed one.
    await tester.tap(find.text('Tasks · 3'));
    await tester.pumpAndSettle();
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
}
