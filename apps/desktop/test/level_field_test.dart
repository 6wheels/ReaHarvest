import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';
import 'package:reaharvest/ui/to_sort/fix_dialog.dart' show Choice;

/// The fields of the "To sort" fixes, kept for the page of #149.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  testWidgets('a level field completes from the existing values', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var changes = 0;
    await pump(
      tester,
      LevelField(
        label: 'Artist',
        hint: 'Keep the proposed value',
        controller: controller,
        options: () => ['Sample Artist', 'Other', 'Samples'],
        error: null,
        onChanged: () => changes++,
      ),
    );
    expect(find.text('Keep the proposed value'), findsOne);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'sam');
    await tester.pumpAndSettle();
    expect(find.text('Sample Artist'), findsOne);
    expect(find.text('Samples'), findsOne);
    expect(find.text('Other'), findsNothing);

    // Enter alone keeps the typed text, in the spelling of an equal option.
    final submitted = <String>[];
    await pump(
      tester,
      LevelField(
        label: 'Artist',
        controller: controller,
        options: () => ['Sample Artist', 'Other', 'Samples'],
        error: null,
        onChanged: () => changes++,
        onSubmit: submitted.add,
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'sam');
    await tester.enterText(find.byType(TextField), 'samples');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'Samples');
    expect(submitted, ['sam', 'Samples']);

    // The page keys browse too; a picked option is submitted once.
    await tester.enterText(find.byType(TextField), 'sam');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'Samples');
    expect(submitted, ['sam', 'Samples', 'Samples']);
    // Enter keeps the focus.
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'sam');
    await tester.pumpAndSettle();

    // Down highlights the next option, Enter picks it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'Samples');

    await tester.enterText(find.byType(TextField), 'Oth');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Other');
    expect(changes, greaterThanOrEqualTo(3));
  });

  testWidgets('a new value says that the level will be created', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const hint = 'This level will be created';
    Widget field({String? error}) => LevelField(
      label: 'Artist',
      controller: controller,
      options: () => ['Sample Artist'],
      error: error,
      newValueHint: hint,
      onChanged: () {},
    );
    await pump(tester, field());
    expect(find.text(hint), findsNothing);

    await tester.enterText(find.byType(TextField), 'Someone');
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOne);

    // A known value, in any case: no hint.
    await tester.enterText(find.byType(TextField), 'sample artist');
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    await tester.tap(find.text('Sample Artist'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Sample Artist');
    expect(find.text(hint), findsNothing);

    // An error wins over the hint.
    controller.text = 'Someone';
    await pump(tester, field(error: 'Invalid level name'));
    expect(find.text(hint), findsNothing);
    expect(find.text('Invalid level name'), findsOne);
  });

  testWidgets('a choice shows its options and tells the one picked', (
    tester,
  ) async {
    int? picked;
    await pump(
      tester,
      Choice<int>(
        label: 'Level',
        value: 0,
        options: const {0: 'Artist', 1: 'Album'},
        onChanged: (v) => picked = v,
      ),
    );
    expect(find.text('Level'), findsOne);

    await tester.tap(find.text('Artist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Album').last);
    await tester.pumpAndSettle();
    expect(picked, 1);
  });
}
