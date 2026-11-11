import 'package:reaharvest_repository/reaharvest_repository.dart';
import 'package:test/test.dart';

void main() {
  test('joinPath and parentOf', () {
    expect(joinPath('', 'a'), 'a');
    expect(joinPath('x/y', 'a.rpp'), 'x/y/a.rpp');
    expect(parentOf('x/y/a.rpp'), 'x/y');
    expect(parentOf('x'), '');
    expect(parentOf(''), '');
  });

  group('isWithin', () {
    test('is strict and works at any depth', () {
      expect(isWithin('a/b/c', 'a'), isTrue);
      expect(isWithin('a/b', 'a/b'), isFalse);
      expect(isWithin('ab/c', 'a'), isFalse);
    });

    test('ignores the case unless asked', () {
      expect(isWithin('A/b', 'a'), isTrue);
      expect(isWithin('A/b', 'a', caseSensitive: true), isFalse);
      expect(isWithin('a/b', 'a', caseSensitive: true), isTrue);
    });

    test('the root contains all but paths leading outside the library', () {
      expect(isWithin('a/b', ''), isTrue);
      expect(isWithin('../a', ''), isFalse);
    });
  });

  test('isAbsoluteReference', () {
    expect(isAbsoluteReference('/home/me/a.wav'), isTrue);
    expect(isAbsoluteReference(r'\server\share\a.wav'), isTrue);
    expect(isAbsoluteReference(r'C:\Media\a.wav'), isTrue);
    expect(isAbsoluteReference('d:/Media/a.wav'), isTrue);
    expect(isAbsoluteReference(r'Media\a.wav'), isFalse);
    expect(isAbsoluteReference('../Media/a.wav'), isFalse);
    expect(isAbsoluteReference('a.wav'), isFalse);
  });

  test('separatorOf takes the one of the reference', () {
    expect(separatorOf(r'Media\a.wav'), r'\');
    expect(separatorOf('Media/a.wav'), '/');
    expect(separatorOf(r'a\b/c'), r'\');
  });

  group('resolveReference', () {
    test('resolves with both separators', () {
      expect(resolveReference('t/v', r'Media\a.wav'), 't/v/Media/a.wav');
      expect(resolveReference('t/v', '../Media/a.wav'), 't/Media/a.wav');
      expect(resolveReference('', 'a.wav'), 'a.wav');
    });

    test('returns null outside the library', () {
      expect(resolveReference('t', '../../a.wav'), isNull);
      expect(resolveReference('', '..'), isNull);
      expect(resolveReference('t', '..'), isNull);
      expect(resolveReference('', '.'), isNull);
      expect(resolveReference('', ''), isNull);
    });

    test('returns null for absolute references', () {
      expect(resolveReference('t', '/a.wav'), isNull);
      expect(resolveReference('t', r'C:\a.wav'), isNull);
      expect(resolveReference('t', r'\server\share\a.wav'), isNull);
    });
  });

  group('relativeReference', () {
    test('is written with the separator of the reference', () {
      expect(
        relativeReference('t/v', 't/Media/a.wav', like: r'Media\a.wav'),
        r'..\Media\a.wav',
      );
      expect(
        relativeReference('t/v', 't/Media/a.wav', like: 'Media/a.wav'),
        '../Media/a.wav',
      );
    });

    test('works from the root', () {
      expect(relativeReference('', 'Media/a.wav', like: '/'), 'Media/a.wav');
      expect(relativeReference('', 'Media/a.wav', like: r'\'), r'Media\a.wav');
    });
  });
}
