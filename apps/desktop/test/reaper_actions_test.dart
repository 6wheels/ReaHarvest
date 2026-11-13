import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/state/version_actions.dart';
import 'package:reaharvest/state/providers.dart';

import 'library_env.dart';

void main() {
  setUpLibraryEnv();

  test('opens versions and backups in REAPER', () async {
    final song = await bandWithSong();
    await versions.adopt(title(), version('v1.rpp'), 'main');
    final id = version('v1.rpp').metadata!.id;
    await versions.backup(title(), version('v1.rpp'));
    final saved = (await container.read(
      historyProvider(title().id).future,
    ))[id]!.single;
    final project = File(p.join(song, 'v1.rpp'));

    // REAPER not found.
    expect(await reaper.openVersion(title(), version('v1.rpp')), isFalse);
    expect(await reaper.openBackup(title(), saved), isFalse);
    expect(launched, isEmpty);

    await container
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(reaperExecutable: 'reaper.exe'));
    expect(await reaper.openVersion(title(), version('v1.rpp')), isTrue);
    expect(await reaper.openBackup(title(), saved), isTrue);
    expect(launched, [
      project.path,
      p.joinAll([
        p.dirname(p.dirname(p.dirname(song))),
        ...saved.path.split('/'),
      ]),
    ]);
  });
}
