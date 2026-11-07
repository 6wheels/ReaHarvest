import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

const fixtures = '../../test/fixtures';

const vstIni = '''
[vstcache]
reaeq.dll=000CE403DF66DD01,1919247729,ReaEQ (Cockos)
TDR_Kotelnikov.vst3=00A1B2C3D4E5F601,352202470{56535454643936746472206B6F74656C},TDR Kotelnikov (Tokyo Dawn Labs)
reasynth.dll=001DC7F6DE66DD01,1919251321,ReaSynth (Cockos)!!!VSTi
broken.dll=0029826E4564D101
Some_Amp_x64_.dll=00452C38A1A2D901,1146243925,Some Amp (Vendor)
SS_11X.vst3=00DB78C4C80AD601,1456207592{5653545331313073732D313178000000,SS-11X (Vendor)
Shell_x64.vst3=37FD5FB44C98DB01,0,<SHELL>
Shell_x64.vst3<202745060=37FD5FB44C98DB01,202745060{5653544951454D637572766573206571,Sub (Vendor)
[xvst3_compat]
other.vst3=x - other.vst3/IPluginCompatibility
''';

const jsIni = '''
VERSION 1
NAME analysis/gfxscope "JS: Oscilloscope Meter (Cockos)"
NAME "IX/MIDI_Tool II" "JS: MIDI Tool v2"
REV "3-Band EQ" loser/3BandEQ
''';

RppPlugin vst(String kind, String file) =>
    RppPlugin(kind: kind, name: file, identifier: file);

ProcessResult result(int exitCode, String stdout) =>
    ProcessResult(0, exitCode, stdout, '');

