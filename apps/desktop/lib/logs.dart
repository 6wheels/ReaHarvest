import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Daily log files in [folder] (SPEC §8): `reaharvest-YYYY-MM-DD.log`, only
/// the last [keep] ones are kept.
final class LogFiles {
  LogFiles(this.folder, {this.keep = 14});

  final String folder;
  final int keep;

  static final _name = RegExp(r'^reaharvest-\d{4}-\d{2}-\d{2}\.log$');

  /// File of the day of [time].
  String pathFor(DateTime time) {
    final day = time.toIso8601String().substring(0, 10);
    return p.join(folder, 'reaharvest-$day.log');
  }

  /// Appends [record] to the file of its day.
  void write(LogRecord record) => File(pathFor(record.time))
      .writeAsStringSync(format(record), mode: FileMode.append, flush: true);

  /// Deletes the log files older than the last [keep] ones.
  void prune() {
    final files = [
      for (final f in Directory(folder).listSync())
        if (f is File && _name.hasMatch(p.basename(f.path))) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files.reversed.skip(keep)) {
      f.deleteSync();
    }
  }

  /// One record: time, level, logger, message, then its error and stack
  /// trace, indented.
  static String format(LogRecord record) {
    final lines = [
      '${record.time.toIso8601String()} ${record.level.name} '
          '${record.loggerName}: ${record.message}',
      ?record.error?.toString(),
      ?record.stackTrace?.toString().trimRight(),
    ];
    return '${lines.join('\n').replaceAll('\n', '\n  ')}\n';
  }
}

/// Sends every log record, and the uncaught errors, to daily files in
/// [folder], created if needed.
void startLogging(String folder) {
  Directory(folder).createSync(recursive: true);
  final files = LogFiles(folder)..prune();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen(files.write);
  final log = Logger('app');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe('Flutter error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.severe('Uncaught error', error, stack);
    return true;
  };
}

// coverage:ignore-start
// Starts the system file manager for real; replaced by a fake in tests.
/// Opens [folder] in the system file manager.
Future<void> openFolder(String folder) => Process.start(
  switch (Platform.operatingSystem) {
    'windows' => 'explorer',
    'macos' => 'open',
    _ => 'xdg-open',
  },
  [folder],
);
// coverage:ignore-end
