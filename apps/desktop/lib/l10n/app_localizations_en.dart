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
}
