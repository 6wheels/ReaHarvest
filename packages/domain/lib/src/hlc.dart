import 'dart:math' as math;

import 'ids.dart';

/// Hybrid Logical Clock timestamp, ordered by [millis], then [counter], then
/// [node]. The string form is fixed-width so it also sorts lexicographically.
final class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.node);

  /// Initial clock for [node], before any event.
  const Hlc.zero(MemberId node) : this(0, 0, node);

  final int millis;
  final int counter;
  final MemberId node;

  /// Next timestamp for a local event.
  Hlc tick(DateTime now) {
    final wall = now.millisecondsSinceEpoch;
    return wall > millis ? Hlc(wall, 0, node) : Hlc(millis, counter + 1, node);
  }

  /// Next timestamp after receiving [remote].
  Hlc receive(Hlc remote, DateTime now) {
    final wall = now.millisecondsSinceEpoch;
    final top = math.max(wall, math.max(millis, remote.millis));
    final int next;
    if (top == millis && top == remote.millis) {
      next = math.max(counter, remote.counter) + 1;
    } else if (top == millis) {
      next = counter + 1;
    } else if (top == remote.millis) {
      next = remote.counter + 1;
    } else {
      next = 0;
    }
    return Hlc(top, next, node);
  }

  /// Parses the form produced by [toString].
  static Hlc parse(String value) {
    final parts = value.split(':');
    if (parts.length != 3) throw FormatException('Invalid HLC', value);
    return Hlc(int.parse(parts[0]), int.parse(parts[1]), MemberId(parts[2]));
  }

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return node.compareTo(other.node);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >(Hlc other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Hlc && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(millis, counter, node);

  @override
  String toString() =>
      '${millis.toString().padLeft(15, '0')}:'
      '${counter.toString().padLeft(5, '0')}:$node';
}
