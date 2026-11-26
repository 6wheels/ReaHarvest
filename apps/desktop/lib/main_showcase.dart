// UI showcase: every real component of the app on static data, with the
// real theme. No I/O: run with
// `flutter run -d windows -t lib/main_showcase.dart`.
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:window_manager/window_manager.dart';

import 'app_window.dart';
import 'l10n/app_localizations.dart';
import 'showcase_tokens.dart';
import 'state/navigation.dart';
import 'state/providers.dart';
import 'state/reaper.dart';
import 'state/tasks.dart';
import 'theme/app_theme.dart';
import 'ui/aurora.dart';
import 'ui/kit/kit.dart';
import 'ui/known_values_editor.dart';
import 'ui/library_page.dart' show LibrarySearchField;
import 'ui/overview.dart';
import 'ui/path_row.dart';
import 'ui/progress_popup.dart';
import 'ui/status_trail.dart';
import 'ui/studio_title_bar.dart';
import 'ui/tasks_zone.dart';
import 'ui/title_card.dart';
import 'ui/to_sort/fix_dialog.dart' show Choice;
import 'ui/to_sort/to_sort_item.dart';

/// Heights of the controls bar and of the accent presets bar, width of the
/// sliders of the controls.
const _controlsHeight = 56.0;
const _presetsHeight = 40.0;
const _sliderWidth = 180.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The window frame of the application: its own title bar and buttons.
  // Shown by the runner with the first frame.
  appWindow
    ?..titleBarStyle = TitleBarStyle.hidden
    ..isWindowControlButtonsVisible = true;
  // Providers read by the overview and the card actions, served from the
  // mock data below: nothing is read from or written to the disk, and REAPER
  // is never found.
  runApp(
    ProviderScope(overrides: showcaseOverrides(), child: const UiShowcaseApp()),
  );
}

/// The providers served from the mock data, shared with the golden tests.
@visibleForTesting
List<Override> showcaseOverrides() => [
  settingsProvider.overrideWith(_ShowcaseSettings.new),
  titlesProvider.overrideWithValue(_titles),
  indexedLibrariesProvider.overrideWithValue({_library: _libraryModel}),
  pluginCacheProvider.overrideWith(
    (ref) async => PluginCache.parse(vstIni: const [], jsIni: null),
  ),
  reaperExecutableProvider.overrideWith((ref) async => null),
  tasksProvider.overrideWith(_ShowcaseTasks.new),
];

/// Ids of the sections, in display order: one golden image set per id.
@visibleForTesting
const showcaseSectionIds = [
  'title_card',
  'overview',
  'status_trail',
  'lights_progress',
  'buttons',
  'tokens',
  'tags_menus',
  'notifications',
  'foreground_popup',
  'forms',
  'to_sort',
  'chrome',
];

/// Key of the section built alone (see [UiShowcaseApp.section]).
@visibleForTesting
const showcaseSectionKey = Key('showcase-section');

/// Settings kept in memory only.
class _ShowcaseSettings extends SettingsNotifier {
  @override
  AppSettings build() =>
      AppSettings(identity: const LocalIdentity(MemberId('me'), 'Sam'));

  @override
  Future<void> persist(AppSettings settings) async {}
}

/// Tasks in every state, for the tasks zone. Cancel and "Clear finished"
/// work on them; nothing runs.
class _ShowcaseTasks extends TasksNotifier {
  @override
  List<BackgroundTask> build() => [
    BackgroundTask(
      id: 1,
      label: (l10n) => l10n.taskScan('Band'),
      state: TaskState.done,
    ),
    BackgroundTask(
      id: 2,
      label: (l10n) => l10n.taskMove('Old/Loose.rpp'),
      state: TaskState.failed,
      error: 'The target folder already exists.',
    ),
    BackgroundTask(
      id: 3,
      label: (l10n) => l10n.taskFix(2),
      state: TaskState.done,
      report: const Report({
        ReportKind.corrupted: [
          ReportItem('Slow Tide/broken.rpp', 'bad header'),
        ],
      }),
    ),
    BackgroundTask(
      id: 4,
      label: (l10n) => l10n.taskUndoFix,
      state: TaskState.cancelled,
    ),
    BackgroundTask(
      id: 5,
      label: (l10n) => l10n.taskScan('Archive'),
      state: TaskState.queued,
    ),
    BackgroundTask(
      id: 6,
      label: (l10n) => l10n.taskFix(3),
      progress: 0.42,
      step: (l10n) => l10n.taskStepFix(2, 3),
    ),
  ];
}

