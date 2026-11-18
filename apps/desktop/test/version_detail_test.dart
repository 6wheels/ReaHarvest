import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/state/navigation.dart';
import 'package:reaharvest/state/version_detail.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/title_detail/version_detail_view.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

void main() {
  test('reads the detail of a project, media presence included', () async {
    final dir = Directory.systemTemp.createTempSync('detail');
    addTearDown(() => dir.deleteSync(recursive: true));
    final project = File(p.join(dir.path, 'song.rpp'));
    File('../../test/fixtures/tracks.rpp').copySync(project.path);
    final media = RppProject.parse(project.readAsStringSync()).mediaFiles;
    final present = File(p.joinAll([dir.path, ...media.first.split(r'\')]))
      ..createSync(recursive: true)
      ..writeAsStringSync('audio');

    final detail = await readVersionDetail(project.path);
    expect(detail.sampleRate, 48000);
    expect(detail.tempo, 128);
    expect(detail.signature, (3, 4));
    expect(detail.tempoChanges, hasLength(2));
    expect(detail.reaperVersion, '7.85/win64');
    expect(detail.length, greaterThan(0));
    expect(detail.tracks.map((t) => t.depth), everyElement(lessThan(2)));
    expect(detail.tracks.first.name, 'Drums');
    expect(detail.media.map((m) => m.reference), media);
    expect(detail.media.first.size, present.lengthSync());
    expect(detail.media.skip(1).map((m) => m.size), everyElement(isNull));

    await expectLater(
      readVersionDetail(p.join(dir.path, 'missing.rpp')),
      throwsA(isA<FileSystemException>()),
    );
  });

  group('view', () {
    VersionDetail detail({
      int tracks = 3,
      List<RppPlugin> plugins = const [],
    }) => VersionDetail(
      reaperVersion: '7.85/win64',
      sampleRate: 48000,
      tempo: 128,
      signature: (3, 4),
      tempoChanges: const [
        RppTempoChange(position: 8.9, tempo: 140.5),
        RppTempoChange(position: 14.9, signature: (4, 4)),
      ],
      length: 65,
      tracks: [
        for (var i = 0; i < tracks; i++)
          RppTrack(
            name: i == 0 ? '' : 'Track $i',
            depth: i % 2,
            color: i == 1 ? 0x0000FF : null,
            plugins: i == 1 ? plugins : const [],
          ),
      ],
      media: const [
        (reference: 'Media/kick.wav', size: 2048),
        (reference: 'Media/gone.wav', size: null),
      ],
    );

    Future<void> pump(
      WidgetTester tester,
      Future<VersionDetail> Function() read, {
      PluginCache? cache,
    }) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          versionDetailProvider('a.rpp').overrideWith((ref) => read()),
          pluginCacheProvider.overrideWith((ref) async => cache),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(
            body: SingleChildScrollView(child: VersionDetailView('a.rpp')),
          ),
        ),
      ),
    );

    testWidgets('shows the facts, the changes, the tracks and the media', (
      tester,
    ) async {
      await pump(tester, () async => detail());
      await tester.pump();
      expect(
        find.textContaining('48000 Hz', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('0:08  ·  140.5 BPM'), findsOneWidget);
      expect(find.text('0:14  ·  4/4'), findsOneWidget);
      expect(find.textContaining('1:05', findRichText: true), findsOneWidget);
      expect(find.text('(unnamed)'), findsOneWidget);
      expect(find.text('Media/kick.wav'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('absent'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('marks the missing plugins of a track', (tester) async {
      const here = RppPlugin(
        kind: 'JS',
        name: 'here/fx',
        identifier: 'here/fx',
      );
      const gone = RppPlugin(
        kind: 'JS',
        name: 'gone/fx',
        identifier: 'gone/fx',
      );
      final cache = PluginCache.parse(
        vstIni: const [],
        jsIni: 'NAME here/fx "JS: Here"\n',
      );
      await pump(
        tester,
        () async => detail(plugins: [here, gone]),
        cache: cache,
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('⚠ gone/fx', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('⚠ here/fx', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('here/fx', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('folds the tracks beyond the twentieth', (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      addTearDown(tester.view.reset);
      await pump(tester, () async => detail(tracks: 25));
      await tester.pump();
      expect(find.text('Track 19'), findsOneWidget);
      expect(find.text('Track 20'), findsNothing);
      await tester.tap(find.text('Show 5 more'));
      await tester.pump();
      expect(find.text('Track 24'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('shows nothing while reading, then the error', (tester) async {
      final pending = Completer<VersionDetail>();
      await pump(tester, () => pending.future);
      expect(find.byType(Text), findsNothing);
      pending.completeError('boom');
      await tester.pump();
      await tester.pump();
      expect(find.text('The project cannot be read'), findsOneWidget);
    });
  });
}
