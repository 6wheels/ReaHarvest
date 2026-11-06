import 'dart:io';

import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

const fixtures = '../../test/fixtures';

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

List<File> allProjects() => Directory(fixtures)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.toLowerCase().endsWith('.rpp'))
    .toList();

void main() {
  group('tokens', () {
    test('tokenize bare and quoted tokens', () {
      expect(tokenize(r'FILE "a b.wav" 1'), ['FILE', 'a b.wav', '1']);
      expect(tokenize("TITLE 'My \"quoted\" title'"),
          ['TITLE', 'My "quoted" title']);
      expect(tokenize('RENDER_FILE ""'), ['RENDER_FILE', '']);
      expect(tokenize('  TEMPO 120 4 4  '), ['TEMPO', '120', '4', '4']);
    });

    test('quote follows REAPER delimiter cascade', () {
      expect(quote('demosong'), 'demosong');
      expect(quote('Sample song'), '"Sample song"');
      expect(quote('My "quoted" title'), "'My \"quoted\" title'");
      expect(quote('a "b" it\'s'), '`a "b" it\'s`');
      expect(quote(''), '""');
    });
  });

  group('document', () {
    test('every fixture parses and round-trips byte-exact', () {
      for (final f in allProjects()) {
        final text = f.readAsStringSync();
        final doc = RppDocument.parse(text);
        expect(doc.root.name, 'REAPER_PROJECT', reason: f.path);
        expect(doc.text, text, reason: f.path);
      }
    });
  });

  group('project', () {
    test('reads project metadata', () {
      final p = RppProject.parse(fixture('reference-metadata.rpp'));
      expect(p.reaperVersion, '7.84/win64');
      expect(p.title, 'demosong');
      expect(p.author, 'band');
      expect(p.notes, 'notes 1');
      expect(p.recordPath, r'.\audio-files');
      expect(p.renderFile, '');
      expect(p.renderPattern, r'$project');
      expect(p.tempo, 120);
      expect(p.timeSignature, (4, 4));
      expect(p.sampleRate, 44100);
      expect(p.extState('ReaHarvest'), {'VERSIONID': 'test'});
    });

    test('reads quoted title and tempo', () {
      final p = RppProject.parse(fixture('project-4.rpp'));
      expect(p.title, 'Sample song');
      expect(p.tempo, 109);
    });

    test('reads tracks, depth, plugins and media on all fixtures', () {
      for (final f in allProjects()) {
        final p = RppProject.parse(f.readAsStringSync());
        for (final t in p.tracks) {
          expect(t.depth, greaterThanOrEqualTo(0), reason: f.path);
        }
        expect(p.mediaFiles, everyElement(isNotEmpty), reason: f.path);
      }

      final p = RppProject.parse(fixture('project-1.rpp'));
      expect(p.tracks, isNotEmpty);
      expect(p.tracks.first.name, 'Track 1');
      expect(p.tracks.first.depth, 0);
      expect(p.tracks.any((t) => t.depth > 0), isTrue);
      expect(p.mediaFiles, everyElement(startsWith(r'.\audio-files\media-')));
      expect(p.length, greaterThan(0));

      final plugins = allProjects()
          .expand((f) => RppProject.parse(f.readAsStringSync()).allPlugins)
          .toSet();
      expect(
        plugins,
        contains(const RppPlugin(
          kind: 'VST3',
          name: 'TDR Kotelnikov (Tokyo Dawn Labs)',
          identifier: 'TDR Kotelnikov.vst3',
        )),
      );
      expect(plugins.where((p) => p.kind == 'JS'), isNotEmpty);
    });
  });

  group('patch', () {
    test('setExtState produces the block REAPER writes', () {
      final text = fixture('reference-metadata.rpp');
      final out = setExtState(text, 'ReaHarvest', {
        'versionId': '01JCTEST',
        'label': 'chorus B',
        'multiline': 'line1\nline2',
        'quotes': 'say "hi" it\'s `x`',
        'unicode': 'naïve ♪',
      });
      // Same layout and encodings as a file saved by REAPER 7.84.
      const expected = '''
    <REAHARVEST
      LABEL "chorus B"
      <BIN MULTILINE
        bGluZTEKbGluZTI=
      >
      <BIN QUOTES
        c2F5ICJoaSIgaXQncyBgeGA=
      >
      UNICODE "naïve ♪"
      VERSIONID 01JCTEST
    >''';
      expect(out.replaceAll('\r', ''), contains(expected));
      // The other section is untouched.
      expect(out, contains('<RPM'));
      expect(RppProject.parse(out).extState('reaharvest')['QUOTES'],
          'say "hi" it\'s `x`');
    });

    test('setExtState inserts EXTSTATE when missing, rest unchanged', () {
      final text = fixture('project-1.rpp');
      final out = setExtState(text, 'ReaHarvest', {'versionId': 'X'});
      expect(RppProject.parse(out).extState('ReaHarvest'), {'VERSIONID': 'X'});
      final a = text.split('\n'), b = out.split('\n');
      expect(b.length, a.length + 5);
      expect(b.sublist(0, a.length - 2), a.sublist(0, a.length - 2));
    });

    test('setExtState removes keys with empty values', () {
      final text = fixture('reference-metadata.rpp');
      final out = setExtState(text, 'ReaHarvest', {'versionId': ''});
      expect(RppProject.parse(out).extState('ReaHarvest'), isEmpty);
    });

    test('setRootAttribute replaces or inserts', () {
      final text = fixture('reference-metadata.rpp');
      final replaced = setRootAttribute(text, 'TITLE', ['New title']);
      expect(RppProject.parse(replaced).title, 'New title');
      expect(replaced.split('\n').length, text.split('\n').length);

      final tpl = fixture('project-template.rpp');
      final inserted = setRootAttribute(tpl, 'TITLE', ['Song']);
      expect(RppProject.parse(inserted).title, 'Song');
      expect(inserted.split('\n')[1], startsWith('  TITLE Song'));
    });
  });
}
