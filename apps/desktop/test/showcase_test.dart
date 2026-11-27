import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reaharvest/main_showcase.dart';
import 'package:reaharvest/ui/to_sort/candidate_card.dart';
import 'package:reaharvest/ui/to_sort/outside_file.dart';

void main() {
  // Each change of a specimen rebuilt the whole showcase (~30 000 widgets,
  // ~0.4 s a key in debug): typing in a card or picking in its drop-downs
  // froze it.
  testWidgets('a change in the To sort card rebuilds that card only', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: showcaseOverrides(),
        child: const UiShowcaseApp(section: 'to_sort'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final rebuilt = <Type>[];
    debugOnRebuildDirtyWidget = (e, _) => rebuilt.add(e.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final label = find
        .descendant(
          of: find.byType(CandidateCard).first,
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(label, 'take 2');
    await tester.pump();
    await tester.tap(find.text('Mixing'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Done').last);
    // The pick is given after the frame of the tap: one more to show it.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Done'), findsOne);
    expect(find.text('take 2'), findsOne);
    expect(rebuilt.where((t) => t == CandidateCard), hasLength(2));
    expect(rebuilt, isNot(contains(OutsideFile)));
    expect(rebuilt, isNot(contains(UiShowcaseApp)));
    // A whole showcase is ~30 000 widgets.
    expect(rebuilt.length, lessThan(2000));
  });
}
