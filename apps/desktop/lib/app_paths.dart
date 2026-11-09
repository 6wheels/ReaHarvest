import 'dart:io';

import 'package:path/path.dart' as p;

/// Per-user folder holding the settings and the local index.
String appDataDirectory({Map<String, String>? environment, String? os}) {
  final env = environment ?? Platform.environment;
  os ??= Platform.operatingSystem;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  if (os == 'windows') {
    return p.join(env['APPDATA'] ?? home, 'ReaHarvest');
  }
  if (os == 'macos') {
    return p.join(
      home,
      'Library',
      'Application Support',
      'io.github.6wheels.reaharvest',
    );
  }
  final config = env['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
  return p.join(config, 'reaharvest');
}

/// Path of the data file [name] (SPEC §5.1): next to the executable when it
/// exists there (portable mode), otherwise in [appData].
String dataFilePath(
  String name, {
  required String appData,
  String? executableDir,
}) {
  executableDir ??= p.dirname(Platform.resolvedExecutable);
  final portable = p.join(executableDir, name);
  return File(portable).existsSync() ? portable : p.join(appData, name);
}
