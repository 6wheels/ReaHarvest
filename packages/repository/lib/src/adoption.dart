import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';


/// Writes [metadata] into the EXTSTATE section of the project at [path]
/// ("To adopt", Save As duplicates, SPEC §4.2): targeted patch, atomic
/// write. Throws [FormatException] if the file is not valid UTF-8.
Future<void> writeVersionMetadata(
  RepositoryStorage storage,
  String path,
  VersionMetadata metadata,
) async {
  final text = await _readText(storage, path);
  final patched = setExtState(
    text,
    VersionMetadata.section,
    metadata.toExtState(),
  );
  await storage.write(path, Stream.value(utf8.encode(patched)));
}

/// Path separator of [ref]; the platform one if it has none (REAPER writes
/// `\` on Windows).
String separatorOf(String ref) {
  if (ref.contains(r'\')) return r'\';
  if (ref.contains('/')) return '/';
  return Platform.isWindows ? r'\' : '/';
}

/// Library path of the media [ref] of a project in [dir]; null if absolute
/// or outside the library.
String? resolveReference(String dir, String ref) {
  final slashed = ref.replaceAll(r'\', '/');
  if (slashed.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(slashed)) {
    return null;
  }
  final path = p.posix.normalize(_join(dir, slashed));
  if (path == '..' || path.startsWith('../') || path == '.') return null;
  return path;
}

/// Pool path for [source]: its name in [pool], reused when the file there is
/// identical (second value true), suffixed when another file has the name.
Future<(String, bool)> poolTarget(
  RepositoryStorage storage,
  String pool,
  String source,
) async {
  final name = p.posix.basename(source);
  final stem = p.posix.basenameWithoutExtension(name);
  final ext = p.posix.extension(name);
  for (var i = 1; ; i++) {
    final candidate = _join(pool, i == 1 ? name : '$stem ($i)$ext');
    final existing = await storage.stat(candidate);
    if (existing == null) return (candidate, false);
    if (await _sameContent(storage, source, candidate)) {
      return (candidate, true);
    }
  }
}

/// [path], or the first free `name (n).ext` variant.
Future<String> freePath(RepositoryStorage storage, String path) async {
  final dir = _parent(path);
  final stem = p.posix.basenameWithoutExtension(path);
  final ext = p.posix.extension(path);
  for (var i = 1; ; i++) {
    final candidate = i == 1 ? path : _join(dir, '$stem ($i)$ext');
    if (await storage.stat(candidate) == null) return candidate;
  }
}

/// Whether the files [a] and [b] have the same content: same size, then
/// compared as they are streamed (media can be large).
Future<bool> _sameContent(RepositoryStorage storage, String a, String b) async {
  final sa = await storage.stat(a);
  final sb = await storage.stat(b);
  if (sa == null || sb == null || sa.size != sb.size) return false;
  final ia = StreamIterator(storage.read(a));
  final ib = StreamIterator(storage.read(b));
  try {
    var ca = const <int>[];
    var cb = const <int>[];
    var oa = 0;
    var ob = 0;
    while (true) {
      if (oa == ca.length) {
        if (!await ia.moveNext()) return true; // Same size: b ends too.
        (ca, oa) = (ia.current, 0);
      } else if (ob == cb.length) {
        if (!await ib.moveNext()) return false;
        (cb, ob) = (ib.current, 0);
      } else {
        final n = min(ca.length - oa, cb.length - ob);
        for (var i = 0; i < n; i++) {
          if (ca[oa + i] != cb[ob + i]) return false;
        }
        oa += n;
        ob += n;
      }
    }
  } finally {
    await ia.cancel();
    await ib.cancel();
  }
}

Future<String> _readText(RepositoryStorage storage, String path) =>
    storage.read(path).transform(utf8.decoder).join();

String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

String _parent(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
