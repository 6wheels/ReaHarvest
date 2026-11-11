import 'dart:convert';
import 'dart:io';

import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

const fixtures = '../../test/fixtures';

String lf(String s) => s.replaceAll('\r', '');

String fixture(String name) => readText(File('$fixtures/$name'));

/// Text of [f]: UTF-8, or Latin-1 for a project that is not valid UTF-8
/// (`windows-1252.rpp`), which keeps every byte as one character.
String readText(File f) {
  final bytes = f.readAsBytesSync();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

List<File> allProjects() =>
    Directory(fixtures)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.rpp'))
        .toList();

void main() {
  group('tokens', () {
    test('tokenize bare and quoted tokens', () {
      expect(tokenize(r'FILE "a b.wav" 1'), ['FILE', 'a b.wav', '1']);
      expect(tokenize("TITLE 'My \"quoted\" title'"), [
        'TITLE',
        'My "quoted" title',
      ]);
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
        final text = readText(f);
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

    test('reads quoted title, notes with accents and tempo', () {
      final p = RppProject.parse(fixture('tracks.rpp'));
      expect(p.reaperVersion, '7.85/win64');
      expect(p.title, 'Sample song');
      expect(p.author, 'Band');
      expect(p.notes, 'line 1\n   line 2\nPrise de voix à refaire');
      expect(p.tempo, 128);
      expect(p.timeSignature, (3, 4));
      expect(p.sampleRate, 48000);
    });

    test('reads the platform of a project saved on Linux', () {
      final p = RppProject.parse(fixture('linux.RPP'));
      expect(p.reaperVersion, '7.84/linux-x86_64');
    });

    test('reads tracks, depth, plugins and media on all fixtures', () {
      for (final f in allProjects()) {
        final p = RppProject.parse(readText(f));
        for (final t in p.tracks) {
          expect(t.depth, greaterThanOrEqualTo(0), reason: f.path);
        }
        expect(p.mediaFiles, everyElement(isNotEmpty), reason: f.path);
      }

      final p = RppProject.parse(fixture('tracks.rpp'));
      expect(p.tracks.map((t) => (t.name, t.depth)), [
        ('Drums', 0),
        ('Kick', 1),
        ('Snare', 1),
        ('Overheads', 1),
        ('OH L', 2),
        ('OH R', 2),
        ('Bass', 0),
        ('Guitare élec', 0),
        ('Voix "lead"', 0),
        ('', 0),
        ('FX Bus', 0),
        ('Reverb', 1),
        ('Synth', 0),
      ]);
      expect(p.mediaFiles, hasLength(5));
      expect(p.mediaFiles, everyElement(startsWith(r'.\Media\')));
      expect(p.length, greaterThan(0));

      final plugins = allProjects()
          .expand((f) => RppProject.parse(readText(f)).allPlugins)
          .toSet();
      expect(
        plugins,
        contains(
          const RppPlugin(
            kind: 'VST3i',
            name: 'Surge XT (Surge Synth Team) (2->6ch)',
            identifier: 'Surge XT.vst3',
          ),
        ),
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
      expect(lf(out), contains('<RPM'));
      expect(
        RppProject.parse(out).extState('reaharvest')['QUOTES'],
        'say "hi" it\'s `x`',
      );
    });

    test('setExtState inserts EXTSTATE when missing, rest unchanged', () {
      final text = fixture('tracks.rpp');
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

    test('setNotes replaces content and keeps the header', () {
      final text = fixture('reference-metadata.rpp');
      final out = setNotes(text, 'first line\n  indented "quoted" <x>\n');
      expect(
        lf(out),
        contains(
          '  <NOTES 0 2\n    |first line\n'
          '    |  indented "quoted" <x>\n    |\n  >\n',
        ),
      );
      expect(
        RppProject.parse(out).notes,
        'first line\n  indented "quoted" <x>\n',
      );

      final cleared = setNotes(text, null);
      expect(lf(cleared), contains('  <NOTES 0 2\n  >\n'));
      expect(RppProject.parse(cleared).notes, '');
    });

    test('setNotes inserts the chunk after TITLE/AUTHOR when missing', () {
      // REAPER always writes the chunk: removed to test the insertion.
      final text = fixture(
        'tracks.rpp',
      ).replaceFirst(RegExp(r'  <NOTES 0 2\r?\n(    \|[^\n]*\n)*  >\r?\n'), '');
      expect(RppProject.parse(text).notes, isNull);
      final out = setNotes(text, 'hello');
      expect(RppProject.parse(out).notes, 'hello');
      expect(out.split('\n').length, text.split('\n').length + 3);
      expect(setNotes(text, ''), text);
    });

    test('setRenderMetadata merges, sorts and removes tags', () {
      final text = fixture('reference-metadata.rpp');
      final out = setRenderMetadata(text, {
        'ID3:TALB': 'Some album',
        'ID3:TIT2': null,
        'VORBIS:ALBUM': r'$title',
      });
      final tags = RppProject.parse(out).renderMetadata;
      expect(tags['ID3:TALB'], 'Some album');
      expect(tags.containsKey('ID3:TIT2'), isFalse);
      expect(tags['ID3:TPE1'], r'$author');
      expect(tags.keys.toList(), [...tags.keys]..sort());
      expect(lf(out), contains('    TAG ID3:TALB "Some album"\n'));
      expect(lf(out), contains('    TAG VORBIS:ALBUM \$title\n'));

      final removed = setRenderMetadata(text, {
        for (final k in RppProject.parse(text).renderMetadata.keys) k: null,
      });
      expect(lf(removed), isNot(contains('RENDER_METADATA')));
    });

    test('setRenderMetadata creates the chunk after RENDER_* lines', () {
      final text = fixture('project-template.rpp');
      final out = setRenderMetadata(text, {'ID3:TIT2': r'$title'});
      expect(RppProject.parse(out).renderMetadata, {'ID3:TIT2': r'$title'});
      final b = out.split('\n');
      final i = b.indexWhere((l) => l.trim() == '<RENDER_METADATA');
      expect(b[i - 1].trim(), startsWith('RENDER_'));
      expect(setRenderMetadata(text, {'ID3:TIT2': null}), text);
      // Metadata embedding enabled (render dialog checkbox).
      expect(lf(text), contains('\n  RENDER_STEMS 0\n'));
      expect(lf(out), contains('\n  RENDER_STEMS 512\n'));
      expect(out.split('\n').length, text.split('\n').length + 3);
      // Already enabled: RENDER_STEMS untouched.
      final ref = fixture('reference-metadata.rpp');
      final stems = RegExp(r'RENDER_STEMS .*');
      expect(
        stems.firstMatch(setRenderMetadata(ref, {'ID3:TALB': 'x'}))![0],
        stems.firstMatch(ref)![0],
      );
    });

    test('record path and render settings', () {
      final text = fixture('render-file.rpp');
      var out = setRootAttribute(text, 'RECORD_PATH', ['Media', '']);
      out = setRootAttribute(out, 'RENDER_FILE', ['Renders']);
      out = setRootAttribute(out, 'RENDER_PATTERN', [r'$title - $author']);
      final p = RppProject.parse(out);
      expect(p.recordPath, 'Media');
      expect(p.renderFile, 'Renders');
      expect(p.renderPattern, r'$title - $author');
      expect(lf(out), contains('  RECORD_PATH Media ""\n'));
      expect(out.split('\n').length, text.split('\n').length + 1);
    });

    test('rewriteMediaPaths rewrites FILE references only', () {
      final text = fixture('media-paths.rpp');
      String toMedia(String path) =>
          'Media\\${path.split(RegExp(r'[\\/]')).last}';
      final out = rewriteMediaPaths(text, toMedia);
      final before = RppProject.parse(text).mediaFiles;
      expect(RppProject.parse(out).mediaFiles, before.map(toMedia).toSet());
      final a = text.split('\n'), b = out.split('\n');
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) expect(a[i].trim(), startsWith('FILE '));
      }
      expect(lf(out), contains(r'FILE "Media\'));
      // Trailing tokens (MIDI `QN`) are preserved.
      final midi = allProjects()
          .map(readText)
          .firstWhere((t) => RegExp(r'FILE "[^"]+" QN').hasMatch(t));
      expect(
        rewriteMediaPaths(midi, toMedia),
        matches(RegExp(r'FILE "Media\\[^"]+\.mid" QN')),
      );
      // Identity mapping is a no-op.
      expect(rewriteMediaPaths(text, (p) => p), text);
    });

    test('non-regression: all patches on every fixture', () {
      for (final f in [...allProjects()]) {
        final text = readText(f);
        var out = setRootAttribute(text, 'TITLE', ['A "song" title']);
        out = setRootAttribute(out, 'AUTHOR', ['band']);
        out = setNotes(out, 'line 1\nline 2');
        out = setRootAttribute(out, 'RECORD_PATH', ['Media', '']);
        out = setRootAttribute(out, 'RENDER_FILE', ['Renders']);
        out = setRootAttribute(out, 'RENDER_PATTERN', [r'$title']);
        out = setRenderMetadata(out, {'ID3:TIT2': r'$title'});
        out = rewriteMediaPaths(
          out,
          (p) => 'Media\\${p.split(RegExp(r'[\\/]')).last}',
        );
        out = setExtState(out, 'ReaHarvest', {'versionId': 'V', 'owner': 'O'});

        final doc = RppDocument.parse(out);
        final p = RppProject(doc);
        expect(p.title, 'A "song" title', reason: f.path);
        expect(p.author, 'band', reason: f.path);
        expect(p.notes, 'line 1\nline 2', reason: f.path);
        expect(p.recordPath, 'Media', reason: f.path);
        expect(p.renderFile, 'Renders', reason: f.path);
        expect(p.renderPattern, r'$title', reason: f.path);
        expect(p.renderMetadata['ID3:TIT2'], r'$title', reason: f.path);
        expect(
          p.mediaFiles,
          everyElement(startsWith(r'Media\')),
          reason: f.path,
        );
        expect(p.extState('ReaHarvest'), {
          'OWNER': 'O',
          'VERSIONID': 'V',
        }, reason: f.path);

        // Tracks, plugins and the rest of the project are untouched.
        final orig = RppProject.parse(text);
        expect(
          p.tracks.map((t) => t.name),
          orig.tracks.map((t) => t.name),
          reason: f.path,
        );
        expect(p.allPlugins, orig.allPlugins, reason: f.path);
        expect(p.length, orig.length, reason: f.path);
        expect(p.tempo, orig.tempo, reason: f.path);
        expect(doc.text, out, reason: f.path);
      }
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
