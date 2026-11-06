import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ReaHarvest'**
  String get appTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search titles, tags, versions…'**
  String get searchHint;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @emptyLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get emptyLibraryTitle;

  /// No description provided for @emptyLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Add a library in the settings to see your titles here.'**
  String get emptyLibraryHint;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No title matches “{query}”'**
  String noResults(String query);

  /// No description provided for @versionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No version} =1{1 version} other{{count} versions}}'**
  String versionCount(int count);

  /// No description provided for @bpm.
  ///
  /// In en, this message translates to:
  /// **'{bpm} BPM'**
  String bpm(int bpm);

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @statusIdea.
  ///
  /// In en, this message translates to:
  /// **'Idea'**
  String get statusIdea;

  /// No description provided for @statusWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get statusWriting;

  /// No description provided for @statusRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get statusRecording;

  /// No description provided for @statusMixing.
  ///
  /// In en, this message translates to:
  /// **'Mixing'**
  String get statusMixing;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get statusDone;

  /// No description provided for @levelArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get levelArtist;

  /// No description provided for @levelAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get levelAlbum;

  /// No description provided for @levelTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get levelTitle;

  /// No description provided for @levelProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get levelProject;

  /// No description provided for @levelChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get levelChapter;

  /// No description provided for @levelScene.
  ///
  /// In en, this message translates to:
  /// **'Scene'**
  String get levelScene;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to ReaHarvest'**
  String get welcomeTitle;

  /// No description provided for @welcomeHint.
  ///
  /// In en, this message translates to:
  /// **'Let\'s set up your first library. It only takes a minute.'**
  String get welcomeHint;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourNameHint.
  ///
  /// In en, this message translates to:
  /// **'Shown as the owner of your versions.'**
  String get yourNameHint;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String stepOf(int current, int total);

  /// No description provided for @libraryStepTitle.
  ///
  /// In en, this message translates to:
  /// **'Your first library'**
  String get libraryStepTitle;

  /// No description provided for @libraryStepHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the folder that holds, or will hold, your REAPER projects.'**
  String get libraryStepHint;

  /// No description provided for @libraryFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get libraryFolder;

  /// No description provided for @choose.
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get choose;

  /// No description provided for @noFolder.
  ///
  /// In en, this message translates to:
  /// **'No folder chosen'**
  String get noFolder;

  /// No description provided for @libraryName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get libraryName;

  /// No description provided for @libraryMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get libraryMode;

  /// No description provided for @modeLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get modeLocal;

  /// No description provided for @modeCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get modeCloud;

  /// No description provided for @modeCollab.
  ///
  /// In en, this message translates to:
  /// **'Collaboration'**
  String get modeCollab;

  /// No description provided for @modesComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Cloud and collaboration modes are coming soon.'**
  String get modesComingSoon;

  /// No description provided for @libraryLayout.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get libraryLayout;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @layoutClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get layoutClassic;

  /// No description provided for @layoutProjectOriented.
  ///
  /// In en, this message translates to:
  /// **'Project-oriented'**
  String get layoutProjectOriented;

  /// No description provided for @layoutFilm.
  ///
  /// In en, this message translates to:
  /// **'Film-oriented'**
  String get layoutFilm;

  /// No description provided for @layoutFreeTree.
  ///
  /// In en, this message translates to:
  /// **'Free tree'**
  String get layoutFreeTree;

  /// No description provided for @layoutFreeTreeHint.
  ///
  /// In en, this message translates to:
  /// **'Your own folders, at any depth.'**
  String get layoutFreeTreeHint;

  /// No description provided for @existingLibrary.
  ///
  /// In en, this message translates to:
  /// **'This folder already holds a library without titles: you can still change its organization.'**
  String get existingLibrary;

  /// No description provided for @layoutLocked.
  ///
  /// In en, this message translates to:
  /// **'This library already holds titles: its organization is fixed. Changing it requires a migration.'**
  String get layoutLocked;

  /// No description provided for @layoutCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current organization'**
  String get layoutCurrent;

  /// No description provided for @createLibrary.
  ///
  /// In en, this message translates to:
  /// **'Create library'**
  String get createLibrary;

  /// No description provided for @addLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add a library'**
  String get addLibrary;

  /// No description provided for @errorUnsupportedMode.
  ///
  /// In en, this message translates to:
  /// **'This folder holds a cloud or collaboration library, which is not supported yet.'**
  String get errorUnsupportedMode;

  /// No description provided for @errorOverlap.
  ///
  /// In en, this message translates to:
  /// **'This folder is, contains or is inside another library.'**
  String get errorOverlap;

  /// No description provided for @errorInvalidFile.
  ///
  /// In en, this message translates to:
  /// **'This folder holds an unreadable _library.json file.'**
  String get errorInvalidFile;

  /// No description provided for @reaperStepHint.
  ///
  /// In en, this message translates to:
  /// **'ReaHarvest opens your projects in REAPER and checks your plugins.'**
  String get reaperStepHint;

  /// No description provided for @reaperExecutable.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get reaperExecutable;

  /// No description provided for @reaperResources.
  ///
  /// In en, this message translates to:
  /// **'Resource folder'**
  String get reaperResources;

  /// No description provided for @templatesFolder.
  ///
  /// In en, this message translates to:
  /// **'Project templates'**
  String get templatesFolder;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFound;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// No description provided for @peaksWarning.
  ///
  /// In en, this message translates to:
  /// **'Peak files (.reapeaks) are saved next to your projects. To keep your library clean, enable “Store all peak caches (.reapeaks) in alternate path” in REAPER (Preferences > General > Paths).'**
  String get peaksWarning;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @libraries.
  ///
  /// In en, this message translates to:
  /// **'Libraries'**
  String get libraries;

  /// No description provided for @noLibrary.
  ///
  /// In en, this message translates to:
  /// **'No library yet.'**
  String get noLibrary;

  /// No description provided for @removeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLibrary;

  /// No description provided for @removeLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}”?'**
  String removeLibraryTitle(String name);

  /// No description provided for @removeLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'The library is only removed from ReaHarvest: its folder and files are left untouched.'**
  String get removeLibraryHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
