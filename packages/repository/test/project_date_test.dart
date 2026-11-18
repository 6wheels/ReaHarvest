import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

import 'memory_storage.dart';

/// The application never changes the date of a project (SPEC §4.2, #146).
void main() {
  const title = 'band/album/song';
  const version = '$title/v/v.rpp';
  final date = DateTime(2020, 5, 6, 7, 8, 9);
  late MemoryStorage storage;

  String project({VersionId? id, String media = r'Media\x.wav'}) =>
      '<REAPER_PROJECT 0.1 "7.0" 0\n'
      '  RECORD_PATH "Media" ""\n'
      '  <ITEM\n    <SOURCE WAVE\n      FILE "$media"\n    >\n  >\n'
      '${id == null ? '' : '  <EXTSTATE\n    <REAHARVEST\n'
                '      VERSIONID $id\n    >\n  >\n'}'
      '>\n';

  DateTime modified(String path) => storage.files[path]!.modified;

  setUp(() {
    storage = MemoryStorage()
      ..put('$title/.node.json', '{"nodeId":"${newUlid()}","level":"title"}');
  });

  test('adoption keeps the date of the project', () async {
    storage.put(version, project(), modified: date);

    await adoptVersion(
      storage,
      title,
      'v/v.rpp',
      VersionMetadata(id: VersionId.generate(), label: 'v'),
    );

    expect(storage.text(version), contains('VERSIONID'));
    expect(modified(version), date);
  });

  test('separating a duplicated version keeps the date of the copy', () async {
    storage.put(version, project(id: VersionId.generate()), modified: date);

    await separateDuplicateVersion(storage, title, 'v/v.rpp', label: 'v');

    expect(modified(version), date);
  });

  test('a backup keeps the date of its version', () async {
    storage.put(version, project(), modified: date);

    final backup = await backupVersion(storage, title, 'v/v.rpp');

    expect(storage.text(backup), contains(r'..\Media\x.wav'));
    expect(modified(backup), date);
    expect(modified(version), date);
  });

  test('a restore gives the version the date of the backup', () async {
    final backupDate = DateTime(2019, 1, 2);
    storage
      ..put(version, project(), modified: date)
      ..put(
        '$title/v/.history/v 2019-01-02 000000.rpp',
        project(media: r'..\Media\y.wav'),
        modified: backupDate,
      );

    final saved = await restoreBackup(
      storage,
      title,
      'v/v.rpp',
      '$title/v/.history/v 2019-01-02 000000.rpp',
    );

    expect(storage.text(version), contains(r'Media\y.wav'));
    expect(modified(version), backupDate);
    expect(modified(saved), date);
  });

  test('cleaning the paths of a backup keeps its date', () async {
    const backup = '$title/v/.history/v 2019-01-02 000000.rpp';
    storage.put(
      backup,
      project(media: r'..\Media\..\Media\x.wav'),
      modified: date,
    );

    await cleanBackupPaths(storage, backup);

    expect(storage.text(backup), contains(r'"..\Media\x.wav"'));
    expect(modified(backup), date);
  });

  test('a copied project keeps the date of its source', () async {
    storage
      ..put('a.rpp', project(), modified: date)
      ..put('a.wav', 'wav', modified: date);

    await copyKeepingProjectDate(storage, 'a.rpp', 'b/a.rpp');
    await copyKeepingProjectDate(storage, 'a.wav', 'b/a.wav');

    expect(modified('b/a.rpp'), date);
    expect(modified('b/a.wav'), isNot(date));
  });

  test('a new version takes the current date', () async {
    storage.put(version, project(id: VersionId.generate()), modified: date);

    final blank = await createVersion(
      storage,
      title,
      'blank',
      VersionMetadata(id: VersionId.generate(), label: 'blank'),
    );

    expect(modified(blank), isNot(date));
    expect(modified(blank).isAfter(date), isTrue);
  });
}
