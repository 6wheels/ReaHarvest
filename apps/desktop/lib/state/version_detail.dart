import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

/// A media file referenced by a project: the reference as written, and its
/// size when the file is present on this machine.
typedef MediaStatus = ({String reference, int? size});

/// What the version detail view shows, read from a project (SPEC §5.3).
class VersionDetail {
  const VersionDetail({
    required this.reaperVersion,
    required this.sampleRate,
    required this.tempo,
    required this.signature,
    required this.tempoChanges,
    required this.length,
    required this.tracks,
    required this.media,
  });

  final String? reaperVersion;
  final int? sampleRate;
  final double? tempo;
  final (int, int)? signature;
  final List<RppTempoChange> tempoChanges;
  final double length;

  /// Tracks of depth 0 and 1.
  final List<RppTrack> tracks;
  final List<MediaStatus> media;
}

/// Reads the project at [path]: parsing and file checks, run in an isolate.
Future<VersionDetail> readVersionDetail(String path) => Isolate.run(() async {
  final folder = p.dirname(path);
  final (:text, encoding: _) = await readProject(
    MountedFolderStorage(folder),
    p.basename(path),
  );
  final project = RppProject.parse(text);
  return VersionDetail(
    reaperVersion: project.reaperVersion,
    sampleRate: project.sampleRate,
    tempo: project.tempo,
    signature: project.timeSignature,
    tempoChanges: project.tempoChanges,
    length: project.length,
    tracks: [
      for (final t in project.tracks)
        if (t.depth <= 1) t,
    ],
    media: [
      for (final reference in project.mediaFiles)
        (
          reference: reference,
          size: _sizeOf(
            p.isAbsolute(reference)
                ? reference
                : p.joinAll([folder, ...reference.split(RegExp(r'[\\/]'))]),
          ),
        ),
    ],
  );
});

/// Size of the file at [path], null when it is not there.
int? _sizeOf(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : null;
}

/// Detail of the project at an absolute path, parsed when first watched
/// (not indexed, SPEC §5.3). An unreadable project is not retried.
final versionDetailProvider = FutureProvider.autoDispose
    .family<VersionDetail, String>(
      (ref, path) => readVersionDetail(path),
      retry: (_, _) => null,
    );
