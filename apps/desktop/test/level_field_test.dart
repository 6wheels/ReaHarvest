import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/to_sort/fix_dialog.dart';

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
