import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import 'labels.dart';

/// File size in B, KB, MB or GB.
String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

/// [name] with the `.RPP` extension when it has none.
String withProjectExtension(String name) {
  final trimmed = name.trim();
  return isProjectFile(trimmed) ? trimmed : '$trimmed.RPP';
}

/// Why [name] cannot be the file name of a version of [title] (other than
/// its version [current]); null when it can.
String? versionNameError(
  AppLocalizations l10n,
  Title title,
  String name, {
  String? current,
}) {
  final file = withProjectExtension(name);
  if (!isValidFolderName(file) ||
      p.posix.basenameWithoutExtension(file).trim().isEmpty) {
    return l10n.invalidVersionName;
  }
  final lower = file.toLowerCase();
  final taken = title.versions.any(
    (v) => v.fileName != current && v.fileName.toLowerCase() == lower,
  );
  return taken ? l10n.versionNameTaken : null;
}

/// Problems of a version, shown in the overview and the detail.
typedef VersionAlerts = ({
  /// Plugins known to be missing on this machine.
  List<PluginRef> missing,

  /// Other versions sharing its version id (Save As copies).
  List<(Title, Version)> duplicates,

  /// Version without metadata in a layout library.
  bool notAdopted,
});

VersionAlerts versionAlerts(WidgetRef ref, Title title, Version version) {
  final freeTree =
      ref.watch(indexedLibrariesProvider)[title.libraryId]?.isFreeTree ?? true;
  final cache = ref.watch(pluginCacheProvider).value;
  final m = version.metadata;
  return (
    missing: cache == null
        ? const <PluginRef>[]
        : missingPlugins(cache, version),
    duplicates: m == null
        ? const <(Title, Version)>[]
        : [
            for (final d in ref.watch(duplicatesProvider)[m.id] ?? const [])
              if (d.$2 != version) d,
          ],
    notAdopted: !freeTree && m == null,
  );
}

/// Versions of [title], most recently modified first.
List<Version> recentVersions(Title title) =>
    [...title.versions]..sort((a, b) => b.modified.compareTo(a.modified));

/// Display name of the library of [title].
String? libraryName(WidgetRef ref, Title title) => ref
    .watch(settingsProvider.select((s) => s.libraries))
    .where((l) => l.id == title.libraryId)
    .firstOrNull
    ?.displayName;

/// Tag values and library of [title], joined.
String titleSubtitle(WidgetRef ref, AppLocalizations l10n, Title title) => [
  for (final v in parentTags(title)) tagValueLabel(l10n, v),
  ?libraryName(ref, title),
].join(' · ');

/// Label (unless not [withLabel]), owner, date and tempo of [version],
/// joined.
String versionDetails(
  WidgetRef ref,
  AppLocalizations l10n,
  Version version, {
  bool withLabel = true,
}) {
  final owners = ref.watch(ownerNamesProvider);
  final m = version.metadata;
  return [
    if (withLabel && m != null) m.label,
    if (m?.owner case final owner?) owners[owner] ?? l10n.unknownOwner,
    shortDate(l10n, version.modified),
    if (version.tempo case final bpm?) l10n.bpm(bpm.round()),
  ].join(' · ');
}

/// Project length as `m:ss`, or `h:mm:ss` from one hour.
String formatLength(double seconds) {
  final d = Duration(milliseconds: (seconds * 1000).round());
  String two(int n) => n.toString().padLeft(2, '0');
  final s = two(d.inSeconds % 60);
  return d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:$s'
      : '${d.inMinutes}:$s';
}