/// Size of a title card in the library grid (see `library_page.dart`).
const _cardSize = 264.0;

class UiShowcaseApp extends StatefulWidget {
  /// With a [section] id, only that section is built, without the controls,
  /// in the given [themeMode] and [accent]: what the golden tests draw.
  const UiShowcaseApp({
    super.key,
    this.section,
    this.themeMode = ThemeMode.dark,
    this.accent = AccentPreference.neutral,
  });

  final String? section;
  final ThemeMode themeMode;
  final AccentPreference accent;

  @override
  State<UiShowcaseApp> createState() => _UiShowcaseAppState();
}

class _UiShowcaseAppState extends State<UiShowcaseApp> {
  late ThemeMode _themeMode = widget.themeMode;
  Locale _locale = const Locale('en');
  double _progress = 0.65;
  bool _loading = true;
  bool _switch = true;
  double _slider = 0.5;
  int _segment = 1;

  /// Accent picked in the settings bar.
  late AccentPreference _accent = widget.accent;

  /// Interface size (text scale of the settings, 75 to 150 %).
  double _scale = 1;

  /// Light of the "select all" specimen: none, some, all.
  bool? _all = false;

  // Local state of the interactive specimens.
  bool _checked = true;
  bool _filterActive = true;
  final _selectedItems = {0};
  String _choice = 'b';
  String _row = 'a';
  String? _owner;
  final _levelController = TextEditingController(text: 'Sample');
  final _emptyLevelController = TextEditingController();
  final _compactController = TextEditingController();
  final _searchFocus = FocusNode();
  List<KnownValue> _knownValues = const [
    KnownValue('Sample Artist', [KnownValue('Album 1'), KnownValue('Album 2')]),
    KnownValue('Other Artist', [KnownValue('Live Sessions')]),
  ];

