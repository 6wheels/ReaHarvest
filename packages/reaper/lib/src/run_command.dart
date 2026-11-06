import 'dart:io';

/// Runs an external command; injected so that tests can fake it.
typedef RunCommand = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<ProcessResult> runProcess(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

/// Runs [executable] and returns its trimmed stdout, or null on failure.
Future<String?> commandOutput(
  RunCommand run,
  String executable,
  List<String> arguments,
) async {
  try {
    final r = await run(executable, arguments);
    if (r.exitCode != 0) return null;
    final out = (r.stdout as String).trim();
    return out.isEmpty ? null : out;
  } on ProcessException {
    return null;
  }
}
