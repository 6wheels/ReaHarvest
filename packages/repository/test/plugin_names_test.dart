import 'dart:convert';

import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

const song = 'Band/Album/Song';

List<int> utf16le(String text) => [
  for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
];

/// Base64 lines of a plugin state holding [state].
List<String> lines(List<int> state) {
  final text = base64.encode(state);
  return [
    for (var i = 0; i < text.length; i += 64)
      text.substring(i, i + 64 > text.length ? text.length : i + 64),
  ];
}

/// Project with a sampler whose state is [state], and the media [media].
String project(List<int> state, {List<String> media = const []}) => [
  '<REAPER_PROJECT 0.1 "7.0" 0',
  '  RECORD_PATH "Media" ""',
  '  <TRACK',
  for (final m in media) ...[
    '    <ITEM',
    '      <SOURCE WAVE',
    '        FILE "$m"',
    '      >',
    '    >',
  ],
  '    <FXCHAIN',
  '      <VST "VST: Sampler" sampler.dll 0 "" 1 ""',
  for (final line in lines(state)) '        $line',
  '      >',
  '    >',
  '  >',
  '>',
  '',
].join('\n');

void main() {
  group('namedOutsideSources', () {
    const names = ['Kick.wav', 'snare.wav'];

    test('finds a name in plain text, ignoring case', () {
      final text = '<REAPER_PROJECT\n  NOTES "use KICK.WAV here"\n>\n';
      expect(namedOutsideSources(text, names), {'Kick.wav'});
    });

    test('ignores the FILE line of a SOURCE chunk', () {
      final text = [
        '<REAPER_PROJECT',
        '  <SOURCE WAVE',
        r'    FILE "Media\Kick.wav"',
        '  >',
        '>',
      ].join('\n');
      expect(namedOutsideSources(text, names), isEmpty);
    });

    test('finds a name in a plugin state, as UTF-8 and as UTF-16LE', () {
      for (final state in [
        utf8.encode(r'sample=C:\Samples\KICK.wav;'),
        utf16le(r'C:\Samples\snare.wav'),
        [0, ...utf16le('snare.wav')],
      ]) {
        final found = namedOutsideSources(project(state), names);
        expect(found, hasLength(1), reason: '$state');
      }
    });

    test('finds nothing in a state naming no file', () {
      expect(
        namedOutsideSources(project(utf8.encode('nothing here')), names),
        isEmpty,
      );
    });
  });

  group('a file named by a plugin state', () {
    late MemoryStorage storage;

    for (final (label, state) in [
      ('UTF-8', utf8.encode(r'file=D:\kits\Hat.wav;')),
      ('UTF-16LE', utf16le(r'D:\kits\Hat.wav')),
    ]) {
      group(label, () {
        setUp(() {
          storage = MemoryStorage()
            ..put('$song/tracks.rpp', '')
            ..files['$song/tracks.rpp'] = (
              bytes: utf8.encode(project(state)),
              modified: DateTime(2026),
            )
            ..put('$song/samples/hat.wav', 'hat')
            ..put('$song/samples/loose.wav', 'loose')
            ..put('$song/Media/hat.wav', 'pool hat')
            ..put('$song/Media/orphan.wav', 'orphan');
        });

        test('is not moved by the normalization, and is reported', () async {
          final report = await normalizeMedia(storage, song);

          expect(storage.files, contains('$song/samples/hat.wav'));
          expect(storage.files, contains('$song/Media/loose.wav'));
          final reported = report.items[ReportKind.referencedByPlugin]!;
          expect(reported.map((i) => i.path), ['$song/samples/hat.wav']);
          expect(reported.single.detail, '$song/tracks.rpp');
          expect(report.items[ReportKind.mediaMoved]!.map((i) => i.path), [
            '$song/Media/loose.wav',
          ]);
        });

        test('is never listed by the purge', () async {
          storage.put('$song/Media/unnamed.wav', 'x');

          final listed = await unreferencedMedia(storage, song);

          expect(
            listed.map((e) => e.path),
            unorderedEquals([
              '$song/Media/orphan.wav',
              '$song/Media/unnamed.wav',
            ]),
          );
        });
      });
    }

    test('named by a backup only: not listed by the purge', () async {
      storage = MemoryStorage()
        ..put('$song/Media/hat.wav', 'hat')
        ..put('$song/Media/orphan.wav', 'orphan')
        ..put('$song/Song.rpp', project(utf8.encode('nothing')))
        ..put('$song/Backups/Song.rpp-bak', project(utf8.encode('Hat.wav')))
        ..put('$song/.trash/Old.rpp', project(utf8.encode('orphan.wav')));

      final listed = await unreferencedMedia(storage, song);

      expect(listed.map((e) => e.path), ['$song/Media/orphan.wav']);
    });
  });
}
