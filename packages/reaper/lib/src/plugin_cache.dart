import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

enum PluginStatus {
  installed,
  missing,

  /// The plugin format has no cache support (CLAP, AU, DX, LV2…).
  unknown,
}

const _vstKinds = {'VST', 'VSTi', 'VST3', 'VST3i'};

/// Plugins known to REAPER on this machine, read from its plugin caches.
class PluginCache {
  PluginCache._(this._vstFiles, this._jsPaths);

  /// Builds a cache from the contents of the `reaper-vstplugins*.ini` files
  /// and of `reaper-jsfx.ini` (null when absent).
  factory PluginCache.parse({
    required Iterable<String> vstIni,
    required String? jsIni,
  }) => PluginCache._({
    for (final ini in vstIni) ...parseVstCache(ini),
  }, jsIni == null ? {} : parseJsCache(jsIni));

  /// Reads the plugin caches of the REAPER [resourcePath], in an isolate.
  /// Missing files give an empty cache.
  static Future<PluginCache> load(String resourcePath) => Isolate.run(() {
    final dir = Directory(resourcePath);
    final vstIni = <String>[];
    String? jsIni;
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        final name = p.basename(f.path).toLowerCase();
        if (name.startsWith('reaper-vstplugins') && name.endsWith('.ini')) {
          vstIni.add(f.readAsStringSync());
        } else if (name == 'reaper-jsfx.ini') {
          jsIni = f.readAsStringSync();
        }
      }
    }
    return PluginCache.parse(vstIni: vstIni, jsIni: jsIni);
  });

  final Set<String> _vstFiles;
  final Set<String> _jsPaths;

  PluginStatus status(RppPlugin plugin) {
    if (plugin.kind == 'JS') {
      return _jsPaths.contains(normalizeJsPath(plugin.identifier))
          ? PluginStatus.installed
          : PluginStatus.missing;
    }
    if (_vstKinds.contains(plugin.kind)) {
      return _vstFiles.contains(normalizeVstFile(plugin.identifier))
          ? PluginStatus.installed
          : PluginStatus.missing;
    }
    return PluginStatus.unknown;
  }

  /// The [plugins] that are known to be missing on this machine.
  List<RppPlugin> missing(Iterable<RppPlugin> plugins) => [
    for (final pl in plugins)
      if (status(pl) == PluginStatus.missing) pl,
  ];
}

/// Cache key of a VST plugin file: base name, every character other than a
/// letter, digit, `.` or `_` replaced by `_`, lowercase
/// (`"Darkglass Ultra(x64).dll"` → `darkglass_ultra_x64_.dll`).
String normalizeVstFile(String file) {
  final base = file.split(RegExp(r'[\\/]')).last;
  return base.replaceAll(RegExp(r'[^A-Za-z0-9._]'), '_').toLowerCase();
}

/// Cache key of a JS effect: `/` separators, lowercase.
String normalizeJsPath(String path) => path.replaceAll(r'\', '/').toLowerCase();

/// Plugin file keys of the `[vstcache]` section. Entries without a plugin
/// name (`file=timestamp`, files REAPER could not load) are skipped.
Set<String> parseVstCache(String ini) {
  final files = <String>{};
  var inCache = false;
  for (final raw in ini.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inCache = line.toLowerCase() == '[vstcache]';
      continue;
    }
    if (!inCache) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    if (line.substring(eq + 1).split(',').length < 3) continue;
    // Shell plugins add `file<id=…` entries for each sub-plugin.
    final key = line.substring(0, eq);
    final shell = key.indexOf('<');
    files.add(normalizeVstFile(shell < 0 ? key : key.substring(0, shell)));
  }
  return files;
}

/// JS effect paths of `reaper-jsfx.ini` (`NAME path "JS: Name"` lines).
Set<String> parseJsCache(String ini) {
  final paths = <String>{};
  for (final line in ini.split('\n')) {
    final tokens = tokenize(line.trim());
    if (tokens.length >= 2 && tokens[0] == 'NAME') {
      paths.add(normalizeJsPath(tokens[1]));
    }
  }
  return paths;
}
