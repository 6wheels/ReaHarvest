import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/kit/kit.dart';

/// Behavior of the components of the kit; their look is in `goldens/`.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('Pill', () {
    testWidgets('is an inert tag without onPressed', (tester) async {
      await pump(tester, const Pill('Mixing'));
      expect(find.text('MIXING'), findsOne);
      expect(find.byType(Tooltip), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('removes a tag with its tooltip button', (tester) async {
      var removed = 0;
      await pump(
        tester,
        Pill('Live', deleteTooltip: 'Remove Live', onDeleted: () => removed++),
      );
      await tester.tap(find.byTooltip('Remove Live'));
      expect(removed, 1);
    });

    testWidgets('is a key with onPressed, with its count and menu', (
      tester,
    ) async {
      var pressed = 0;
      await pump(
        tester,
        Pill(
          'To sort',
          count: 3,
          menuOpen: true,
          icon: Icons.add,
          active: true,
          onPressed: () => pressed++,
        ),
      );
      expect(find.text('TO SORT // 3'), findsOne);
      await tester.tap(find.byType(Pill));
      expect(pressed, 1);
    });
  });

  group('LightSwitch', () {
    testWidgets('toggles on tap and tells its state', (tester) async {
      final semantics = tester.ensureSemantics();
      final values = <bool>[];
      await pump(tester, LightSwitch(value: false, onChanged: values.add));
      expect(
        tester.getSemantics(find.byType(LightSwitch)),
        matchesSemantics(
          hasToggledState: true,
          isToggled: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      await tester.tap(find.byType(LightSwitch));
      expect(values, [true]);
      semantics.dispose();
    });

    testWidgets('does nothing when disabled', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, const LightSwitch(value: true, onChanged: null));
      final node = tester.getSemantics(find.byType(LightSwitch));
      expect(
        node,
        matchesSemantics(
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      semantics.dispose();
    });
  });

  group('DisclosureTile', () {
    testWidgets('shows its content when opened and hides it when closed', (
      tester,
    ) async {
      await pump(
        tester,
        const DisclosureTile(
          title: Text('Section'),
          children: [Text('Content')],
        ),
      );
      expect(find.text('Content'), findsNothing);
      await tester.tap(find.text('Section'));
      await tester.pumpAndSettle();
      expect(find.text('Content'), findsOne);
      await tester.tap(find.text('Section'));
      await tester.pumpAndSettle();
      expect(find.text('Content'), findsNothing);
    });

    testWidgets('starts open on request, with its leading icon', (
      tester,
    ) async {
      await pump(
        tester,
        const DisclosureTile(
          initiallyExpanded: true,
          leading: Icon(Icons.check),
          title: Text('Section'),
          children: [Text('Content')],
        ),
      );
      expect(find.text('Content'), findsOne);
      expect(find.byIcon(Icons.check), findsOne);
    });
  });

  group('PressableSurface', () {
    testWidgets('calls onTap', (tester) async {
      var taps = 0;
      await pump(
        tester,
        PressableSurface(onTap: () => taps++, child: const Text('Strip')),
      );
      await tester.tap(find.text('Strip'));
      expect(taps, 1);
    });

    testWidgets('is disabled without onTap', (tester) async {
      await pump(
        tester,
        const PressableSurface(onTap: null, child: Text('Strip')),
      );
      final ink = tester.widget<InkWell>(find.byType(InkWell));
      expect(ink.onTap, isNull);
    });
  });

  testWidgets('a removable tag is as high as an inert one', (tester) async {
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Pill('Live', key: Key('inert')),
          Pill(
            'Live',
            key: const Key('removable'),
            deleteTooltip: 'Remove',
            onDeleted: () {},
          ),
        ],
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('removable'))).height,
      tester.getSize(find.byKey(const Key('inert'))).height,
    );
  });

  testWidgets('a light checkbox has a wider target than its light', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      LightCheckbox(value: false, tooltip: 'All', onPressed: () => taps++),
    );
    expect(tester.getSize(find.byType(IconButton)).width, greaterThan(28));
    await tester.tapAt(
      tester.getTopLeft(find.byType(IconButton)) + const Offset(2, 2),
    );
    expect(taps, 1);
  });

  testWidgets('the suggestions of a level field touch its input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      SizedBox(
        width: 300,
        child: LevelField(
          label: 'Artist',
          controller: controller,
          options: () => ['Sample'],
          error: null,
          onChanged: () {},
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final input = tester.getBottomLeft(find.byType(EditableText)).dy;
    final menu = tester.getTopLeft(find.text('Sample')).dy;
    // Measured from the text, so that a gap under the input shows.
    expect(menu - input, lessThan(20));
  });

  testWidgets('the slider and the surfaces draw in every state', (
    tester,
  ) async {
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 300, child: Slider(value: 0.4, onChanged: (_) {})),
          const SizedBox(
            width: 300,
            child: Slider(value: 0.4, onChanged: null),
          ),
          for (final selected in [false, true])
            PressableSurface(
              selected: selected,
              onTap: () {},
              child: Text('strip $selected'),
            ),
        ],
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider).first),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.tap(find.text('strip true'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(2));
  });

  testWidgets('a suggestion is inside the tap region of its field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var outside = 0;
    final submitted = <String>[];
    await pump(
      tester,
      TextFieldTapRegion(
        onTapOutside: (_) => outside++,
        child: SizedBox(
          width: 300,
          child: LevelField(
            label: 'Tag',
            controller: controller,
            options: () => ['Sample'],
            error: null,
            compact: true,
            autofocus: true,
            onChanged: () {},
            onSubmit: submitted.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample'));
    await tester.pumpAndSettle();
    expect(submitted, ['Sample']);
    expect(outside, 0);
  });

  testWidgets('a disabled dropdown does not open', (tester) async {
    await pump(
      tester,
      SizedBox(
        width: 200,
        child: Dropdown<String>(
          enabled: false,
          value: 'a',
          options: const {'a': 'Artist', 'b': 'Album'},
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Artist'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Album'), findsNothing);
  });

  testWidgets('a level field is as high as the other fields', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(
      tester,
      SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TextField(key: Key('plain')),
            LevelField(
              key: const Key('level'),
              label: 'Artist',
              controller: controller,
              options: () => const [],
              error: null,
              dense: true,
              onChanged: () {},
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('level'))).height,
      tester.getSize(find.byKey(const Key('plain'))).height,
    );
  });

  testWidgets('a choice row selects on tap and tells its state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceRow(
            selected: true,
            label: 'Blank',
            hint: 'Empty project',
            onTap: () => taps++,
          ),
          const ChoiceRow(selected: false, label: 'Duplicate', onTap: null),
        ],
      ),
    );
    expect(find.text('Empty project'), findsOne);
    await tester.tap(find.text('Blank'));
    expect(taps, 1);
    expect(find.byType(ChoiceLight), findsNWidgets(2));
    expect(
      tester.getSemantics(find.byType(ChoiceRow).first),
      isSemantics(
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byType(ChoiceRow).last),
      isSemantics(
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: false,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a check row toggles on tap and tells its state', (tester) async {
    final semantics = tester.ensureSemantics();
    final values = <bool>[];
    await pump(
      tester,
      CheckRow(value: false, label: 'Tray', onChanged: values.add),
    );
    await tester.tap(find.text('Tray'));
    expect(values, [true]);
    expect(find.byType(ChoiceLight), findsOne);
    expect(
      tester.getSemantics(find.byType(CheckRow)),
      isSemantics(
        hasCheckedState: true,
        isChecked: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a panel is a surface with its frame', (tester) async {
    await pump(
      tester,
      const Surface.panel(elevation: Elevation.menu, child: Text('Menu')),
    );
    expect(find.text('Menu'), findsOne);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Menu'), matching: find.byType(Material))
          .first,
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(Radii.s));
    expect(shape.side.width, greaterThan(0));
    expect(material.elevation, Elevation.menu);
  });

  testWidgets('a Surface shows its child on its color', (tester) async {
    await pump(
      tester,
      const Surface(
        color: Colors.red,
        elevation: Elevation.menu,
        child: Text('Panel'),
      ),
    );
    expect(find.text('Panel'), findsOne);
    expect(
      tester.widget<Material>(find.byType(Material).last).color,
      Colors.red,
    );
  });
}
