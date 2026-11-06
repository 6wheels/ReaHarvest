import 'dart:io';

import 'run_command.dart';

/// Whether a REAPER process is running on this machine.
Future<bool> isReaperRunning({String? os, RunCommand run = runProcess}) async {
  os ??= Platform.operatingSystem;
  if (os == 'windows') {
    final out = await commandOutput(run, 'tasklist', [
      '/FI',
      'IMAGENAME eq reaper.exe',
      '/FO',
      'CSV',
      '/NH',
    ]);
    return out != null && out.toLowerCase().contains('"reaper.exe"');
  }
  // pgrep exits with 0 only when a process matches.
  return await commandOutput(run, 'pgrep', ['-ix', 'reaper']) != null;
}

/// Command line opening [projectFile] in the running REAPER instance (or
/// starting REAPER when closed). [executable] is the `.app` bundle on macOS.
(String, List<String>) openProjectCommand(
  String executable,
  String projectFile, {
  String? os,
}) {
  os ??= Platform.operatingSystem;
  if (os == 'macos') return ('open', ['-a', executable, projectFile]);
  return (executable, ['-nonewinst', projectFile]);
}

/// Opens [projectFile] in REAPER, without waiting for it.
Future<void> openInReaper(String executable, String projectFile) async {
  final (exe, args) = openProjectCommand(executable, projectFile);
  await Process.start(exe, args, mode: ProcessStartMode.detached);
}
