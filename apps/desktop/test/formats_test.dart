import 'package:flutter/widgets.dart' hide Title;
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/ui/formats.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

void main() {
  test('formatSize picks the unit and the precision', () {
    expect(formatSize(0), '0 B');
    expect(formatSize(1023), '1023 B');
    expect(formatSize(1024), '1.0 KB');
    expect(formatSize(1536), '1.5 KB');
    expect(formatSize(10 * 1024), '10 KB');
    expect(formatSize(5 * 1024 * 1024), '5.0 MB');
    expect(formatSize(3 * 1024 * 1024 * 1024), '3.0 GB');
    expect(formatSize(2048 * 1024 * 1024 * 1024), '2.0 TB');
  });

  test('formatLength shows m:ss, then h:mm:ss from one hour', () {
    expect(formatLength(0), '0:00');
    expect(formatLength(65), '1:05');
    expect(formatLength(3599.4), '59:59');
    expect(formatLength(3600), '1:00:00');
    expect(formatLength(3725), '1:02:05');
  });

  test('versionNameOf trims the name and drops a project extension', () {
    expect(versionNameOf(' Song '), 'Song');
    expect(versionNameOf('Song.rpp'), 'Song');
    expect(versionNameOf('Song v2.RPP '), 'Song v2');
    expect(versionNameOf('Song.txt'), 'Song.txt');
  });

  test('versionName is the folder, else the file name', () {
    final folder = Version(
      fileName: 'Take/old.rpp',
      folder: 'Take',
      modified: DateTime(2026),
      size: 1,
    );
    final free = Version(
      fileName: 'sub/take.rpp',
      modified: DateTime(2026),
      size: 1,
    );
    expect((versionName(folder), versionName(free)), ('Take', 'sub/take'));
  });

  group('versionNameError', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final title = Title(
      id: NodeId.generate(),
      libraryId: LibraryId.generate(),
      path: 'Band/Album/Song',
      tags: const {},
      versions: [
        Version(
          fileName: 'Song/Song.rpp',
          folder: 'Song',
          modified: DateTime(2026),
          size: 1,
        ),
      ],
    );

    test('accepts a free name', () {
      expect(versionNameError(l10n, title, 'Song v2'), isNull);
      expect(versionNameError(l10n, title, 'Song v2.rpp'), isNull);
    });

    test('refuses an invalid name', () {
      for (final name in ['.rpp', 'a/b', ' ', 'Assets', '.hidden']) {
        expect(
          versionNameError(l10n, title, name),
          l10n.invalidVersionName,
          reason: name,
        );
      }
    });

    test('refuses a taken name, case-insensitively, except the current', () {
      expect(versionNameError(l10n, title, 'song'), l10n.versionNameTaken);
      expect(versionNameError(l10n, title, 'song.RPP'), l10n.versionNameTaken);
      expect(versionNameError(l10n, title, 'song', current: 'Song'), isNull);
    });
  });
}
