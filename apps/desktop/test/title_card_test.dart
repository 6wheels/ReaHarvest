import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/l10n/app_localizations.dart';
import 'package:reaharvest/main_showcase.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest/ui/aurora.dart';
import 'package:reaharvest/ui/title_card.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' as domain;

const _longTitle = 'A very long song title that wraps on two lines or more';

domain.Title _title({List<String> tags = const [], bool withLevels = true}) =>
    domain.Title(
      id: const domain.NodeId('t'),
      libraryId: const domain.LibraryId('l'),
      path: 'Artist/Album/$_longTitle',
      levels: {
        if (withLevels) ...{
          'artist': 'An artist with a long name',
          'album': 'An album with a long name',
        },
        'title': _longTitle,
      },
      tags: tags,
      versions: [
        domain.Version(
          fileName: 'a.rpp',
          modified: DateTime(2026, 11, 12),
          size: 1,
          tempo: 120,
          sampleRate: 48000,
          metadata: const domain.VersionMetadata(
            id: domain.VersionId('v'),
            owner: domain.MemberId('me'),
            label: 'take',
          ),
        ),
      ],
    );

void main() {
  for (final scale in [0.75, 1.0, 1.5]) {
    for (final (tags, withLevels) in [
      (<String>[], true),
      (['live', 'standard tuning', 'rehearsal'], true),
      (<String>[], false),
    ]) {
      testWidgets('card at ${scale * 100} % with ${tags.length} tags'
          '${withLevels ? '' : ', without levels'}', (tester) async {
        tester.view
          ..physicalSize = const Size(400, 400)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: showcaseOverrides(),
            child: MaterialApp(
              theme: buildTheme(Brightness.dark),
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Center(
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: TitleCard(_title(tags: tags, withLevels: withLevels)),
                ),
              ),
            ),
          ),
        );
        // No overflow, whatever the text scale.
        expect(tester.takeException(), isNull);
        expect(find.text('120 BPM // 48 kHz'), findsOne);
        // The title is cut by an ellipsis, on one line, and the figures stay
        // clear of it.
        final title = tester.widget<Text>(find.text(_longTitle));
        expect((title.maxLines, title.overflow), (1, TextOverflow.ellipsis));
        final figures = tester.getRect(find.text('120 BPM // 48 kHz'));
        final name = tester.getRect(find.text(_longTitle));
        if (scale <= 1.0) {
          expect(name.overlaps(figures), isFalse);
        }
        // The title alone is centered in the aurora, levels or not.
        if (scale == 1.0) {
          final aurora = tester.getRect(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is AuroraPainter,
            ),
          );
          expect((name.center.dy - aurora.center.dy).abs(), lessThan(1));
        }
        expect(find.text('live'), tags.isEmpty ? findsNothing : findsOne);
        expect(tester.getSize(find.byType(TitleCard)), const Size(200, 200));
      });
    }
  }
}
