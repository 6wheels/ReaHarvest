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

  @override
  String get levelArtist => 'Artiste';

  @override
  String get levelAlbum => 'Album';

  @override
  String get levelTitle => 'Titre';

  @override
  String get levelProject => 'Projet';

  @override
  String get levelChapter => 'Chapitre';

  @override
  String get levelScene => 'Scène ou titre';

  @override
  String get welcomeTitle => 'Bienvenue dans ReaHarvest';

  @override
  String get welcomeHint =>
      'Configurons votre première bibliothèque. Cela ne prend qu\'une minute.';

  @override
  String get yourName => 'Votre nom';

  @override
  String get yourNameHint => 'Affiché comme propriétaire de vos versions.';

  @override
  String get later => 'Plus tard';

  @override
  String get continueAction => 'Continuer';

  @override
  String get back => 'Retour';

  @override
  String get finish => 'Terminer';

  @override
  String get cancel => 'Annuler';

  @override
  String stepOf(int current, int total) {
    return 'Étape $current sur $total';
  }

  @override
  String get libraryStepTitle => 'Votre première bibliothèque';

  @override
  String get libraryStepHint =>
      'Choisissez le dossier qui contient, ou contiendra, vos projets REAPER.';

  @override
  String get libraryFolder => 'Dossier';

  @override
  String get choose => 'Choisir…';

  @override
  String get noFolder => 'Aucun dossier choisi';

  @override
  String get libraryName => 'Nom';

  @override
  String get libraryMode => 'Mode';

  @override
  String get modeLocal => 'Local';

  @override
  String get modeCloud => 'Cloud';

  @override
  String get modeCollab => 'Collaboration';

  @override
  String get modesComingSoon =>
      'Les modes cloud et collaboration arrivent bientôt.';

  @override
  String get libraryLayout => 'Organisation';

  @override
  String get recommended => 'Recommandé';

  @override
  String get layoutClassic => 'Classique';

  @override
  String get layoutProjectOriented => 'Orienté projet';

  @override
  String get layoutFilm => 'Orienté film';

  @override
  String get layoutFreeTree => 'Arborescence libre';

  @override
  String get layoutFreeTreeHint =>
      'Vos propres dossiers, à n\'importe quelle profondeur.';

  @override
  String get existingLibrary =>
      'Ce dossier contient déjà une bibliothèque sans titre : vous pouvez encore changer son organisation.';

  @override
  String get layoutLocked =>
      'Cette bibliothèque contient déjà des titres : son organisation est figée. La changer demande une migration.';

  @override
  String get layoutCurrent => 'Organisation actuelle';

  @override
  String get createLibrary => 'Créer la bibliothèque';

  @override
  String get addLibrary => 'Ajouter une bibliothèque';

  @override
  String get errorUnsupportedMode =>
      'Ce dossier contient une bibliothèque cloud ou collaborative, pas encore prise en charge.';

  @override
  String get errorOverlap =>
      'Ce dossier est, contient ou se trouve dans une autre bibliothèque.';

  @override
  String get errorInvalidFile =>
      'Ce dossier contient un fichier .library.json illisible.';

  @override
  String get reaperStepHint =>
      'ReaHarvest ouvre vos projets dans REAPER et vérifie vos plugins.';

  @override
  String get reaperExecutable => 'Application';

  @override
  String get reaperResources => 'Dossier de ressources';

  @override
  String get templatesFolder => 'Modèles de projet';

  @override
  String get notFound => 'Introuvable';

  @override
  String get resetToDefault => 'Rétablir la valeur par défaut';

  @override
  String get peaksWarning =>
      'Les fichiers de crêtes (.reapeaks) sont enregistrés à côté de vos projets. Pour garder votre bibliothèque propre, activez « Store all peak caches (.reapeaks) in alternate path » dans REAPER (Preferences > General > Paths).';

  @override
  String get profile => 'Profil';

  @override
  String get libraries => 'Bibliothèques';

  @override
  String get noLibrary => 'Aucune bibliothèque pour l\'instant.';

  @override
  String get removeLibrary => 'Retirer';

  @override
  String removeLibraryTitle(String name) {
    return 'Retirer « $name » ?';
  }

  @override
  String get removeLibraryHint =>
      'La bibliothèque est seulement retirée de ReaHarvest : son dossier et ses fichiers restent intacts.';
}
