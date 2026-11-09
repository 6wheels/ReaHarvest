import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';
import 'package:test/test.dart';

/// Minimal project with relative, Windows-style and absolute media.
const project = '''
<REAPER_PROJECT 0.1 "7.0" 0
  RECORD_PATH "audio" ""
  <TRACK
    <ITEM
      <SOURCE WAVE
        FILE "audio\\x.wav"
      >
    >
    <ITEM
      <SOURCE WAVE
        FILE "take.wav"
      >
    >
    <ITEM
      <SOURCE WAVE
        FILE "C:\\abs.wav"
      >
    >
  >
>
''';

void main() {
  late Directory root;
  late MountedFolderStorage storage;

  File file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  void put(String path, [String content = '']) {
    final f = file(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  Future<String> hash(String path) => utf8.decodeStream(storage.read(path));

  Future<Migration> migration() async {
    final m = Migration.start(storage);
    await m.takeInventory(hash);
    return m;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('reaharvest_fixes_');
    storage = MountedFolderStorage(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('the migration storage keeps originals and refuses deletion', () async {
    put('a.rpp', 'original');
    put('notes.txt');
    final m = Migration.start(storage);
    expect(() => m.storage, throwsStateError);
    await m.takeInventory(hash);
    final guarded = m.storage;

    await guarded.move('a.rpp', 'song/a.rpp');
    await guarded.write('song/a.rpp', Stream.value(utf8.encode('rewritten')));
    await guarded.write('new.txt', Stream.value(utf8.encode('new')));
    await guarded.createDirectory('empty');
    await expectLater(guarded.delete('notes.txt'), throwsUnsupportedError);

    expect(file('${m.folder}/originals/a.rpp').readAsStringSync(), 'original');
    expect(file('${m.folder}/originals/new.txt').existsSync(), isFalse);
    expect(await guarded.stat('empty'), isNotNull);
    expect(await guarded.list(''), isNotEmpty);
    expect((await m.check(hash)).isEmpty, isTrue);
  });

  test('lifts a project into its title, references kept', () async {
    put('Song/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');
    put('Song/a.rpp', 'already there');
    put('Song/Alice/mix/a.rpp', project);
    final m = await migration();

    final moved = await liftProject(
      m.storage,
      'Song/Alice/mix/a.rpp',
      'Song',
      owner: const MemberId('alice'),
      status: 'mixing',
    );

    expect(moved, 'Song/a (2).rpp');
    final text = file(moved).readAsStringSync();
    final lifted = RppProject.parse(text);
    // Without a separator, the platform one is used, like REAPER does.
    final sep = Platform.isWindows ? r'\' : '/';
    expect(lifted.mediaFiles, [
      r'Alice\mix\audio\x.wav',
      'Alice${sep}mix${sep}take.wav',
      r'C:\abs.wav',
    ]);
    expect(lifted.document.root.line('RECORD_PATH')!.params, [
      'Alice${sep}mix${sep}audio',
      '',
    ]);
    final metadata = VersionMetadata.fromExtState(
      lifted.extState(VersionMetadata.section),
    )!;
    expect(metadata.owner, 'alice');
    final node = (await readNodeFile(storage, 'Song'))!;
    expect(node.versionStatuses, {metadata.id: 'mixing'});
    expect((await m.check(hash)).isEmpty, isTrue);

    // An adopted project keeps its metadata; no status is set without one.
    put('Root/sub/b.rpp', text);
    final again = await migration();
    final top = await liftProject(
      again.storage,
      'Root/sub/b.rpp',
      'Root',
      owner: const MemberId('bob'),
    );
    expect(top, 'Root/b.rpp');
    final kept = VersionMetadata.fromExtState(
      RppProject.parse(file(top).readAsStringSync())
          .extState(VersionMetadata.section),
    )!;
    expect(kept.id, metadata.id);
    expect(kept.owner, 'alice');
    expect(await readNodeFile(storage, 'Root'), isNull);
  });

  test('lifts a project of a library whose root is the title', () async {
    put('sub/c.rpp', '<REAPER_PROJECT\n>\n');
    final m = await migration();
    final moved = await liftProject(
      m.storage,
      'sub/c.rpp',
      '',
      owner: const MemberId('bob'),
    );
    expect(moved, 'c.rpp');
  });

  test('applies fixes one by one and reports each', () async {
    put('Song/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');
    put('Old/v.rpp', '<REAPER_PROJECT\n>\n');
    put('Taken/v.rpp', '<REAPER_PROJECT\n>\n');
    put('Band/Taken/x.txt');
    put('loose.rpp', '<REAPER_PROJECT\n>\n');
    put('Song/demo/d.rpp', '<REAPER_PROJECT\n>\n');
    final m = await migration();

    final report = await applyFixes(m.storage, const [
      MoveFolder('Old', 'Band/_Unassigned/Old'),
      MoveFolder('Taken', 'Band/Taken'),
      MoveProject('loose.rpp', 'Song'),
      LiftProject(
        'Song/demo/d.rpp',
        'Song',
        owner: MemberId('bob'),
        statusFolder: 'demo',
      ),
      MoveFolder('Gone', 'Band/Gone'),
    ]);

    expect(report.items[ReportKind.folderMoved], [
      const ReportItem('Band/_Unassigned/Old'),
    ]);
    expect(report.items[ReportKind.targetExists], [
      const ReportItem('Taken', 'Band/Taken'),
    ]);
    expect(report.items[ReportKind.projectMoved], [
      const ReportItem('Song/loose.rpp'),
      const ReportItem('Song/d.rpp'),
    ]);
    expect(report.items[ReportKind.statusFolderUnmatched], [
      const ReportItem('Song/d.rpp', 'demo'),
    ]);
    expect(report.items[ReportKind.fixFailed]!.single.path, 'Gone');
    expect(file('Band/_Unassigned/Old/v.rpp').existsSync(), isTrue);
    expect((await m.check(hash)).isEmpty, isTrue);
  });
}
