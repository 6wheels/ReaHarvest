import 'dart:io';

import 'package:path/path.dart' as p;

/// Peak cache settings of `REAPER.ini` (General > Paths).
class PeaksPreference {
  const PeaksPreference({required this.altPeaks, required this.altPeaksPath});

  /// `altpeaks` bit `0x1`: store all peak caches in the alternate path.
  final bool altPeaks;

  /// `altpeakspath`, null when empty.
  final String? altPeaksPath;

  /// Peaks are centralized outside the projects (recommended setting).
  bool get isRecommended => altPeaks && altPeaksPath != null;
}

PeaksPreference parsePeaksPreference(String reaperIni) {
  final values = _readSection(reaperIni, 'REAPER');
  final altPeaks = int.tryParse(values['altpeaks'] ?? '') ?? 0;
  final path = values['altpeakspath'] ?? '';
  return PeaksPreference(
    altPeaks: altPeaks & 0x1 != 0,
    altPeaksPath: path.isEmpty ? null : path,
  );
}

/// Reads the peaks preference from `REAPER.ini` in [resourcePath], or null
/// when the file does not exist.
Future<PeaksPreference?> loadPeaksPreference(String resourcePath) async {
  final file = File(p.join(resourcePath, 'REAPER.ini'));
  if (!await file.exists()) return null;
  return parsePeaksPreference(await file.readAsString());
}

/// Default template for new projects (`newprojtmpl`, Preferences > Project),
/// as an absolute path: written relative to the resource folder
/// [resourcePath] when the template is inside it. Null when unset.
String? parseDefaultProjectTemplate(String reaperIni, String resourcePath) {
  final value = _readSection(reaperIni, 'REAPER')['newprojtmpl']?.trim();
  if (value == null || value.isEmpty) return null;
  final path = p.joinAll(value.split(RegExp(r'[\\/]')));
  return p.isAbsolute(path) || value.startsWith(RegExp(r'[\\/]'))
      ? value
      : p.join(resourcePath, path);
}

/// Reads [parseDefaultProjectTemplate] from `REAPER.ini` in [resourcePath];
/// null when unset, or when the file or the template does not exist.
Future<String?> loadDefaultProjectTemplate(String resourcePath) async {
  final ini = File(p.join(resourcePath, 'REAPER.ini'));
  if (!await ini.exists()) return null;
  final path = parseDefaultProjectTemplate(
    await ini.readAsString(),
    resourcePath,
  );
  return path != null && await File(path).exists() ? path : null;
}

/// Project templates (`.rpp` files) in [folder] and its subfolders, sorted
/// by path; empty when the folder does not exist.
Future<List<String>> listProjectTemplates(String folder) async {
  final dir = Directory(folder);
  if (!await dir.exists()) return const [];
  return [
    await for (final e in dir.list(recursive: true))
      if (e is File && p.extension(e.path).toLowerCase() == '.rpp') e.path,
  ]..sort();
}

Map<String, String> _readSection(String ini, String section) {
  final values = <String, String>{};
  final header = '[${section.toLowerCase()}]';
  var inSection = false;
  for (final raw in ini.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inSection = line.toLowerCase() == header;
      continue;
    }
    if (!inSection) continue;
    final eq = line.indexOf('=');
    if (eq > 0) values[line.substring(0, eq)] = line.substring(eq + 1);
  }
  return values;
}
