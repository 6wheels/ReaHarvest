/// REAPER integration: launching, resource path, plugin caches, preference checks.
library;

export 'src/launcher.dart'
    show isReaperRunning, openInReaper, openProjectCommand;
export 'src/plugin_cache.dart' show PluginCache, PluginStatus;
export 'src/preferences.dart'
    show
        PeaksPreference,
        listProjectTemplates,
        loadDefaultProjectTemplate,
        loadPeaksPreference,
        parseDefaultProjectTemplate,
        parsePeaksPreference;
export 'src/reaper_paths.dart'
    show
        defaultExecutableCandidates,
        defaultResourcePath,
        detectReaperExecutable,
        parseRegDefaultValue;
export 'src/run_command.dart' show RunCommand;
