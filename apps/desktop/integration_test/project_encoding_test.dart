import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/app.dart';
import 'package:reaharvest/state/libraries.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest/state/tasks.dart';
import 'package:reaharvest/ui/overview.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

/// Runs the real app on a throwaway library holding a project saved in
/// Windows-1252 (#91): it is adopted, backed up and normalized through the
/// UI and keeps its encoding:
/// `flutter test integration_test -d windows` in `apps/desktop`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String song;
  late ProviderContainer container;

  /// Fixture [name], found from the working directory upwards.
  String fixture(String name) {
    for (var dir = Directory.current.absolute; ; dir = dir.parent) {
      final candidate = File(p.join(dir.path, 'test', 'fixtures', name));
      if (candidate.existsSync()) return candidate.path;
      if (dir.parent.path == dir.path) throw StateError('No fixture $name');
    }
  }

  File file(String relative) => File(p.joinAll([song, ...relative.split('/')]));

  bool isUtf8(List<int> bytes) {
    try {
      utf8.decode(bytes);
      return true;
    } on FormatException {
      return false;
    }
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('reaharvest_it_');
    final band = p.join(root.path, 'Band');
    song = p.join(band, 'Artist', 'Album', 'Song');
    Directory(song).createSync(recursive: true);
    // The fixture saved by REAPER, with an item added: same bytes, in
    // Windows-1252, referencing a media outside the pool.
    final text = latin1.decode(
      File(fixture('windows-1252.rpp')).readAsBytesSync(),
    );
    const item =
        '<ITEM\r\n  <SOURCE WAVE\r\n    FILE "audio-files\\Café.wav"\r\n  >\r\n>\r\n';
    File(p.join(song, 'old.rpp')).writeAsBytesSync(
      latin1.encode(text.replaceFirst('  <EXTENSIONS', '$item  <EXTENSIONS')),
    );
    File(p.join(song, 'audio-files', 'Café.wav'))
      ..createSync(recursive: true)
      ..writeAsStringSync('wav');
    Directory(p.join(root.path, 'resources')).createSync();

    final data = p.join(root.path, 'data');
    Directory(data).createSync();
    final settingsFile = SettingsFile(p.join(data, 'settings.json'));
    container = ProviderContainer(
      overrides: [
        settingsFileProvider.overrideWithValue(settingsFile),
        initialSettingsProvider.overrideWithValue(
          AppSettings(
            identity: LocalIdentity(MemberId.generate(), 'Tester'),
            language: 'en',
          ),
        ),
        localIndexProvider.overrideWithValue(
          LocalIndex.open(p.join(data, 'index.sqlite')),
        ),
        defaultReaperResourcesProvider.overrideWithValue(
          p.join(root.path, 'resources'),
        ),
        reaperRunningProvider.overrideWithValue(() async => false),
        logFolderProvider.overrideWithValue(p.join(data, 'logs')),
      ],
    );
    await container
        .read(libraryServiceProvider)
        .addLocal(folder: band, displayName: 'Band', layout: Layout.classic());
  });

  tearDown(() {
    container.read(localIndexProvider).close();
    container.dispose();
    root.deleteSync(recursive: true);
  });

  /// Pumps until [found] holds: file operations run in isolates, outside
  /// the frames that pumpAndSettle waits for.
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() found, {
    String? reason,
  }) async {
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (!found()) {
      if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('keeps a Windows-1252 project in its encoding (#91)', (
    tester,
  ) async {
    final original = file('old.rpp').readAsBytesSync();
    expect(isUtf8(original), isFalse);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReaHarvestApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Adoption: only the EXTSTATE lines are added.
    await tapText(tester, 'Song');
    await tester.tap(
      find.descendant(
        of: find.byType(Overview),
        matching: find.byTooltip('Open detail'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Label'), 'demo');
    await tester.pumpAndSettle();
    await tapText(tester, 'Adopt');
    await waitFor(
      tester,
      () =>
          latin1.decode(file('old.rpp').readAsBytesSync()).contains('EXTSTATE'),
      reason: 'version adopted',
    );
    final adopted = file('old.rpp').readAsBytesSync();
    expect(isUtf8(adopted), isFalse);
    final before = latin1.decode(original).split('\n');
    final extra = <String>[];
    var i = 0;
    for (final line in latin1.decode(adopted).split('\n')) {
      if (i < before.length && line == before[i]) {
        i++;
      } else {
        extra.add(line);
      }
    }
    expect(i, before.length, reason: 'every original line is unchanged');
    expect(extra.join('\n'), contains('EXTSTATE'));

    // Backup point: same encoding.
    await tapText(tester, 'Create a backup point');
    await waitFor(
      tester,
      () => find.text('No backup point yet.').evaluate().isEmpty,
      reason: 'backup listed',
    );
    final backup =
        Directory(p.join(song, '.history')).listSync().single as File;
    final saved = backup.readAsBytesSync();
    expect(isUtf8(saved), isFalse);
    expect(latin1.decode(saved), contains('NAME "Café tête"'));

    // Normalization: the media is moved, the reference rewritten in
    // Windows-1252.
    final service = container.read(libraryServiceProvider);
    final scanning = service.scanAll();
    await waitFor(
      tester,
      () => !container.read(tasksProvider).last.isRunning,
      reason: 'scan done',
    );
    await scanning;
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('To sort ·'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Café.wav'), findsOne);
    await tapText(tester, 'Fix…');
    await tapText(tester, 'Fix 1 item');
    await waitFor(
      tester,
      () => find.text('Media moved · 1').evaluate().isNotEmpty,
      reason: 'normalization report',
    );
    expect(find.textContaining('Files missing or changed'), findsNothing);
    await tapText(tester, 'Close');
    expect(file('Media/Café.wav').existsSync(), isTrue);
    final normalized = file('old.rpp').readAsBytesSync();
    expect(isUtf8(normalized), isFalse);
    final text = latin1.decode(normalized);
    expect(text, contains(r'FILE "Media\Café.wav"'));
    expect(text, contains('NAME "Café tête"'));
  });
}
