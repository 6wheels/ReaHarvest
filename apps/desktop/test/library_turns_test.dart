import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/state/library_turns.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

void main() {
  const a = LibraryId('a');
  const b = LibraryId('b');
  late LibraryTurns turns;
  late List<String> log;

  setUp(() {
    turns = LibraryTurns();
    log = [];
  });

  /// A body that logs its start and end around [gate].
  Future<String> Function() body(String name, Completer<void> gate) =>
      () async {
        log.add('start $name');
        await gate.future;
        log.add('end $name');
        return name;
      };

  test('bodies of one library run one after the other, in order', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final third = Completer<void>();
    final results = [
      turns.run(a, body('1', first)),
      turns.run(a, body('2', second)),
      turns.run(a, body('3', third)),
    ];
    await pumpEventQueue();
    expect(log, ['start 1']);
    expect(turns.isBusy(a), isTrue);

    second.complete();
    third.complete();
    await pumpEventQueue();
    expect(log, ['start 1'], reason: 'the others wait for the first');

    first.complete();
    expect(await Future.wait(results), ['1', '2', '3']);
    expect(log, ['start 1', 'end 1', 'start 2', 'end 2', 'start 3', 'end 3']);
    expect(turns.isBusy(a), isFalse);
  });

  test('libraries are independent', () async {
    final first = Completer<void>();
    final other = Completer<void>();
    final running = turns.run(a, body('a', first));
    final done = turns.run(b, body('b', other));
    await pumpEventQueue();
    expect(log, ['start a', 'start b']);
    expect(turns.isBusy(b), isTrue);

    other.complete();
    expect(await done, 'b');
    expect(turns.isBusy(b), isFalse);
    expect(turns.isBusy(a), isTrue);
    first.complete();
    await running;
  });

  test('a failed body gives its turn to the next one', () async {
    final failed = turns.run<void>(a, () async => throw StateError('boom'));
    final next = turns.run(a, () async => 'next');
    await expectLater(failed, throwsStateError);
    expect(await next, 'next');
    expect(turns.isBusy(a), isFalse);
  });

  test('a library is not busy before its first body', () {
    expect(turns.isBusy(a), isFalse);
  });
}
