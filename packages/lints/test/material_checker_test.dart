import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:reaharvest_lints/src/material_checker.dart';
import 'package:test/test.dart';

const _app = r'C:\repo\apps\desktop\lib\ui\library_page.dart';

/// The type names of the candidates of [code] when it lives in [path].
List<String> _names(String code, {String path = _app, String? shorthand}) {
  final unit = parseString(content: code).unit;
  return [
    for (final (_, name) in findWidgetCandidates(
      path,
      unit,
      shorthandType: shorthand == null ? null : (_) => shorthand,
    ))
      name,
  ];
}

void main() {
  test('a construction outside the allowed list is a candidate', () {
    expect(_names('final a = ListTile(title: x);'), ['ListTile']);
    expect(_names('final a = Material(child: InkWell());'), [
      'Material',
      'InkWell',
    ]);
    expect(_names('final a = ListTile.divideTiles(tiles: t);'), ['ListTile']);
  });

  test('a widget of the closed list is not', () {
    for (final name in allowedMaterialWidgets) {
      expect(_names('final a = $name();'), isEmpty, reason: name);
    }
  });

  test('a call on an expression is not a construction', () {
    expect(_names('final a = x.y.build();'), isEmpty);
    expect(_names('final a = builder.build(context);'), isEmpty);
  });

  test('a call to a function is not a construction', () {
    expect(_names('Widget f() => _tip();'), isEmpty);
    expect(_names('Widget f() => tip();'), isEmpty);
    expect(_names('Widget f() => _Tip();'), ['_Tip']);
  });

  test('the kit, the theme and files outside the app are not checked', () {
    const code = 'final a = Material();';
    expect(_names(code, path: '/r/apps/desktop/lib/ui/kit/a.dart'), isEmpty);
    expect(_names(code, path: '/r/apps/desktop/lib/theme/a.dart'), isEmpty);
    expect(_names(code, path: '/r/packages/domain/lib/a.dart'), isEmpty);
  });

  test('the showcase is checked', () {
    expect(
      _names(
        'final a = Material();',
        path: '/r/apps/desktop/lib/main_showcase.dart',
      ),
      ['Material'],
    );
  });

  test('a dot shorthand takes the type of its context', () {
    expect(_names('final a = Card(child: .new());', shorthand: 'ListTile'), [
      'ListTile',
    ]);
    expect(_names('final a = Card(child: const .new());', shorthand: 'Chip'), [
      'Chip',
    ]);
    expect(_names('final a = Card(child: .named());', shorthand: 'Chip'), [
      'Chip',
    ]);
    expect(
      _names('final a = Card(child: .new());', shorthand: 'Card'),
      isEmpty,
    );
    expect(_names('final a = Card(child: .new());'), isEmpty);
  });
}
