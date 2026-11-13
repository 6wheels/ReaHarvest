import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/logs.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/reaper.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';

import 'library_env.dart';

void main() {
  setUpLibraryEnv();

  group('REAPER providers', () {
    test('read the peaks preference of the resource folder', () async {
      final resources = Directory(p.join(root.path, 'resources'))..createSync();
      final ini = File(p.join(resources.path, 'REAPER.ini'))
        ..writeAsStringSync('[REAPER]\naltpeaks=1\naltpeakspath=P\n');
      expect(
        (await container.read(peaksPreferenceProvider.future))!.isRecommended,
        isTrue,
      );

      ini.writeAsBytesSync([0xff, 0xfe, 0xfd]);
      container.invalidate(peaksPreferenceProvider);
      expect(await container.read(peaksPreferenceProvider.future), isNull);

      final none = ProviderContainer(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            AppSettings(identity: const LocalIdentity(MemberId('M'), 'A')),
          ),
          defaultReaperResourcesProvider.overrideWithValue(null),
        ],
      );
      addTearDown(none.dispose);
      expect(await none.read(peaksPreferenceProvider.future), isNull);
    });

    test('default to this machine', () async {
      final machine = ProviderContainer();
      addTearDown(machine.dispose);
      final detected = await machine.read(detectedReaperProvider.future);
      if (detected != null) expect(File(detected).existsSync(), isTrue);
      expect(machine.read(defaultReaperResourcesProvider), isNotNull);
      expect(machine.read(reaperRunningProvider), isReaperRunning);
      expect(machine.read(reaperLauncherProvider), openInReaper);
    });
  });

  test('ports must be provided by main()', () {
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    expect(() => bare.read(settingsFileProvider), throwsA(anything));
    expect(() => bare.read(initialSettingsProvider), throwsA(anything));
    expect(() => bare.read(localIndexProvider), throwsA(anything));
    expect(() => bare.read(indexPathProvider), throwsA(anything));
    expect(() => bare.read(logFolderProvider), throwsA(anything));
    expect(bare.read(openFolderProvider), openFolder);
  });
}
