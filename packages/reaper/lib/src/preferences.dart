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
