import 'package:flutter/widgets.dart' hide Title;
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/ui/formats.dart';
import 'package:reaharvest/ui/widgets.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
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

  test('sizeBreakdown lists the kinds of files, the largest first', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final version =
        Version(
          fileName: 'a/a.rpp',
          modified: DateTime(2026),
          size: 0,
        ).withSizes('a', const {
          SizeCategory.project: 2048,
          SizeCategory.media: 0,
          SizeCategory.history: 5 * 1024 * 1024,
          SizeCategory.reaperBackups: 1024,
          SizeCategory.renders: 4096,
          SizeCategory.other: 10,
        });
    expect(
      sizeBreakdown(l10n, version),
      'Backup points 5.0 MB · Renders 4.0 KB · Project 2.0 KB · '
      'REAPER backups 1.0 KB · Other 10 B',
    );
    expect(sizeCategoryLabel(l10n, SizeCategory.media), 'Media');
  });

  test('versionFolderCount counts folders, not projects', () {
    Version at(String file) => Version(
      fileName: file,
      folder: file.split('/').first,
      modified: DateTime(2026),
      size: 1,
    );
    final title = Title(
      id: NodeId.generate(),
      libraryId: LibraryId.generate(),
      path: 'A/B/C',
      tags: const {},
      versions: [at('a/a.rpp'), at('a/a copy.rpp'), at('b/b.rpp')],
    );
    expect(versionFolderCount(title), 2);
  });

  test('a shared version folder has its own failure message', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      failureMessage(l10n, const SharedVersionFolderException('a')),
      l10n.sharedVersionFolder,
    );
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
      for (final name in ['.rpp', 'a/b', ' ', '.hidden']) {
        expect(
          versionNameError(l10n, title, name),
          l10n.invalidVersionName,
          reason: name,
        );
      }
    });

    test('refuses the names reserved by the application', () {
      for (final name in ['Assets', 'media', 'Renders.rpp', 'Backups']) {
        expect(
          versionNameError(l10n, title, name),
          l10n.reservedVersionName,
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
