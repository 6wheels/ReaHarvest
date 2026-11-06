import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';

/// Local member identity, created on first launch and used in all modes as
/// version owner (SPEC §5.1).
final class LocalIdentity {
  const LocalIdentity(this.memberId, this.displayName);

  final MemberId memberId;
  final String displayName;

  LocalIdentity withDisplayName(String name) => LocalIdentity(memberId, name);

  Map<String, Object?> toJson() => {
    'memberId': memberId,
    'displayName': displayName,
  };

  static LocalIdentity fromJson(Map<String, Object?> json) => LocalIdentity(
    MemberId(json['memberId'] as String),
    json['displayName'] as String,
  );
}

/// A library configured on this machine (SPEC §5.1). Mode and layout live in
/// the library's `_library.json`.
final class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.displayName,
    required this.workspaceRoot,
    this.repositoryRoot,
    this.templatesFolder,
  });

  final LibraryId id;
  final String displayName;
  final String workspaceRoot;

  /// Repository root (cloud and collab modes only).
  final String? repositoryRoot;

  /// Templates folder specific to this library.
  final String? templatesFolder;

  /// Folder holding `_library.json`.
  String get libraryRoot => repositoryRoot ?? workspaceRoot;

  List<String> get roots => [workspaceRoot, ?repositoryRoot];

  Map<String, Object?> toJson() => {
    'libraryId': id,
    'displayName': displayName,
    'workspaceRoot': workspaceRoot,
    'repositoryRoot': ?repositoryRoot,
    'templatesFolder': ?templatesFolder,
  };

  static LibraryEntry fromJson(Map<String, Object?> json) => LibraryEntry(
    id: LibraryId(json['libraryId'] as String),
    displayName: json['displayName'] as String,
    workspaceRoot: json['workspaceRoot'] as String,
    repositoryRoot: json['repositoryRoot'] as String?,
    templatesFolder: json['templatesFolder'] as String?,
  );
}

/// Light, dark or system theme (SPEC §7.1).
enum ThemePreference { system, light, dark }

/// Application settings (SPEC §5.1). Null paths mean "use the default".
final class AppSettings {
  AppSettings({
    required this.identity,
    List<LibraryEntry> libraries = const [],
    this.reaperExecutable,
    this.reaperResources,
    this.templatesFolder,
    this.theme = ThemePreference.system,
    this.textScale = 1.0,
    this.language = systemLanguage,
  }) : libraries = List.unmodifiable(libraries);

  /// [language] value meaning "follow the system language".
  static const systemLanguage = 'system';

  static const schemaVersion = 1;

  final LocalIdentity identity;
  final List<LibraryEntry> libraries;
  final String? reaperExecutable;
  final String? reaperResources;

  /// Project templates folder (default: `ProjectTemplates` in the REAPER
  /// resource folder).
  final String? templatesFolder;

  final ThemePreference theme;

  /// Font size factor (1.0 = default).
  final double textScale;

  /// UI language code (e.g. `en`), or [systemLanguage].
  final String language;

  /// Copy with the given values. Paths are kept when omitted and reset to
  /// the default when passed as null.
  AppSettings copyWith({
    LocalIdentity? identity,
    List<LibraryEntry>? libraries,
    Object? reaperExecutable = _keep,
    Object? reaperResources = _keep,
    Object? templatesFolder = _keep,
    ThemePreference? theme,
    double? textScale,
    String? language,
  }) => AppSettings(
    identity: identity ?? this.identity,
    libraries: libraries ?? this.libraries,
    reaperExecutable: _path(reaperExecutable, this.reaperExecutable),
    reaperResources: _path(reaperResources, this.reaperResources),
    templatesFolder: _path(templatesFolder, this.templatesFolder),
    theme: theme ?? this.theme,
    textScale: textScale ?? this.textScale,
    language: language ?? this.language,
  );

  static const _keep = Object();

  static String? _path(Object? value, String? current) =>
      identical(value, _keep) ? current : value as String?;

  /// Adds [entry]. Throws [ArgumentError] if the id is already configured or
  /// if one of its folders is, contains or is inside a folder of another
  /// library (SPEC §3.0).
  AppSettings addLibrary(LibraryEntry entry) {
    if (libraries.any((l) => l.id == entry.id)) {
      throw ArgumentError('Library ${entry.id} is already configured');
    }
    for (final other in libraries) {
      for (final a in entry.roots) {
        for (final b in other.roots) {
          if (p.equals(a, b) || p.isWithin(a, b) || p.isWithin(b, a)) {
            throw ArgumentError(
              'Folder $a overlaps library "${other.displayName}" ($b)',
            );
          }
        }
      }
    }
    return copyWith(libraries: [...libraries, entry]);
  }

  AppSettings removeLibrary(LibraryId id) =>
      copyWith(libraries: [...libraries.where((l) => l.id != id)]);

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'identity': identity.toJson(),
    'libraries': [for (final l in libraries) l.toJson()],
    'reaperExecutable': ?reaperExecutable,
    'reaperResources': ?reaperResources,
    'templatesFolder': ?templatesFolder,
    'theme': theme.name,
    'textScale': textScale,
    'language': language,
  };

  static AppSettings fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported settings schema: $version');
    }
    return AppSettings(
      identity: LocalIdentity.fromJson((json['identity'] as Map).cast()),
      libraries: [
        for (final l in json['libraries'] as List)
          LibraryEntry.fromJson((l as Map).cast()),
      ],
      reaperExecutable: json['reaperExecutable'] as String?,
      reaperResources: json['reaperResources'] as String?,
      templatesFolder: json['templatesFolder'] as String?,
      theme: ThemePreference.values.asNameMap()[json['theme']] ??
          ThemePreference.system,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      language: json['language'] as String? ?? systemLanguage,
    );
  }
}

/// Persists [AppSettings] as JSON in [path] (app support folder, provided by
/// the app).
final class SettingsFile {
  const SettingsFile(this.path);

  final String path;

  /// Loads the settings. On first launch (no file), creates them with a new
  /// local identity named after the OS user, and saves them.
  Future<AppSettings> load() async {
    final file = File(path);
    if (await file.exists()) {
      return AppSettings.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast(),
      );
    }
    final settings = AppSettings(
      identity: LocalIdentity(MemberId.generate(), _osUserName()),
    );
    await save(settings);
    return settings;
  }

  /// Saves [settings] atomically (temporary file, then rename).
  Future<void> save(AppSettings settings) async {
    final text = const JsonEncoder.withIndent('  ').convert(settings.toJson());
    await File(path).parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString('$text\n', flush: true);
    await tmp.rename(path);
  }

  static String _osUserName() {
    final env = Platform.environment;
    final name = env['USERNAME'] ?? env['USER'] ?? '';
    return name.isEmpty ? 'Me' : name;
  }
}
