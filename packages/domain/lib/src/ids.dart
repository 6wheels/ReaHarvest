import 'dart:math';

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final _ulidPattern = RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$');
final _secureRandom = Random.secure();

/// Generates a ULID: 48-bit millisecond timestamp + 80 random bits, encoded
/// as 26 Crockford base32 characters (lexicographically sortable by time).
String newUlid({DateTime? now, Random? random}) {
  final rnd = random ?? _secureRandom;
  var time = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final chars = List.filled(26, '');
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford[time % 32];
    time ~/= 32;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford[rnd.nextInt(32)];
  }
  return chars.join();
}

/// Whether [value] is a canonical (uppercase) ULID.
bool isUlid(String value) => _ulidPattern.hasMatch(value);

/// Local member identity; owner of versions in every mode.
extension type const MemberId(String value) implements String {
  MemberId.generate() : this(newUlid());
}

/// Library identity, stored in `.library.json`.
extension type const LibraryId(String value) implements String {
  LibraryId.generate() : this(newUlid());
}

/// Collaboration group identity (collab mode).
extension type const GroupId(String value) implements String {
  GroupId.generate() : this(newUlid());
}

/// Layout node identity, stored in `.node.json`. A leaf node id is a title id.
extension type const NodeId(String value) implements String {
  NodeId.generate() : this(newUlid());
}

/// Version identity, stored in the `.RPP` EXTSTATE section.
extension type const VersionId(String value) implements String {
  VersionId.generate() : this(newUlid());
}
