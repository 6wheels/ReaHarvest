import 'dart:io';

import 'package:path/path.dart' as p;

import 'run_command.dart';

/// Default REAPER resource folder for [os] (`Platform.operatingSystem`
/// value), or null when it cannot be derived from [env].
String? defaultResourcePath(String os, Map<String, String> env) {
  switch (os) {
    case 'windows':
      final appData = env['APPDATA'];
      return appData == null ? null : p.windows.join(appData, 'REAPER');
    case 'macos':
      final home = env['HOME'];
      return home == null
          ? null
          : p.posix.join(home, 'Library', 'Application Support', 'REAPER');
    case 'linux':
      final home = env['HOME'];
      return home == null ? null : p.posix.join(home, '.config', 'REAPER');
  }
  return null;
}

/// Usual install locations of the REAPER executable for [os], most likely
/// first. On macOS the executable is the `.app` bundle.
List<String> defaultExecutableCandidates(String os, Map<String, String> env) {
  switch (os) {
    case 'windows':
      final programFiles = env['ProgramFiles'] ?? r'C:\Program Files';
      return [
        p.windows.join(programFiles, 'REAPER (x64)', 'reaper.exe'),
        p.windows.join(programFiles, 'REAPER', 'reaper.exe'),
      ];
    case 'macos':
      final home = env['HOME'];
      return [
        '/Applications/REAPER.app',
        '/Applications/REAPER64.app',
        if (home != null) p.posix.join(home, 'Applications', 'REAPER.app'),
      ];
    case 'linux':
      final home = env['HOME'];
      return [
        if (home != null) p.posix.join(home, 'opt', 'REAPER', 'reaper'),
        '/opt/REAPER/reaper',
      ];
  }
  return const [];
}

/// Finds the REAPER executable: first the location reported by the OS
/// (Windows registry, macOS Spotlight, Linux `PATH`), then the usual install
/// locations. Returns null when none exists.
Future<String?> detectReaperExecutable({
  String? os,
  Map<String, String>? env,
  RunCommand run = runProcess,
  bool Function(String path)? exists,
}) async {
  os ??= Platform.operatingSystem;
  env ??= Platform.environment;
  exists ??= (path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  final reported = await _reportedExecutable(os, run);
  for (final c in [?reported, ...defaultExecutableCandidates(os, env)]) {
    if (exists(c)) return c;
  }
  return null;
}

Future<String?> _reportedExecutable(String os, RunCommand run) async {
  switch (os) {
    case 'windows':
      final out = await commandOutput(run, 'reg', [
        'query',
        r'HKLM\SOFTWARE\REAPER',
        '/ve',
      ]);
      final dir = out == null ? null : parseRegDefaultValue(out);
      return dir == null ? null : p.windows.join(dir, 'reaper.exe');
    case 'macos':
      final out = await commandOutput(run, 'mdfind', [
        "kMDItemCFBundleIdentifier == 'com.cockos.reaper'",
      ]);
      return out?.split('\n').first.trim();
    case 'linux':
      return commandOutput(run, 'which', ['reaper']);
  }
  return null;
}

/// Extracts the default value from `reg query <key> /ve` output, e.g.
/// `    (Default)    REG_SZ    C:\Program Files\REAPER (x64)`.
String? parseRegDefaultValue(String output) {
  for (final line in output.split('\n')) {
    final i = line.indexOf('REG_SZ');
    if (i < 0) continue;
    final value = line.substring(i + 'REG_SZ'.length).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}
