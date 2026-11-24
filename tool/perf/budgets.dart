// Budgets of docs/performance.md and the table of the benchmark results.

/// A measure and its budgets, in milliseconds (docs/performance.md).
final class Budget {
  const Budget(this.id, this.name, this.reference, this.ci);

  final String id;
  final String name;

  /// Limit on the reference machine; the result must be below it.
  final double reference;

  /// Limit on the CI runner (twice the reference).
  final double ci;

  double limit({required bool ci}) => ci ? this.ci : reference;
}

/// The budgets B1 to B7. B4 has two measures: the 90th percentile of the
/// frames, and the slowest one; B6 is the slowest frame.
const budgets = <Budget>[
  Budget('B1', 'Cold start', 1000, 2000),
  Budget('B2', 'First full scan', 30000, 60000),
  Budget('B3', 'Rescan with no change', 2000, 4000),
  Budget('B4 p90', 'Scrolling, 90th percentile frame', 16, 32),
  Budget('B4 max', 'Scrolling, slowest frame', 50, 100),
  Budget('B5', 'Search, one character', 100, 200),
  Budget('B6', 'Interface during a scan, slowest frame', 50, 100),
  Budget('B7 tray', 'Quit, tray icon shown', 500, 1000),
  Budget('B7 no tray', 'Quit, tray icon hidden', 500, 1000),
];

/// Median of [values] (the mean of the two middle ones when even).
double median(List<double> values) {
  if (values.isEmpty) throw ArgumentError('No value');
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Value at the [fraction] (0 to 1) of the sorted [values], rounded up.
double percentile(List<double> values, double fraction) {
  if (values.isEmpty) throw ArgumentError('No value');
  final sorted = [...values]..sort();
  return sorted[(fraction * sorted.length).ceil().clamp(1, sorted.length) - 1];
}

/// Result in milliseconds of each measure, by budget id; null or absent when
/// not measured.
typedef Results = Map<String, double?>;

/// Whether [value] is within the budget [b].
bool withinBudget(Budget b, double value, {required bool ci}) =>
    value < b.limit(ci: ci);

/// Table measure / result / budget, and whether every measure is within
/// its budget. A measure with no result counts as over its budget.
({String table, bool ok}) formatTable(Results results, {required bool ci}) {
  final rows = <List<String>>[
    ['Measure', 'Result', 'Budget', ''],
  ];
  var ok = true;
  for (final b in budgets) {
    final value = results[b.id];
    final good = value != null && withinBudget(b, value, ci: ci);
    ok &= good;
    rows.add([
      '${b.id}  ${b.name}',
      value == null ? 'not measured' : '${value.toStringAsFixed(1)} ms',
      '< ${b.limit(ci: ci).toStringAsFixed(0)} ms',
      good ? 'ok' : 'OVER',
    ]);
  }
  final widths = [
    for (var c = 0; c < 4; c++)
      rows.map((r) => r[c].length).reduce((a, b) => a > b ? a : b),
  ];
  final lines = [
    for (final r in rows)
      [for (var c = 0; c < 4; c++) r[c].padRight(widths[c])]
          .join('  ')
          .trimRight(),
  ];
  return (table: lines.join('\n'), ok: ok);
}

/// Marks written by the application in `perf-marks.txt`, one line per mark:
/// `<name> <microseconds since the epoch>`.
Map<String, DateTime> parseMarks(String text) => {
  for (final line in text.split('\n'))
    if (line.trim().split(' ') case [final name, final micros])
      name: DateTime.fromMicrosecondsSinceEpoch(int.parse(micros)),
};
