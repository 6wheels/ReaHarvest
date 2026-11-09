import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/app_paths.dart';

void main() {
  group('portable mode', () {
    late Directory exe;
    late String appData;

    setUp(() {
      final root = Directory.systemTemp.createTempSync('reaharvest_paths');
      addTearDown(() => root.deleteSync(recursive: true));
      exe = Directory(p.join(root.path, 'app'))..createSync();
      appData = p.join(root.path, 'appdata');
    });

    String path(String name) =>
        dataFilePath(name, appData: appData, executableDir: exe.path);

    test('uses the application data folder by default', () {
      expect(path('settings.json'), p.join(appData, 'settings.json'));
      expect(path('index.sqlite'), p.join(appData, 'index.sqlite'));
    });

    test('prefers each file found next to the executable', () {
      File(p.join(exe.path, 'settings.json')).writeAsStringSync('{}');
      expect(path('settings.json'), p.join(exe.path, 'settings.json'));
      expect(path('index.sqlite'), p.join(appData, 'index.sqlite'));

      File(p.join(exe.path, 'index.sqlite')).writeAsStringSync('');
      expect(path('index.sqlite'), p.join(exe.path, 'index.sqlite'));
    });

    test('an injected folder wins over the executable folder', () {
      File(p.join(exe.path, 'settings.json')).writeAsStringSync('{}');
      expect(
        dataFilePath(
          'settings.json',
          appData: appData,
          injected: true,
          executableDir: exe.path,
        ),
        p.join(appData, 'settings.json'),
      );
    });

    test('defaults to the folder of the running executable', () {
      expect(
        dataFilePath('settings.json', appData: appData),
        anyOf(
          p.join(p.dirname(Platform.resolvedExecutable), 'settings.json'),
          p.join(appData, 'settings.json'),
        ),
      );
    });
  });

  test('application data folder per platform', () {
    expect(
      appDataDirectory(environment: {'APPDATA': 'A'}, os: 'windows'),
      p.join('A', 'ReaHarvest'),
    );
    expect(
      appDataDirectory(environment: {'USERPROFILE': 'U'}, os: 'windows'),
      p.join('U', 'ReaHarvest'),
    );
    expect(
      appDataDirectory(environment: {'HOME': 'H'}, os: 'macos'),
      p.join(
        'H',
        'Library',
        'Application Support',
        'io.github.6wheels.reaharvest',
      ),
    );
    expect(
      appDataDirectory(environment: {'XDG_CONFIG_HOME': 'X'}, os: 'linux'),
      p.join('X', 'reaharvest'),
    );
    expect(
      appDataDirectory(environment: {}, os: 'linux'),
      p.join('.', '.config', 'reaharvest'),
    );
    expect(appDataDirectory(), isNotEmpty);
  });
}
