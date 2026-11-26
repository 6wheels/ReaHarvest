import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';

/// Width of the specimens.
const _width = 360.0;

/// Loads the fonts of the application: the tests would draw boxes instead
/// of the glyphs otherwise.
Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }

  // The icons come with the Flutter SDK running the tests.
  if (Platform.environment['FLUTTER_ROOT'] == null) {
    throw StateError('FLUTTER_ROOT is not set: run the goldens with flutter');
  }
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/'
    'material_fonts/materialicons-regular.otf',
  );
  final loader = FontLoader('MaterialIcons')
    ..addFont(icons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
  await loader.load();

  await load(Fonts.text, ['Inter.ttf']);
  await load(Fonts.mono, [
    'JetBrainsMono-Regular.ttf',
    'JetBrainsMono-Medium.ttf',
    'JetBrainsMono-Bold.ttf',
  ]);
}

/// One golden test of [name] per theme, dark and light: the [child] on the
/// background of the application, compared with `<name>-<theme>.png` next
/// to the test. Generated on Windows, the platform the CI compares on:
/// `flutter test --tags golden --update-goldens test/goldens/<file>`.
void goldenTest(String name, Widget Function(BuildContext) child) {
  setUpAll(loadFonts);
  for (final brightness in Brightness.values) {
    testWidgets('$name on the ${brightness.name} theme', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(brightness),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => ColoredBox(
                    color: context.colors.background,
                    child: SizedBox(
                      width: _width,
                      child: Padding(
                        padding: const EdgeInsets.all(Space.m),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [child(context)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('$name-${brightness.name}.png'),
      );
    });
  }
}