void main() {
  group('paths', () {
    test('default resource paths per OS', () {
      expect(
        defaultResourcePath('windows', {'APPDATA': r'C:\Users\u\AppData'}),
        r'C:\Users\u\AppData\REAPER',
      );
      expect(
        defaultResourcePath('macos', {'HOME': '/Users/u'}),
        '/Users/u/Library/Application Support/REAPER',
      );
      expect(
        defaultResourcePath('linux', {'HOME': '/home/u'}),
        '/home/u/.config/REAPER',
      );
      expect(defaultResourcePath('windows', {}), isNull);
    });

    test('parses the registry default value', () {
      const out =
          '\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\REAPER\r\n'
          '    (Default)    REG_SZ    C:\\Program Files\\REAPER (x64)\r\n';
      expect(parseRegDefaultValue(out), r'C:\Program Files\REAPER (x64)');
      expect(parseRegDefaultValue('nothing'), isNull);
    });

    test('prefers the location reported by the OS', () async {
      final exe = await detectReaperExecutable(
        os: 'windows',
        env: {'ProgramFiles': r'C:\Program Files'},
        run: (cmd, args) async =>
            result(0, '    (Default)    REG_SZ    D:\\Audio\\REAPER\r\n'),
        exists: (_) => true,
      );
      expect(exe, r'D:\Audio\REAPER\reaper.exe');
    });

    test('falls back to the usual install locations', () async {
      final exe = await detectReaperExecutable(
        os: 'linux',
        env: {'HOME': '/home/u'},
        run: (cmd, args) async => result(1, ''),
        exists: (path) => path == '/opt/REAPER/reaper',
      );
      expect(exe, '/opt/REAPER/reaper');
    });

    test('macOS uses Spotlight, null when nothing exists', () async {
      final found = await detectReaperExecutable(
        os: 'macos',
        env: {'HOME': '/Users/u'},
        run: (cmd, args) async {
          expect(cmd, 'mdfind');
          return result(0, '/Apps/REAPER.app\n/Volumes/x/REAPER.app\n');
        },
        exists: (path) => path == '/Apps/REAPER.app',
      );
      expect(found, '/Apps/REAPER.app');

      final none = await detectReaperExecutable(
        os: 'macos',
        env: {'HOME': '/Users/u'},
        run: (cmd, args) async => throw ProcessException(cmd, args),
        exists: (_) => false,
      );
      expect(none, isNull);
    });
  });

  group('plugin cache', () {
    final cache = PluginCache.parse(vstIni: [vstIni], jsIni: jsIni);

    test('VST lookup by file name, spaces as underscores', () {
      expect(cache.status(vst('VST', 'reaeq.dll')), PluginStatus.installed);
      expect(cache.status(vst('VST', 'ReaEQ.DLL')), PluginStatus.installed);
      expect(
        cache.status(vst('VST3', 'TDR Kotelnikov.vst3')),
        PluginStatus.installed,
      );
      expect(cache.status(vst('VSTi', 'reasynth.dll')), PluginStatus.installed);
      expect(
        cache.status(vst('VST', r'C:\Plugins\reaeq.dll')),
        PluginStatus.installed,
      );
      expect(
        cache.status(vst('VST', 'Some Amp(x64).dll')),
        PluginStatus.installed,
      );
      expect(cache.status(vst('VST3', 'SS-11X.vst3')), PluginStatus.installed);
      expect(
        cache.status(vst('VST3', 'Shell x64.vst3')),
        PluginStatus.installed,
      );
      expect(cache.status(vst('VST', 'broken.dll')), PluginStatus.missing);
      expect(cache.status(vst('VST3', 'other.vst3')), PluginStatus.missing);
    });

    test('JS lookup by path', () {
      expect(
        cache.status(vst('JS', 'analysis/gfxscope')),
        PluginStatus.installed,
      );
      expect(
        cache.status(vst('JS', r'IX\MIDI_Tool II')),
        PluginStatus.installed,
      );
      expect(cache.status(vst('JS', 'loser/3BandEQ')), PluginStatus.missing);
    });

    test('formats without cache support are unknown', () {
      expect(cache.status(vst('CLAP', 'com.x.y')), PluginStatus.unknown);
      expect(cache.status(vst('AU', 'x')), PluginStatus.unknown);
    });

    test('missing plugins of a real project', () {
      final rpp = RppProject.parse(
        File('$fixtures/project-1.rpp').readAsStringSync(),
      );
      final missing = cache.missing(rpp.allPlugins);
      expect(missing, isNotEmpty);
      expect(missing.map((pl) => pl.identifier), isNot(contains('reaeq.dll')));
      expect(
        missing.map((pl) => pl.identifier),
        isNot(contains('TDR Kotelnikov.vst3')),
      );
    });

    test('loads caches from a resource folder', () async {
      final dir = Directory.systemTemp.createTempSync('reaper_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'reaper-vstplugins64.ini'))
          .writeAsStringSync(vstIni);
      File(p.join(dir.path, 'reaper-vstplugins.ini'))
          .writeAsStringSync('[vstcache]\nold32.dll=0,1,Old (Vendor)\n');
      File(p.join(dir.path, 'reaper-jsfx.ini')).writeAsStringSync(jsIni);

      final loaded = await PluginCache.load(dir.path);
      expect(loaded.status(vst('VST', 'reaeq.dll')), PluginStatus.installed);
      expect(loaded.status(vst('VST', 'old32.dll')), PluginStatus.installed);
      expect(
        loaded.status(vst('JS', 'analysis/gfxscope')),
        PluginStatus.installed,
      );

      final empty = await PluginCache.load(p.join(dir.path, 'none'));
      expect(empty.status(vst('VST', 'reaeq.dll')), PluginStatus.missing);
    });
  });

  group('preferences', () {
    test('peaks centralized when bit 0x1 and path are set', () {
      final ok = parsePeaksPreference(
        '[REAPER]\naltpeakspath=C:\\Peaks\naltpeaks=5\n',
      );
      expect(ok.altPeaks, isTrue);
      expect(ok.altPeaksPath, r'C:\Peaks');
      expect(ok.isRecommended, isTrue);

      expect(
        parsePeaksPreference('[REAPER]\naltpeakspath=C:\\Peaks\naltpeaks=4\n')
            .isRecommended,
        isFalse,
      );
      expect(
        parsePeaksPreference('[REAPER]\naltpeaks=1\naltpeakspath=\n')
            .isRecommended,
        isFalse,
      );
      expect(
        parsePeaksPreference('[other]\naltpeaks=1\naltpeakspath=x\n')
            .isRecommended,
        isFalse,
      );
    });

    test('missing REAPER.ini gives null', () async {
      expect(await loadPeaksPreference('/no/such/folder'), isNull);
      expect(await loadDefaultProjectTemplate('/no/such/folder'), isNull);
    });

    test('resolves the default project template', () async {
      final res = p.join('res', 'REAPER');
      expect(
        parseDefaultProjectTemplate(
          '[REAPER]\nnewprojtmpl=ProjectTemplates\\default.rpp\n',
          res,
        ),
        p.join(res, 'ProjectTemplates', 'default.rpp'),
      );
      expect(
        parseDefaultProjectTemplate('[REAPER]\nnewprojtmpl=\n', res),
        isNull,
      );
      final absolute = Platform.isWindows ? r'D:\t\a.rpp' : '/t/a.rpp';
      expect(
        parseDefaultProjectTemplate('[REAPER]\nnewprojtmpl=$absolute\n', res),
        absolute,
      );

      final dir = Directory.systemTemp.createTempSync('reaharvest_tmpl_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'REAPER.ini'))
          .writeAsStringSync('[REAPER]\nnewprojtmpl=ProjectTemplates\\a.rpp\n');
      expect(await loadDefaultProjectTemplate(dir.path), isNull);
      File(p.join(dir.path, 'ProjectTemplates', 'a.rpp'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<REAPER_PROJECT\n>\n');
      expect(
        await loadDefaultProjectTemplate(dir.path),
        p.join(dir.path, 'ProjectTemplates', 'a.rpp'),
      );
    });
  });

  group('launcher', () {
    test('open command per OS', () {
      final (winExe, winArgs) = openProjectCommand(
        r'C:\R\reaper.exe',
        r'C:\p\a.rpp',
        os: 'windows',
      );
      expect(winExe, r'C:\R\reaper.exe');
      expect(winArgs, ['-nonewinst', r'C:\p\a.rpp']);

      final (macExe, macArgs) = openProjectCommand(
        '/Applications/REAPER.app',
        '/p/a.rpp',
        os: 'macos',
      );
      expect(macExe, 'open');
      expect(macArgs, ['-a', '/Applications/REAPER.app', '/p/a.rpp']);
    });

    test('process detection', () async {
      expect(
        await isReaperRunning(
          os: 'windows',
          run: (cmd, args) async =>
              result(0, '"reaper.exe","1234","Console","1","500,000 K"'),
        ),
        isTrue,
      );
      expect(
        await isReaperRunning(
          os: 'windows',
          run: (cmd, args) async =>
              result(0, 'INFO: No tasks are running which match.'),
        ),
        isFalse,
      );
      expect(
        await isReaperRunning(
          os: 'linux',
          run: (cmd, args) async => result(1, ''),
        ),
        isFalse,
      );
      expect(
        await isReaperRunning(
          os: 'macos',
          run: (cmd, args) async => result(0, '4321'),
        ),
        isTrue,
      );
    });
  });
}
