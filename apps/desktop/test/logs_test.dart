import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest/logs.dart';

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('reaharvest_logs');
    addTearDown(() => folder.deleteSync(recursive: true));
  });

  List<String> names() =>
      [for (final f in folder.listSync()) p.basename(f.path)]..sort();

  test('writes one file per day', () {
    final files = LogFiles(folder.path);
    files.write(LogRecord(Level.INFO, 'first', 'app'));
    final day = DateTime.now();
    final failure = LogRecord(
      Level.SEVERE,
      'second\nline',
      'tasks',
      'boom',
      StackTrace.fromString('#0 main\n'),
    );
    files.write(failure);
    final text = File(files.pathFor(day)).readAsStringSync();
    expect(text, contains(' INFO app: first\n'));
    expect(
      text,
      contains(' SEVERE tasks: second\n  line\n  boom\n  #0 main\n'),
    );
    expect(
      p.basename(files.pathFor(DateTime(2026, 3, 4, 23))),
      'reaharvest-2026-03-04.log',
    );
  });

  test('keeps only the last log files', () {
    for (final day in ['01', '02', '03']) {
      File(p.join(folder.path, 'reaharvest-2026-01-$day.log')).createSync();
    }
    File(p.join(folder.path, 'notes.txt')).createSync();
    LogFiles(folder.path, keep: 2).prune();
    expect(names(), [
      'notes.txt',
      'reaharvest-2026-01-02.log',
      'reaharvest-2026-01-03.log',
    ]);
  });

  test('logs records and uncaught errors into the folder', () {
    final flutterHandler = FlutterError.onError;
    final platformHandler = PlatformDispatcher.instance.onError;
    final presented = FlutterError.presentError;
    addTearDown(() {
      FlutterError.onError = flutterHandler;
      PlatformDispatcher.instance.onError = platformHandler;
      FlutterError.presentError = presented;
      Logger.root.clearListeners();
    });
    FlutterError.presentError = (_) {};

    final logs = p.join(folder.path, 'logs');
    startLogging(logs);
    Logger('app').info('hello');
    FlutterError.onError!(FlutterErrorDetails(exception: 'widget'));
    expect(
      PlatformDispatcher.instance.onError!('async', StackTrace.empty),
      isTrue,
    );

    final text = File(LogFiles(logs).pathFor(DateTime.now()))
        .readAsStringSync();
    expect(text, contains('INFO app: hello'));
    expect(text, contains('SEVERE app: Flutter error\n  widget'));
    expect(text, contains('SEVERE app: Uncaught error\n  async'));
  });
}
