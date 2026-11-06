import 'dart:io';

import 'package:path/path.dart' as p;

/// Per-user folder holding the settings and the local index.
String appDataDirectory() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  if (Platform.isWindows) {
    return p.join(env['APPDATA'] ?? home, 'ReaHarvest');
  }
  if (Platform.isMacOS) {
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