  @override
  void dispose() {
    _levelController.dispose();
    _emptyLevelController.dispose();
    _compactController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    // The tasks zone opens its reports over the pages.
    navigatorKey: appNavigatorKey,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(_scale)),
      child: child!,
    ),
    themeMode: _themeMode,
    theme: buildTheme(Brightness.light, accent: _accent),
    darkTheme: buildTheme(Brightness.dark, accent: _accent),
    themeAnimationDuration: Motion.medium,
    locale: _locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => widget.section != null
          ? _alone(context, widget.section!)
          : Scaffold(
              appBar: _windowBar(context),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final section in _sections(context))
                      _SectionView(section),
                  ],
                ),
              ),
            ),
    ),
  );

  /// One section alone, at its natural height, for the golden tests.
  Widget _alone(BuildContext context, String id) {
    final section = _sections(context).singleWhere((s) => s.id == id);
    assert(
      _sections(context).map((s) => s.id).join() == showcaseSectionIds.join(),
    );
    return Scaffold(
      body: OverflowBox(
        maxHeight: double.infinity,
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: showcaseSectionKey,
          child: ColoredBox(
            color: context.colors.background,
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: _SectionView(section),
            ),
          ),
        ),
      ),
    );
  }

  /// The title bar of the application above the showcase controls.
  PreferredSizeWidget _windowBar(BuildContext context) => PreferredSize(
    preferredSize: const Size.fromHeight(
      studioTitleBarHeight + _controlsHeight + _presetsHeight,
    ),
    child: Column(
      children: [
        const StudioTitleBar(location: 'UI showcase'),
        Expanded(
          child: ColoredBox(
            color: context.colors.surface,
            child: Column(
              children: [
                SizedBox(height: _controlsHeight, child: _controls(context)),
                SizedBox(height: _presetsHeight, child: _presets(context)),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// Title and controls of the showcase: loading, progress, size, language,
  /// theme.
  Widget _controls(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.m),
    child: Row(
      spacing: Space.s,
      children: [
        Expanded(
          child: Text(
            'ReaHarvest — UI showcase',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Text('LOADING', style: context.legend),
        LightSwitch(
          value: _loading,
          onChanged: (v) => setState(() => _loading = v),
        ),
        const SizedBox(width: Space.s),
        Text('PROGRESS ${(_progress * 100).round()}%', style: context.readout),
        SizedBox(
          width: _sliderWidth,
          child: Slider(
            value: _progress,
            onChanged: (v) => setState(() => _progress = v),
          ),
        ),
        Text('SIZE ${(_scale * 100).round()}%', style: context.readout),
        SizedBox(
          width: _sliderWidth,
          child: Slider(
            min: 0.75,
            max: 1.5,
            divisions: 15,
            value: _scale,
            onChanged: (v) => setState(() => _scale = v),
          ),
        ),
        TextButton(
          onPressed: () => setState(
            () => _locale = Locale(_locale.languageCode == 'en' ? 'fr' : 'en'),
          ),
          child: Text(_locale.languageCode.toUpperCase()),
        ),
        IconButton(
          tooltip: 'Light / dark',
          icon: Icon(
            _themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
          ),
          onPressed: () => setState(() {
            _themeMode = _themeMode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
          }),
        ),
      ],
    ),
  );

  /// Accent settings: one preset per accent.
  Widget _presets(BuildContext context) {
    Widget preset(String label, AccentPreference value) => TextButton(
      onPressed: () => setState(() => _accent = value),
      child: Text(label),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m),
      child: Row(
        children: [
          Text('ACCENT', style: context.legend),
          const SizedBox(width: Space.s),
          Container(
            width: IconSize.s,
            height: IconSize.s,
            decoration: BoxDecoration(
              color: context.colors.accent,
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
          ),
          const SizedBox(width: Space.s),
          preset('Neutral', AccentPreference.neutral),
          preset('Orange', AccentPreference.orange),
          preset('Yellow', AccentPreference.yellow),
          preset('Teal', AccentPreference.teal),
          preset('Blue', AccentPreference.blue),
          preset('Violet', AccentPreference.violet),
          const SizedBox(width: Space.m),
          Text('ACCENT ${_accent.name.toUpperCase()}', style: context.readout),
        ],
      ),
    );
  }

  List<_Section> _sections(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    return [
      _Section(
        'title_card',
        'Title card — states',
        'Real TitleCard at its grid size (${_cardSize.round()} px). '
            'Hover is internal to the card: move the mouse over any card.',
        [
          _Specimen(
            'Nominal — full data',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_nominal),
          ),
          _Specimen(
            'Selected (shown in the overview)',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_nominal, selected: true),
          ),
          _Specimen(
            'Hover — move the mouse here',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_done),
          ),
          _Specimen(
            'Selected + versions to adopt',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_nominal, selected: true, toAdopt: 2),
          ),
          _Specimen(
            'Processing (scan / export) — not supported',
            width: _cardSize,
            height: _cardSize,
            child: const _Gap(
              'TitleCard has no busy or progress state. '
              'Scans and fixes only show in the tasks zone at the bottom.',
            ),
          ),
          _Specimen(
            'Alert — versions to adopt',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_nominal, toAdopt: 3),
          ),
          _Specimen(
            'Alert — status off the trail',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_customStatus),
          ),
          _Specimen(
            'Error — missing files / sync — not supported',
            width: _cardSize,
            height: _cardSize,
            child: const _Gap(
              'No input for missing files, missing plugins, unknown path '
              'or sync warnings: the card only takes `toAdopt`.',
            ),
          ),
          _Specimen(
            'Minimal — no tags, versions, tempo or status',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_minimal),
          ),
          _Specimen(
            'Minimal — one version without tempo',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_bare),
          ),
          _Specimen(
            'Overflow — long name, many tags, big counts',
            width: _cardSize,
            height: _cardSize,
            child: TitleCard(_overflow, toAdopt: 128, selected: true),
          ),
          _Specimen(
            'Overflow — narrow (200 px)',
            width: 200,
            height: 200,
            child: TitleCard(_overflow, toAdopt: 128),
          ),
        ],
      ),
      _Section(
        'overview',
        'Overview',
        'Real Overview on mock providers, over cards to show the blur.',
        [
          _Specimen('Nominal', width: 960, child: _OverviewStage(_nominal.id)),
          _Specimen(
            'Alerts — missing plugin, duplicate, not adopted',
            width: 960,
            child: _OverviewStage(_alerts.id),
          ),
        ],
      ),
      _Section(
        'status_trail',
        'Status trail',
        'StatusTrail: hover a trail to reveal every label.',
        [
          for (final s in [null, ...Title.defaultStatuses])
            _Specimen('Status: ${s ?? 'none'}', child: StatusTrail(s)),
          const _Specimen(
            'Custom status (off the trail)',
            child: StatusTrail('waiting for the strings'),
          ),
          const _Specimen(
            'Large (title detail header)',
            child: StatusTrail('recording', large: true),
          ),
          _Specimen(
            'Over an aurora',
            child: SizedBox(
              height: 64,
              child: CustomPaint(
                painter: AuroraPainter(AuroraPalette.of('trail', light: light)),
                child: Padding(
                  padding: const EdgeInsets.all(Space.s + 2),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: StatusTrail('mixing', onDark: !light),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      _Section(
        'lights_progress',
        'Lights & progress',
        'Meters follow the PROGRESS slider; lights follow LOADING.',
        [
          _Specimen(
            'Meter — ${(_progress * 100).round()}%',
            child: Meter(_progress),
          ),
          _Specimen('Meter — tall', child: Meter(_progress, height: 18)),
          const _Specimen('Meter — unknown progress', child: Meter(null)),
          _Specimen(
            'Led — steady / pulse / blink',
            child: Column(
              spacing: Space.s,
              children: [
                for (final mode in LedMode.values)
                  Row(
                    spacing: Space.m,
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          mode.name.toUpperCase(),
                          style: context.legend,
                        ),
                      ),
                      for (final color in [
                        c.accent,
                        c.ledGreen,
                        c.ledAmber,
                        c.ledRed,
                      ])
                        Led(color, mode: mode),
                      Led(c.accent, lit: false),
                    ],
                  ),
              ],
            ),
          ),
          _Specimen(
            'Led — follows LOADING (pulse / steady)',
            child: Led(
              c.ledAmber,
              size: 10,
              mode: _loading ? LedMode.pulse : LedMode.steady,
            ),
          ),
          _Specimen(
            'BusyLight (shown while loading)',
            child: SizedBox(
              height: 40,
              child: _loading
                  ? const BusyLight()
                  : const Center(child: Text('Loaded')),
            ),
          ),
        ],
      ),
      _Section(
        'buttons',
        'Buttons',
        'FilledButton is the lit console key of the theme.',
        [
          _Specimen(
            'Filled (lit key) — BusyLabel follows LOADING',
            child: FilledButton(
              onPressed: () {},
              child: BusyLabel('Validate', busy: _loading),
            ),
          ),
          _Specimen(
            'Filled — with icon / disabled',
            child: Row(
              spacing: Space.s,
              children: [
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Open'),
                ),
                const FilledButton(onPressed: null, child: Text('Disabled')),
              ],
            ),
          ),
          _Specimen(
            'Outlined / Text / Icon',
            child: Row(
              spacing: Space.s,
              children: [
                OutlinedButton(onPressed: () {}, child: const Text('Choose…')),
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                IconButton(
                  onPressed: () {},
                  tooltip: 'Reset',
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
      _Section(
        'tokens',
        'Tokens',
        'Style scales and the accents of both themes side by side. '
            'Pick an accent in the bar: the matrix always shows all six.',
        [
          const _Specimen('Type scale', child: TypeScaleSpecimen()),
          const _Specimen('Alpha levels', child: AlphaSpecimen()),
          const _Specimen('Icon sizes', child: IconSizeSpecimen()),
          const _Specimen(
            'Accents — name, hex, luminance, contrast',
            width: 960,
            child: AccentMatrix(),
          ),
        ],
      ),
      _Section('tags_menus', 'Tags, legends & menus', '', [
        _Specimen(
          'Pill — status / alert tag, removable tag',
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              Pill('Mixing', color: c.accent),
              Pill('Missing plugins', color: c.ledAmber),
              Pill('Not adopted', color: c.muted),
              Pill('Corrupted', color: c.ledRed),
              Pill('Done', color: c.ledGreen),
              SizedBox(
                width: 120,
                child: Pill(
                  'A very long status that gets truncated',
                  color: c.accent,
                ),
              ),
              Pill(
                'First album',
                uppercase: false,
                deleteTooltip: 'Remove "First album"',
                onDeleted: () {},
              ),
            ],
          ),
        ),
        _Specimen(
          'Filter switch (filter bar) — click to toggle',
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              Pill(
                'Status',
                icon: Icons.flag_outlined,
                menuOpen: false,
                active: _filterActive,
                count: _filterActive ? 2 : null,
                onPressed: () => setState(() => _filterActive = !_filterActive),
              ),
              Pill('To sort', count: 14, onPressed: () {}),
              Pill('Artist', onPressed: () {}),
            ],
          ),
        ),
        _Specimen(
          'LightSwitch — on, off, disabled',
          child: Row(
            spacing: Space.m,
            children: [
              LightSwitch(
                value: _switch,
                onChanged: (v) => setState(() => _switch = v),
              ),
              const LightSwitch(value: false, onChanged: null),
              const LightSwitch(value: true, onChanged: null),
            ],
          ),
        ),
        _Specimen(
          'Slider and SegmentedButton (theme) — and Tooltip: hover',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: _slider,
                onChanged: (v) => setState(() => _slider = v),
              ),
              const Slider(value: 0.3, onChanged: null),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('System')),
                  ButtonSegment(value: 1, label: Text('Light')),
                  ButtonSegment(value: 2, label: Text('Dark')),
                  ButtonSegment(value: 3, label: Text('Off'), enabled: false),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
              ),
              const SizedBox(height: Space.s),
              const Tooltip(
                message: 'The theme of the tooltips',
                child: Text('Hover this text'),
              ),
            ],
          ),
        ),
        _Specimen(
          'DisclosureTile — report sections (error blinks)',
          child: Column(
            children: [
              for (final (level, led, open) in [
                ('Error', Led(c.ledRed, mode: LedMode.blink), true),
                ('Warning', Led(c.ledAmber), true),
                ('Skipped', Led(c.muted, lit: false), false),
                ('Done', Led(c.ledGreen), false),
              ])
                DisclosureTile(
                  initiallyExpanded: open,
                  leading: SizedBox(
                    width: IconSize.l,
                    child: Center(child: led),
                  ),
                  title: Text('$level section · 2'),
                  children: const [Text('First item'), Text('Second item')],
                ),
            ],
          ),
        ),
        const _Specimen(
          'Surface.panel — plain, raised (panel / menu)',
          child: Column(
            spacing: Space.m,
            children: [
              Surface.panel(
                child: Padding(
                  padding: EdgeInsets.all(Space.s),
                  child: Text('Plain panel'),
                ),
              ),
              Surface.panel(
                elevation: Elevation.menu,
                child: Padding(
                  padding: EdgeInsets.all(Space.s),
                  child: Text('Raised panel'),
                ),
              ),
            ],
          ),
        ),
        _Specimen(
          'ChoiceRow and CheckRow — choice among several, on / off, disabled',
          child: Column(
            children: [
              CheckRow(
                value: _switch,
                label: 'Show in the tray',
                onChanged: (v) => setState(() => _switch = v),
              ),
              ChoiceRow(
                selected: _row == 'a',
                label: 'Blank project',
                hint: 'An empty project',
                onTap: () => setState(() => _row = 'a'),
              ),
              ChoiceRow(
                selected: _row == 'b',
                label: 'From a template',
                hint: 'A project template',
                trailing: SizedBox(
                  width: 120,
                  child: Dropdown(
                    enabled: _row == 'b',
                    value: _choice,
                    options: const {'a': 'Artist', 'b': 'Album'},
                    onChanged: (v) => setState(() => _choice = v),
                  ),
                ),
                onTap: () => setState(() => _row = 'b'),
              ),
              const ChoiceRow(
                selected: false,
                label: 'Duplicate',
                hint: 'Not available',
                onTap: null,
              ),
            ],
          ),
        ),
        _Specimen(
          'PressableSurface — idle, selected, disabled (hover, press: try)',
          child: Column(
            spacing: Space.s,
            children: [
              for (final (label, onTap, selected) in [
                ('IDLE', () {}, false),
                ('SELECTED', () {}, true),
                ('DISABLED', null, false),
              ])
                PressableSurface(
                  onTap: onTap,
                  selected: selected,
                  color: c.surface,
                  side: BorderSide(color: c.border),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s),
                    child: Row(
                      children: [
                        Container(
                          width: Space.xxs,
                          height: Space.m,
                          color: selected ? c.accent : c.muted,
                        ),
                        const SizedBox(width: Space.s),
                        Text(label, style: context.legend),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const _Specimen(
          'SectionLabel / MenuLegend',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SectionLabel('Versions'), MenuLegend('Sort by')],
          ),
        ),
        _Specimen(
          'LightCheckbox — select all: none, some, all',
          child: Row(
            children: [
              LightCheckbox(
                value: _all,
                tooltip: 'Select all',
                onPressed: () => setState(
                  () => _all = switch (_all) {
                    false => null,
                    null => true,
                    true => false,
                  },
                ),
              ),
              const SizedBox(width: Space.s),
              Text(switch (_all) {
                false => 'None selected',
                null => 'Some selected',
                true => 'All selected',
              }),
            ],
          ),
        ),
        _Specimen(
          'Menu with ChoiceLight — click to open',
          child: MenuAnchor(
            menuChildren: [
              const MenuLegend('Sort by'),
              for (final (i, label) in ['Name', 'Date', 'Tempo'].indexed)
                MenuItemButton(
                  leadingIcon: ChoiceLight(checked: i == 1),
                  child: Text(label),
                ),
              MenuItemButton(
                leadingIcon: ChoiceLight(checked: _checked),
                closeOnActivate: false,
                onPressed: () => setState(() => _checked = !_checked),
                child: const Text('Show hidden'),
              ),
            ],
            builder: (context, controller, _) => OutlinedButton(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: const Text('Open menu'),
            ),
          ),
        ),
      ]),
      _Section(
        'notifications',
        'Notifications',
        'Real TasksZone on mock tasks in every state: click TASKS to unfold, '
            'Escape folds it in the app.',
        [const _Specimen('TasksZone', width: 900, child: TasksZone())],
      ),
      _Section(
        'foreground_popup',
        'Foreground task',
        'The popup of a sensitive action, its cancel confirmation, and the '
            'glass pane that covers the tasks zone while it runs.',
        [
          _Specimen(
            'Running',
            width: 420,
            child: ProgressPopup(
              BackgroundTask(
                id: 1,
                label: (l10n) => l10n.taskFix(2),
                progress: 0.5,
                step: (l10n) => l10n.taskStepCheck,
              ),
              onCancel: () {},
            ),
          ),
          _Specimen(
            'Waiting for the library',
            width: 420,
            child: ProgressPopup(
              BackgroundTask(
                id: 2,
                label: (l10n) => l10n.taskFix(1),
                state: TaskState.queued,
              ),
              onCancel: () {},
            ),
          ),
          const _Specimen(
            'Cancel confirmation',
            width: 420,
            child: CancelTaskDialog(),
          ),
          const _Specimen(
            'Glass pane over the tasks zone',
            width: 900,
            child: _LockedZone(),
          ),
        ],
      ),
      _Section(
        'forms',
        'Forms',
        'Fields, drop-downs and buttons share one height.',
        [
          _Specimen(
            'Heights side by side',
            width: 660,
            child: Row(
              spacing: Space.s,
              children: [
                const Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search_rounded, size: 16),
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Dropdown(
                    value: _choice,
                    options: const {'a': 'Artist', 'b': 'Album', 'c': 'Title'},
                    onChanged: (v) => setState(() => _choice = v),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: LevelField(
                    label: 'Artist',
                    controller: _levelController,
                    options: () => const ['Sample Artist', 'Other Artist'],
                    error: null,
                    dense: true,
                    onChanged: () {},
                  ),
                ),
                FilledButton(onPressed: () {}, child: const Text('Adopt')),
                OutlinedButton(onPressed: () {}, child: const Text('Choose…')),
                TextButton(onPressed: () {}, child: const Text('Cancel')),
              ],
            ),
          ),
          _Specimen(
            'Dropdown — with label / empty',
            width: 480,
            child: Row(
              spacing: Space.s,
              children: [
                Expanded(
                  child: Dropdown(
                    label: 'Owner',
                    value: _owner ?? 'sam',
                    options: const {'sam': 'Sam', 'alex': 'Alex'},
                    onChanged: (v) => setState(() => _owner = v),
                  ),
                ),
                Expanded(
                  child: Dropdown<String>(
                    label: 'Template',
                    value: null,
                    options: const {'empty': 'Empty project'},
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
          _Specimen(
            'FormRow + text field',
            width: 480,
            child: const FormRow(label: 'Name', child: TextField()),
          ),
          _Specimen(
            'PathRow — value / placeholder',
            width: 480,
            child: Column(
              children: [
                PathRow(
                  label: 'Library',
                  value: r'C:\Music\Projects\A very long path\to the library',
                  placeholder: 'Not set',
                  onChoose: () {},
                  onReset: () {},
                ),
                PathRow(
                  label: 'REAPER',
                  value: null,
                  placeholder: 'Not set',
                  onChoose: () {},
                ),
              ],
            ),
          ),
          _Specimen(
            'Choice (fix dialog)',
            width: 480,
            child: Choice(
              label: 'Level',
              value: _choice,
              options: const {'a': 'Artist', 'b': 'Album', 'c': 'Title'},
              onChanged: (v) => setState(() => _choice = v),
            ),
          ),
          _Specimen(
            'LevelField — autocomplete / compact (tag) / error',
            width: 480,
            child: Column(
              spacing: Space.m,
              children: [
                LevelField(
                  label: 'Artist',
                  controller: _levelController,
                  options: () => const ['Sample Artist', 'Other Artist'],
                  error: null,
                  onChanged: () {},
                ),
                SizedBox(
                  width: 160,
                  child: LevelField(
                    label: 'Add a tag',
                    controller: _compactController,
                    options: () => const ['live', 'mix'],
                    error: null,
                    compact: true,
                    onChanged: () {},
                  ),
                ),
                LevelField(
                  label: 'Album',
                  hint: 'Album name',
                  controller: _emptyLevelController,
                  options: () => const [],
                  error: 'Invalid folder name',
                  onChanged: () {},
                ),
              ],
            ),
          ),
          _Specimen(
            'KnownValuesEditor',
            width: 480,
            child: KnownValuesEditor(
              layout: Layout.classic(),
              values: _knownValues,
              used: const {'Sample Artist/Album 1'},
              onChanged: (v) => setState(() => _knownValues = v),
            ),
          ),
        ],
      ),
      _Section('to_sort', 'To sort & previews', '', [
        _Specimen(
          'To sort list — click a strip to select it',
          width: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Title too high · 3'),
              for (final (i, name) in [
                'Paper Boats',
                'Copper Sky',
                'A project folder with a really long name that must be cut',
              ].indexed)
                Item(
                  title: name,
                  subtitle: 'Sample Artist/$name',
                  details: const [
                    'Expected level: album',
                    'Proposed: _Unassigned/Album 1',
                  ],
                  selected: _selectedItems.contains(i),
                  onSelected: (on) => setState(
                    () => on ? _selectedItems.add(i) : _selectedItems.remove(i),
                  ),
                  action: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Move…'),
                  ),
                ),
              const SizedBox(height: Space.m),
              const SectionLabel('Scan failed · 1'),
              const Item(title: 'Loose project.RPP', subtitle: 'Inbox'),
            ],
          ),
        ),
      ]),
      _Section('chrome', 'Chrome', 'StudioTitleBar at a bounded width.', [
        _Specimen(
          'StudioTitleBar — location, back, search, actions',
          width: 900,
          child: StudioTitleBar(
            location: 'To sort',
            onBack: () {},
            center: SizedBox(
              width: 360,
              child: LibrarySearchField(
                focusNode: _searchFocus,
                autofocus: false,
              ),
            ),
            trailing: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ),
        const _Specimen(
          'StudioTitleBar — brand only',
          width: 900,
          child: StudioTitleBar(),
        ),
        _Specimen(
          'Aurora palettes (seeded by title id)',
          width: 480,
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final seed in ['a', 'b', 'c', 'd', 'e', 'f'])
                SizedBox(
                  width: 140,
                  height: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.xs),
                    child: CustomPaint(
                      painter: AuroraPainter(
                        AuroraPalette.of(seed, light: light),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ]),
    ];
  }
}

// --- Mock data -------------------------------------------------------------

const _library = LibraryId('showcase');

final _libraryModel = Library(
  id: _library,
  mode: LibraryMode.local,
  layout: Layout.classic(),
);

Title _title(
  String id, {
  required Map<String, String> levels,
  String? status,
  int versions = 0,
  double? tempo,
  Map<String, String> versionStatuses = const {},
}) => Title(
  id: NodeId(id),
  libraryId: _library,
  path: levels.values.join('/'),
  levels: levels,
  // The title status is derived: [status] goes to the first version.
  versionStatuses: {
    if (status != null && versions > 0) '$id-0': status,
    ...versionStatuses,
  },
  versions: [
    for (var v = 0; v < versions; v++)
      Version(
        fileName: '${levels.values.last} v${v + 1}.rpp',
        modified: DateTime(2026, 11, 12).subtract(Duration(days: v * 3)),
        size: 1,
        tempo: tempo,
        metadata: VersionMetadata(
          id: VersionId('$id-$v'),
          owner: const MemberId('me'),
          label: 'take ${v + 1}',
        ),
      ),
  ],
);

final _nominal = _title(
  'nominal',
  levels: {'artist': 'Sample Artist', 'album': 'Album 1', 'title': 'Slow Tide'},
  status: 'mixing',
  versions: 6,
  tempo: 92,
  versionStatuses: const {
    'nominal-0': 'mixing',
    'nominal-1': 'recording',
    'nominal-3': 'writing',
  },
);

final _done = _title(
  'done',
  levels: {
    'artist': 'Other Artist',
    'album': 'Album 2',
    'title': 'First Light',
  },
  status: 'done',
  versions: 3,
  tempo: 120,
);

final _customStatus = _title(
  'custom',
  levels: {
    'artist': 'Sample Artist',
    'album': 'Album 1',
    'title': 'Glass Garden',
  },
  status: 'waiting for the strings',
  versions: 2,
  tempo: 76,
);

final _minimal = _title('minimal', levels: {'title': 'Untitled'});

final _bare = _title('bare', levels: {'title': 'Sketch'}, versions: 1);

final _overflow = _title(
  'overflow',
  levels: {
    'artist': 'The Extraordinarily Long Named Collective of Sound',
    'album': 'An Album Title That Keeps Going Far Beyond Reason',
    'disc': 'Disc 2 — Bonus Material',
    'title':
        'A Remarkably Long Song Title Meant To Break Every Layout Rule '
        'We Have Ever Written (Extended Midnight Remix)',
  },
  status: 'recording',
  versions: 999,
  tempo: 174.6,
);

/// A title with every overview alert: a version using a plugin missing on
/// this machine, two versions sharing an id, one version not adopted.
final _alerts = Title(
  id: const NodeId('alerts'),
  libraryId: _library,
  path: 'Other Artist/Album 2/Copper Sky',
  levels: const {
    'artist': 'Other Artist',
    'album': 'Album 2',
    'title': 'Copper Sky',
  },
  // The title shows the most advanced status of its versions: recording.
  versionStatuses: const {
    'alerts-dup': 'recording',
    'Copper Sky rough.rpp': 'idea',
  },
  versions: [
    Version(
      fileName: 'Copper Sky drums.rpp',
      modified: DateTime(2026, 11, 14),
      size: 1,
      tempo: 104,
      metadata: const VersionMetadata(
        id: VersionId('alerts-dup'),
        owner: MemberId('me'),
        label: 'drums',
      ),
      plugins: const [
        PluginRef(
          kind: 'VST3',
          name: 'Fancy Reverb',
          identifier: 'FancyReverb.vst3',
        ),
      ],
    ),
    Version(
      fileName: 'Copper Sky drums copy.rpp',
      modified: DateTime(2026, 11, 13),
      size: 1,
      tempo: 104,
      metadata: const VersionMetadata(
        id: VersionId('alerts-dup'),
        owner: MemberId('alex'),
        label: 'drums (copy)',
      ),
    ),
    Version(
      fileName: 'Copper Sky rough.rpp',
      modified: DateTime(2026, 11, 2),
      size: 1,
    ),
  ],
);

final _titles = [_nominal, _alerts];

// --- Showcase layout -------------------------------------------------------

class _Section {
  const _Section(this.id, this.title, this.description, this.items);

  final String id;
  final String title;
  final String description;
  final List<Widget> items;
}

class _SectionView extends StatelessWidget {
  const _SectionView(this.section);

  final _Section section;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.xl + Space.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.title, style: Theme.of(context).textTheme.titleLarge),
        if (section.description.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(
            section.description,
            style: TextStyle(color: context.colors.muted, fontSize: 13),
          ),
        ],
        const Divider(height: Space.l),
        Wrap(spacing: Space.l, runSpacing: Space.l, children: section.items),
      ],
    ),
  );
}

/// One component under its label, at a bounded width (and height when
/// given, for widgets that fill their parent like the title card).
class _Specimen extends StatelessWidget {
  const _Specimen(
    this.label, {
    required this.child,
    this.width = 320,
    this.height,
  });

  final String label;
  final Widget child;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.legend.copyWith(color: context.colors.accent),
        ),
        const SizedBox(height: Space.s),
        if (height case final height?)
          SizedBox(height: height, child: child)
        else
          child,
      ],
    ),
  );
}

