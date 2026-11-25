import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:reaharvest_lints/src/style_checker.dart';
import 'package:test/test.dart';

const _strict = 'C:/repo/apps/desktop/lib/ui/library_page.dart';
const _kit = 'C:/repo/apps/desktop/lib/ui/kit/button.dart';

/// The number of violations of [code] when it lives in [path].
int _count(String code, {String path = _strict, String? shorthand}) {
  final unit = parseString(content: code).unit;
  return findStyleViolations(
    path,
    unit,
    shorthandType: shorthand == null ? null : (_) => shorthand,
  ).length;
}

void main() {
  group('zones', () {
    test('are told apart by path, on any separator', () {
      expect(styleZoneOf(r'C:\r\apps\desktop\lib\ui\a.dart'), StyleZone.strict);
      expect(styleZoneOf(_kit), StyleZone.kit);
      expect(
        styleZoneOf('/r/apps/desktop/lib/theme/app_theme.dart'),
        StyleZone.unchecked,
      );
      expect(
        styleZoneOf('/r/apps/desktop/lib/l10n/app_localizations.dart'),
        StyleZone.unchecked,
      );
      expect(
        styleZoneOf('/r/apps/desktop/lib/main_showcase.dart'),
        StyleZone.unchecked,
      );
      expect(
        styleZoneOf('/r/apps/desktop/lib/showcase_tokens.dart'),
        StyleZone.unchecked,
      );
      expect(
        styleZoneOf('/r/apps/desktop/test/a_test.dart'),
        StyleZone.unchecked,
      );
    });

    test('an unchecked file reports nothing', () {
      expect(
        _count(
          'final a = Color(0xFF000000);',
          path: '/r/apps/desktop/lib/theme/x.dart',
        ),
        0,
      );
    });
  });

  group('colors', () {
    test('Color, Color.from* and Colors.* are reported', () {
      expect(_count('final a = Color(0xFF000000);'), 1);
      expect(_count('final a = Color.fromARGB(1, 2, 3, 4);'), 1);
      expect(_count('final a = Colors.red;'), 1);
      expect(_count('final a = const Color(0xFF000000);'), 1);
    });

    test('Colors.transparent and other Color members are allowed', () {
      expect(_count('final a = Colors.transparent;'), 0);
      expect(_count('final a = Color.lerp(x, y, t);'), 0);
    });

    test('are reported in the kit too', () {
      expect(_count('final a = Colors.red;', path: _kit), 1);
      expect(_count('final a = Color(0);', path: _kit), 1);
    });
  });

  group('text styles', () {
    test('TextStyle( is reported, TextStyle.lerp is not', () {
      expect(_count('final a = TextStyle();'), 1);
      expect(_count('final a = TextStyle.lerp(a, b, t);'), 0);
      expect(_count('final a = TextStyle();', path: _kit), 1);
    });

    test('fontSize and fontWeight are reported', () {
      expect(_count('final a = f(fontSize: 12);'), 1);
      expect(_count('final a = f(fontSize: size);'), 0);
      expect(_count('final a = f(fontWeight: FontWeight.w500);'), 1);
      expect(_count('final a = f(fontWeight: .bold);'), 1);
      expect(_count('final a = f(other: .bold);'), 0);
      expect(_count('final a = f(fontWeight: weight);'), 0);
      expect(_count('final a = f(other: FontWeight.w500);'), 0);
    });
  });

  group('metrics', () {
    test('a numeric literal in EdgeInsets or BorderRadius is reported', () {
      expect(_count('final a = EdgeInsets.all(8);'), 1);
      expect(_count('final a = EdgeInsets.symmetric(vertical: 6);'), 1);
      expect(_count('final a = EdgeInsets.only(top: Space.s);'), 0);
      expect(_count('final a = BorderRadius.circular(4);'), 1);
      expect(_count('final a = BorderRadius.circular(Radii.s);'), 0);
    });

    test('the literal zero is allowed', () {
      expect(_count('final a = EdgeInsets.only(top: 0);'), 0);
      expect(_count('final a = EdgeInsets.only(top: 0.0);'), 0);
      expect(_count('final a = c.withValues(alpha: 0);'), 0);
    });

    test('Radius.circular is reported, other Radius members are not', () {
      expect(_count('final a = Radius.circular(3);'), 1);
      expect(_count('final a = Radius.elliptical(3, 4);'), 2);
      expect(_count('final a = Radius.circular(Radii.s);'), 0);
      expect(_count('final a = Radius.lerp(a, b, t);'), 0);
    });

    test('SizedBox width and height are reported', () {
      expect(_count('final a = SizedBox(width: 4);'), 1);
      expect(_count('final a = SizedBox(width: 4, height: 6);'), 2);
      expect(_count('final a = SizedBox(width: Space.s);'), 0);
      expect(_count('final a = SizedBox(child: x);'), 0);
      expect(_count('final a = SizedBox.shrink();'), 0);
    });

    test('the alpha of withValues and the value of withOpacity', () {
      expect(_count('final a = c.withValues(alpha: 0.5);'), 1);
      expect(_count('final a = c.withValues(red: 0.5);'), 0);
      expect(_count('final a = c.withOpacity(0.5);'), 1);
      expect(_count('final a = c.withValues(alpha: tokens.dim);'), 0);
    });

    test('the size of an Icon', () {
      expect(_count('final a = Icon(x, size: 16);'), 1);
      expect(_count('final a = Icon(x, size: IconSizes.m);'), 0);
      expect(_count('final a = Icon(x);'), 0);
    });

    test('are allowed in the kit', () {
      for (final code in [
        'final a = EdgeInsets.all(8);',
        'final a = SizedBox(width: 4);',
        'final a = f(fontSize: 12);',
        'final a = c.withValues(alpha: 0.5);',
        'final a = Icon(x, size: 16);',
        'final a = BorderRadius.circular(3);',
        'final a = f(duration: Duration(milliseconds: 90));',
      ]) {
        expect(_count(code, path: _kit), 0, reason: code);
      }
    });
  });

  group('durations', () {
    test('are reported in a style argument only', () {
      expect(_count('final a = f(duration: Duration(seconds: 1));'), 1);
      expect(_count('final a = f(waitDuration: Duration(seconds: 1));'), 1);
      expect(_count('final a = f(delay: Duration(seconds: 1));'), 1);
      expect(_count('final a = Timer(Duration(seconds: 1), g);'), 0);
      expect(_count('final a = Duration(seconds: 1);'), 0);
      expect(_count('final a = f(other: Duration(seconds: 1));'), 0);
      expect(_count('final a = f(duration: Duration.zero);'), 0);
      expect(_count('final a = f(duration: tokens.fast);'), 0);
    });
  });

  group('dot shorthands', () {
    test('take the type of their context', () {
      expect(_count('final a = f(p: .all(13));', shorthand: 'EdgeInsets'), 1);
      expect(_count('final a = f(p: .all(0));', shorthand: 'EdgeInsets'), 0);
      expect(
        _count('final a = f(c: .fromARGB(1, 2, 3, 4));', shorthand: 'Color'),
        1,
      );
      expect(_count('final a = f(c: .lerp(a, b, t));', shorthand: 'Color'), 0);
      expect(_count('final a = f(r: .circular(6));', shorthand: 'Radius'), 1);
      expect(
        _count(
          'final a = f(duration: .new(seconds: 1));',
          shorthand: 'Duration',
        ),
        1,
      );
      expect(_count('final a = f(s: .new());', shorthand: 'TextStyle'), 1);
      expect(
        _count('final a = f(s: const .new());', shorthand: 'TextStyle'),
        1,
      );
      expect(
        _count('final a = f(w: .new(width: 4));', shorthand: 'SizedBox'),
        1,
      );
    });

    test('are ignored when the type is unknown or not a style', () {
      expect(_count('final a = f(p: .all(13));'), 0);
      expect(_count('final a = f(p: .all(13));', shorthand: 'Other'), 0);
      expect(_count('final a = f(p: .zero);', shorthand: 'EdgeInsets'), 0);
    });

    test('follow the zones', () {
      expect(
        _count(
          'final a = f(p: .all(13));',
          path: _kit,
          shorthand: 'EdgeInsets',
        ),
        0,
      );
    });
  });
}
