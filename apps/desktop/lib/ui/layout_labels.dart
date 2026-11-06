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
