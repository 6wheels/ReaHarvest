import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import 'harness.dart';

/// The index is written in a background isolate, the app only reads it
/// (SPEC §7.1, #103): frames keep being drawn while a library of 1,000
/// titles and 50,000 files is scanned. The longest gap between two frames
/// is logged, not asserted (it depends on the machine):
/// `flutter test integration_test/index_background_test.dart -d windows`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;

  setUp(() => h = Harness());

  tearDown(() => h.dispose());

  const titles = 1000;
  const filesPerTitle = 50;

  testWidgets('frames keep coming while 50,000 files are indexed', (
    tester,
  ) async {
    // Each title: one project, its two media and notes, 50 files.
    for (var i = 0; i < titles; i++) {
      final project = h.copyCleanProject(
        'Band/Artist ${i ~/ 100}/Album ${i ~/ 10 % 10}/Song $i/v1.rpp',
      );
      final notes = Directory(p.join(p.dirname(project), 'Notes'))
        ..createSync();
      for (var n = 0; n < filesPerTitle - 3; n++) {
        File(p.join(notes.path, 'note $n.txt')).writeAsStringSync('$n');
      }
    }
    await h.writeSettings();
    await h.start(tester);
    await tapText(tester, 'Later');

    final before = h.tasks.length;
    final adding = h.catalog.addLocal(
      folder: h.path('Band'),
      displayName: 'Band',
      layout: Layout.classic(),
    );
    final clock = Stopwatch()..start();
    var longest = Duration.zero;
    var frames = 0;
    final end = DateTime.now().add(const Duration(minutes: 5));
    while (!(h.tasks.length > before && h.tasks.last.isFinished)) {
      if (DateTime.now().isAfter(end)) fail('Timed out: scan');
      final start = clock.elapsed;
      await tester.pump(const Duration(milliseconds: 16));
      final gap = clock.elapsed - start;
      if (gap > longest) longest = gap;
      frames++;
    }
    await tester.runAsync(() => adding);
    debugPrint(
      'Index of $titles titles and ${titles * filesPerTitle} files written '
      'in ${clock.elapsed.inMilliseconds} ms; longest gap between two '
      'frames: ${longest.inMilliseconds} ms ($frames frames)',
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Close');
    final index = h.container.read(localIndexProvider);
    expect(index.titles(), hasLength(titles));
    expect(
      index.files(index.libraries().single.id).length,
      greaterThanOrEqualTo(titles * filesPerTitle),
    );
    expect(find.text('Song 0'), findsWidgets);
  });
}
