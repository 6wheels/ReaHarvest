import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart' as reference;
import 'package:path/path.dart' as p;
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

Uint8List bytes(int length) {
  final rnd = Random(length);
  return Uint8List.fromList([
    for (var i = 0; i < length; i++) rnd.nextInt(256),
  ]);
}

/// [data] split into chunks of random sizes.
Stream<List<int>> chunked(Uint8List data) async* {
  final rnd = Random(data.length);
  var start = 0;
  while (start < data.length) {
    final end = min(data.length, start + 1 + rnd.nextInt(5000));
    yield Uint8List.sublistView(data, start, end);
    start = end;
  }
}

void main() {
  test('hashes empty content', () async {
    expect(await xxh3Hash(const Stream.empty()), '2d06800538d394c2');
  });

  test('matches a reference implementation whatever the chunking', () async {
    // Lengths around the XXH3 internal thresholds (16, 128, 240, stripes,
    // 1 KB blocks) and a multi-block input.
    for (final length in [
      1,
      3,
      4,
      8,
      9,
      16,
      17,
      128,
      129,
      240,
      241,
      1024,
      1025,
      100000,
    ]) {
      final data = bytes(length);
      final expected = reference.xxh3.convert(data).hex();
      expect(await xxh3Hash(Stream.value(data)), expected, reason: '$length');
      expect(await xxh3Hash(chunked(data)), expected, reason: '$length');
    }
  });

  test('pads to 16 hex digits', () async {
    for (var i = 0; i < 300; i++) {
      expect(await xxh3Hash(Stream.value([i & 0xff, i >> 8])), hasLength(16));
    }
  });

  test('hashes a storage file in an isolate', () async {
    final root = Directory.systemTemp.createTempSync('reaharvest_hash_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = bytes(300000);
    File(p.join(root.path, 'a.wav')).writeAsBytesSync(data);

    final hasher = xxh3Hasher(MountedFolderStorage(root.path));
    expect(await hasher('a.wav'), reference.xxh3.convert(data).hex());
  });
}
