import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';

/// Displayed label of a layout level: provided template keys are translated
/// by the app, custom keys carry their own labels (SPEC §3.1).
String layoutLevelLabel(AppLocalizations l10n, LayoutLevel level) =>
    switch (level.key) {
      'artist' => l10n.levelArtist,
      'album' => l10n.levelAlbum,
      'title' => l10n.levelTitle,
      'project' => l10n.levelProject,
      'chapter' => l10n.levelChapter,
      'scene' => l10n.levelScene,
      _ => level.label(l10n.localeName),
    };

/// Count of the values of [level], for the group rows of the tree: "3
/// albums". A custom level has no plural to translate: "label: 3".
String levelCountLabel(AppLocalizations l10n, LayoutLevel level, int count) =>
    switch (level.key) {
      'artist' => l10n.levelCountArtist(count),
      'album' => l10n.levelCountAlbum(count),
      'title' => l10n.levelCountTitle(count),
      'project' => l10n.levelCountProject(count),
      'chapter' => l10n.levelCountChapter(count),
      'scene' => l10n.levelCountScene(count),
      _ => '${layoutLevelLabel(l10n, level)}: $count',
    };