/// The overview of title [id] floating over a strip of cards, as in the
/// library.
class _OverviewStage extends StatelessWidget {
  const _OverviewStage(this.id);

  final NodeId id;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: overviewHeight + Space.xl,
    child: Stack(
      children: [
        Row(
          spacing: Space.m,
          children: [
            for (final t in [_nominal, _done, _customStatus, _overflow])
              SizedBox(
                width: _cardSize - 40,
                height: overviewHeight + Space.xl,
                child: TitleCard(t),
              ),
          ],
        ),
        Positioned(
          left: Space.m,
          right: Space.m,
          bottom: Space.s,
          height: overviewHeight,
          child: Overview(id),
        ),
      ],
    ),
  );
}

/// Placeholder for a state the component does not support yet.
class _Gap extends StatelessWidget {
  const _Gap(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: c.border, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.design_services_outlined, color: c.muted, size: 28),
          const SizedBox(height: Space.s),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// The tasks zone under the glass pane of a running foreground task.
class _LockedZone extends StatelessWidget {
  const _LockedZone();

  @override
  Widget build(BuildContext context) => const ClipRect(
    child: Stack(
      children: [
        TasksZone(),
        Positioned.fill(child: GlassPane(AlwaysStoppedAnimation(1))),
      ],
    ),
  );
}
