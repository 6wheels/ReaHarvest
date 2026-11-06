// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ReaHarvest';

  @override
  String get searchHint => 'Search titles, tags, versions…';

  @override
  String get settings => 'Settings';

  @override
  String get close => 'Close';

  @override
  String get emptyLibraryTitle => 'Your library is empty';

  @override
  String get emptyLibraryHint =>
      'Add a library in the settings to see your titles here.';

  @override
  String noResults(String query) {
    return 'No title matches “$query”';
  }

  @override
  String versionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versions',
      one: '1 version',
      zero: 'No version',
    );
    return '$_temp0';
  }

  @override
  String bpm(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get textSize => 'Text size';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get statusIdea => 'Idea';

  @override
  String get statusWriting => 'Writing';

  @override
  String get statusRecording => 'Recording';

  @override
  String get statusMixing => 'Mixing';

  @override
  String get statusDone => 'Done';

  @override
  String get levelArtist => 'Artist';

  @override
  String get levelAlbum => 'Album';

  @override
  String get levelTitle => 'Title';

  @override
  String get levelProject => 'Project';

  @override
  String get levelChapter => 'Chapter';

  @override
  String get levelScene => 'Scene';

  @override
  String get welcomeTitle => 'Welcome to ReaHarvest';

  @override
  String get welcomeHint =>
      'Let\'s set up your first library. It only takes a minute.';

  @override
  String get yourName => 'Your name';

  @override
  String get yourNameHint => 'Shown as the owner of your versions.';

  @override
  String get later => 'Later';

  @override
  String get continueAction => 'Continue';

  @override
  String get back => 'Back';

  @override
  String get finish => 'Finish';

  @override
  String get cancel => 'Cancel';

  @override
  String stepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get libraryStepTitle => 'Your first library';

  @override
  String get libraryStepHint =>
      'Choose the folder that holds, or will hold, your REAPER projects.';

  @override
  String get libraryFolder => 'Folder';

  @override
  String get choose => 'Choose…';

  @override
  String get noFolder => 'No folder chosen';

  @override
  String get libraryName => 'Name';

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
      'Cloud and collaboration modes are coming soon.';

  @override
  String get libraryLayout => 'Organization';

  @override
  String get recommended => 'Recommended';

  @override
  String get layoutClassic => 'Classic';

  @override
  String get layoutProjectOriented => 'Project-oriented';

  @override
  String get layoutFilm => 'Film-oriented';

  @override
  String get layoutFreeTree => 'Free tree';

  @override
  String get layoutFreeTreeHint => 'Your own folders, at any depth.';

  @override
  String get existingLibrary =>
      'This folder already holds a library without titles: you can still change its organization.';

  @override
  String get layoutLocked =>
      'This library already holds titles: its organization is fixed. Changing it requires a migration.';

  @override
  String get layoutCurrent => 'Current organization';

  @override
  String get createLibrary => 'Create library';

  @override
  String get addLibrary => 'Add a library';

  @override
  String get errorUnsupportedMode =>
      'This folder holds a cloud or collaboration library, which is not supported yet.';

  @override
  String get errorOverlap =>
      'This folder is, contains or is inside another library.';

  @override
  String get errorInvalidFile =>
      'This folder holds an unreadable _library.json file.';

  @override
  String get reaperStepHint =>
      'ReaHarvest opens your projects in REAPER and checks your plugins.';

  @override
  String get reaperExecutable => 'Application';

  @override
  String get reaperResources => 'Resource folder';

  @override
  String get templatesFolder => 'Project templates';

  @override
  String get notFound => 'Not found';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get peaksWarning =>
      'Peak files (.reapeaks) are saved next to your projects. To keep your library clean, enable “Store all peak caches (.reapeaks) in alternate path” in REAPER (Preferences > General > Paths).';

  @override
  String get profile => 'Profile';

  @override
  String get libraries => 'Libraries';

  @override
  String get noLibrary => 'No library yet.';

  @override
  String get removeLibrary => 'Remove';

  @override
  String removeLibraryTitle(String name) {
    return 'Remove “$name”?';
  }

  @override
  String get removeLibraryHint =>
      'The library is only removed from ReaHarvest: its folder and files are left untouched.';
}
