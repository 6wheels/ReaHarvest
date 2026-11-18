import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/glass_dialog.dart';

void main() {
  testWidgets('a dialog opened by the helper shows over a blurred backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGlassDialog<void>(
              context,
              (_) => const AlertDialog(title: Text('Glass')),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Glass'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
