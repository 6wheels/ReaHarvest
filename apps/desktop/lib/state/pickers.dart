import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native file dialogs; replaced by fakes in tests.
class Pickers {
  const Pickers();

  /// Lets the user choose a folder; null when cancelled.
  Future<String?> folder({String? initial}) =>
      getDirectoryPath(initialDirectory: initial);

  /// Lets the user choose the REAPER executable (the `.app` bundle on
  /// macOS); null when cancelled.
  Future<String?> reaperExecutable() async {
    final group = Platform.isWindows
        ? const XTypeGroup(label: 'REAPER', extensions: ['exe'])
        : Platform.isMacOS
        ? const XTypeGroup(
            label: 'REAPER',
            uniformTypeIdentifiers: ['com.apple.application-bundle'],
          )
        : const XTypeGroup(label: 'REAPER');
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }
}

final pickersProvider = Provider<Pickers>((ref) => const Pickers());
