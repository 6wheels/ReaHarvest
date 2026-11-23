import 'package:test/test.dart';

import '../budgets.dart';

void main() {
  test('median of an odd and an even number of values', () {
    expect(median([3, 1, 2]), 2);
    expect(median([4, 1, 3, 2]), 2.5);
    expect(() => median([]), throwsArgumentError);
  });

  test('percentile rounds up and keeps the slowest at 1', () {
    final values = [for (var i = 1; i <= 10; i++) i.toDouble()];
    expect(percentile(values, 0.9), 9);
    expect(percentile(values, 1), 10);
    expect(percentile(values, 0), 1);
    expect(() => percentile([], 0.5), throwsArgumentError);
  });

  Results within() => {for (final b in budgets) b.id: b.reference - 1};

  test('the table is ok when every measure is within its budget', () {
    final (:table, :ok) = formatTable(within(), ci: false);
    expect(ok, isTrue);
    expect(table, contains('B1  Cold start'));
    expect(table, contains('< 1000 ms'));
    expect(table, isNot(contains('OVER')));
  });

  test('a measure at its budget is over, the CI column doubles it', () {
    final results = within()..['B1'] = 1000;
    expect(formatTable(results, ci: false).ok, isFalse);
    expect(formatTable(results, ci: false).table, contains('OVER'));
    expect(formatTable(results, ci: true).ok, isTrue);
    expect(formatTable(results, ci: true).table, contains('< 2000 ms'));
  });

  test('a measure not measured fails', () {
    final results = within()..remove('B5');
    final (:table, :ok) = formatTable(results, ci: false);
    expect(ok, isFalse);
    expect(table, contains('not measured'));
  });

  test('marks are read by name, anything else is ignored', () {
    final marks = parseMarks('first-frame 1500000\nquit 2500000\n\njunk\n');
    expect(marks.keys, ['first-frame', 'quit']);
    expect(
      marks['quit']!.difference(marks['first-frame']!),
      const Duration(seconds: 1),
    );
  });
}
