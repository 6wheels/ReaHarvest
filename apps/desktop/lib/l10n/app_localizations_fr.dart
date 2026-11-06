// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'ReaHarvest';

  @override
  String get searchHint => 'Rechercher des titres, tags, versions…';

  @override
  String get settings => 'Paramètres';

  @override
  String get close => 'Fermer';

  @override
  String get emptyLibraryTitle => 'Votre bibliothèque est vide';

  @override
  String get emptyLibraryHint =>
      'Ajoutez une bibliothèque dans les paramètres pour voir vos titres ici.';

  @override
  String noResults(String query) {
    return 'Aucun titre ne correspond à « $query »';
  }

  @override
  String versionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versions',
      one: '1 version',
      zero: 'Aucune version',
    );
    return '$_temp0';
  }

  @override
  String bpm(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get appearance => 'Apparence';

  @override
  String get theme => 'Thème';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get textSize => 'Taille du texte';

  @override
  String get language => 'Langue';

  @override
  String get languageSystem => 'Système';

  @override
  String get statusIdea => 'Idée';

  @override
  String get statusWriting => 'Écriture';

  @override
  String get statusRecording => 'Enregistrement';

  @override
  String get statusMixing => 'Mixage';

  @override
  String get statusDone => 'Terminé';
}
