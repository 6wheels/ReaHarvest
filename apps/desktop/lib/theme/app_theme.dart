import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:reaharvest_library/reaharvest_library.dart'
    show AccentPreference;

import 'light_slider.dart';

/// Spacing scale (logical pixels), by increasing value: [xxs] 2, [xs] 4,
/// [sm] 6, [s] 8, [md] 10, [ml] 12, [m] 16, [l] 24, [xl] 32.
abstract final class Space {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 6.0;
  static const s = 8.0;
  static const md = 10.0;
  static const ml = 12.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
}

/// Hardware-like corner radii: modules and controls are nearly square.
abstract final class Radii {
  static const xs = 2.0;
  static const s = 4.0;
  static const m = 6.0;
}

/// Motion: durations and curves shared by every animation.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 600);

  /// Entrance of the cards of a list, one after the other.
  static const cascade = Duration(milliseconds: 420);

  /// Delay between two cards of the cascade.
  static const stagger = Duration(milliseconds: 30);

  /// Delay before a tooltip of the title bar shows.
  static const tooltip = Duration(milliseconds: 1500);
  static const curve = Curves.easeOutCubic;
}

/// Sizes of the controls and of the popups (logical pixels).
abstract final class Sizes {
  /// Hairline: dividers.
  static const hairline = 1.0;

  /// Bar marking a selected row.
  static const bar = 2.0;

  /// Height of a filter pill and of its segmented bar, of a segment.
  static const control = 26.0;
  static const segment = 20.0;

  /// Height of a field or a button, of a small button, of a heading row.
  static const field = 32.0;
  static const mini = 22.0;
  static const row = 30.0;

  /// Cover of a title in its header.
  static const avatar = 72.0;

  /// Width of a window button.
  static const windowButton = 44.0;
}

/// Blur of the glows and of the shadows, and the offset of a drop shadow.
abstract final class Blur {
  static const s = 6.0;
  static const m = 12.0;
  static const l = 24.0;
  static const dropOffset = Offset(0, 6);
}

/// Elevation of a menu and of a dialog.
abstract final class Elevation {
  static const menu = 6.0;
  static const dialog = 24.0;
}

/// Line heights: tight for a name over an image, normal for a label, loose
/// for a paragraph.
abstract final class Leading {
  static const tight = 1.2;
  static const normal = 1.3;
  static const loose = 1.4;
}

/// Letter spacing of the capitals: the legend and the wider heading.
abstract final class Tracking {
  static const legend = 1.1;
  static const wide = 1.2;
}

/// Alpha levels: every translucent tint, border or shade of the interface
/// takes one of them.
abstract final class Alpha {
  /// Fill of a selected row or chip.
  static const faint = 0.08;

  /// Fill of a lit control, glow.
  static const tint = 0.14;

  /// Light hairline, light shade.
  static const soft = 0.25;

  /// Border of a selected item, dimmed text.
  static const medium = 0.45;

  /// Dimmed icon, strong border.
  static const strong = 0.65;

  /// Nearly opaque shade.
  static const dense = 0.85;
}

/// Icon sizes (logical pixels).
abstract final class IconSize {
  static const xs = 12.0;
  static const s = 14.0;
  static const m = 16.0;
  static const l = 18.0;
  static const xl = 20.0;

  /// Illustration of an empty list.
  static const hero = 48.0;

  /// Side of a square icon action.
  static const action = 28.0;

  /// Status lights.
  static const ledS = 6.0;
  static const ledM = 8.0;
  static const ledL = 10.0;
}

/// Font weights.
abstract final class Weights {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
}

/// Fixed tones, for what is drawn over an image (the aurora of a title).
abstract final class Tone {
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  /// Shade at the bottom of the aurora, behind the name of a title, on the
  /// dark and on the light theme.
  static const auroraShadeDark = Color(0xB0000000);
  static const auroraShadeLight = Color(0x99FFFFFF);
}

/// Type faces: Inter for running text and names, JetBrains Mono for the
/// labels and readouts of the console.
abstract final class Fonts {
  static const text = 'Inter';
  static const mono = 'JetBrainsMono';
}

/// Separator of label parts, like on a console legend (`STATUS // MIX`).
const labelSeparator = ' // ';

/// Design tokens of the application, available through
/// `Theme.of(context).extension<AppColors>()` (see [AppColorsX]).
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.scrim,
    required this.ledAmber,
    required this.ledGreen,
    required this.ledRed,
  });

  /// Chassis, behind the modules.
  final Color background;

  /// Modules and bars.
  final Color surface;

  /// Controls set in a module (fields, chips, tiles).
  final Color raised;

  /// Hairlines.
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;

  /// Tint over blurred content behind popups.
  final Color scrim;

  /// Status lights: in progress, passed or done, failed.
  final Color ledAmber;
  final Color ledGreen;
  final Color ledRed;

  static const dark = AppColors(
    background: Color(0xFF0E1013),
    surface: Color(0xFF16191E),
    raised: Color(0xFF1F232A),
    border: Color(0xFF2A2F38),
    text: Color(0xFFE8EAEE),
    muted: Color(0xFF7D8594),
    accent: Color(0xFF7FE0C5),
    scrim: Color(0xFF05060A),
    ledAmber: Color(0xFFFF9F1C),
    ledGreen: Color(0xFF3DD68C),
    ledRed: Color(0xFFE5484D),
  );

  static const light = AppColors(
    background: Color(0xFFE9E8E4),
    surface: Color(0xFFF7F6F3),
    raised: Color(0xFFFFFFFF),
    border: Color(0xFFD3D1CA),
    text: Color(0xFF0F1013),
    muted: Color(0xFF4F535C),
    accent: Color(0xFF177E65),
    scrim: Color(0xFFE9E7E1),
    ledAmber: Color(0xFFE07B00),
    ledGreen: Color(0xFF1E9E5E),
    ledRed: Color(0xFFD13438),
  );

  @override
  AppColors copyWith({Color? accent}) => AppColors(
    background: background,
    surface: surface,
    raised: raised,
    border: border,
    text: text,
    muted: muted,
    accent: accent ?? this.accent,
    scrim: scrim,
    ledAmber: ledAmber,
    ledGreen: ledGreen,
    ledRed: ledRed,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      border: mix(border, other.border),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      scrim: mix(scrim, other.scrim),
      ledAmber: mix(ledAmber, other.ledAmber),
      ledGreen: mix(ledGreen, other.ledGreen),
      ledRed: mix(ledRed, other.ledRed),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;

  /// Text styles of the interface.
  AppText get type => Theme.of(this).extension<AppText>()!;

  /// Console legend: small mono capitals, widely spaced.
  TextStyle get legend => type.legend;

  /// Readout: mono figures (tempo, counts, dates, durations).
  TextStyle get readout => type.readout;
}

/// Text styles of the application: a scale of six sizes for running text,
/// and the mono styles of the console.
@immutable
final class AppText extends ThemeExtension<AppText> {
  const AppText({
    required this.micro,
    required this.small,
    required this.caption,
    required this.body,
    required this.item,
    required this.title,
    required this.legend,
    required this.legendSmall,
    required this.readout,
    required this.readoutSmall,
  });

  /// Styles over the colors [c].
  factory AppText.of(AppColors c) {
    TextStyle text(double size, [FontWeight? weight]) => TextStyle(
      fontFamily: Fonts.text,
      fontSize: size,
      fontWeight: weight,
      color: c.text,
    );
    TextStyle legend(double size) => TextStyle(
      fontFamily: Fonts.mono,
      fontSize: size,
      fontWeight: Weights.bold,
      letterSpacing: Tracking.legend,
      height: Leading.normal,
      color: c.muted,
    );
    TextStyle readout(double size) => TextStyle(
      fontFamily: Fonts.mono,
      fontSize: size,
      fontWeight: Weights.medium,
      height: Leading.normal,
      color: c.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return AppText(
      micro: text(9.5),
      small: text(11),
      caption: text(12),
      body: text(13),
      item: text(13.5, Weights.semibold),
      title: text(20, Weights.medium),
      legend: legend(10.5),
      legendSmall: legend(9.5),
      readout: readout(11.5),
      readoutSmall: readout(11),
    );
  }

  /// Weight or slant only, for a span inheriting the rest.
  static const semibold = TextStyle(fontWeight: Weights.semibold);
  static const italic = TextStyle(fontStyle: FontStyle.italic);

  /// Color only, for a span inheriting the rest.
  static TextStyle color(Color color) => TextStyle(color: color);

  final TextStyle micro;
  final TextStyle small;
  final TextStyle caption;
  final TextStyle body;

  /// Name of a row of a list.
  final TextStyle item;
  final TextStyle title;

  /// Console legend: small mono capitals, widely spaced. Callers upper-case
  /// the text themselves.
  final TextStyle legend;
  final TextStyle legendSmall;

  /// Mono figures (tempo, counts, dates, durations).
  final TextStyle readout;
  final TextStyle readoutSmall;

  @override
  AppText copyWith({
    TextStyle? micro,
    TextStyle? small,
    TextStyle? caption,
    TextStyle? body,
    TextStyle? item,
    TextStyle? title,
    TextStyle? legend,
    TextStyle? legendSmall,
    TextStyle? readout,
    TextStyle? readoutSmall,
  }) => AppText(
    micro: micro ?? this.micro,
    small: small ?? this.small,
    caption: caption ?? this.caption,
    body: body ?? this.body,
    item: item ?? this.item,
    title: title ?? this.title,
    legend: legend ?? this.legend,
    legendSmall: legendSmall ?? this.legendSmall,
    readout: readout ?? this.readout,
    readoutSmall: readoutSmall ?? this.readoutSmall,
  );

  @override
  AppText lerp(AppText? other, double t) {
    if (other == null) return this;
    TextStyle mix(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppText(
      micro: mix(micro, other.micro),
      small: mix(small, other.small),
      caption: mix(caption, other.caption),
      body: mix(body, other.body),
      item: mix(item, other.item),
      title: mix(title, other.title),
      legend: mix(legend, other.legend),
      legendSmall: mix(legendSmall, other.legendSmall),
      readout: mix(readout, other.readout),
      readoutSmall: mix(readoutSmall, other.readoutSmall),
    );
  }
}

/// Accent colors: one value tuned for each theme. The neutral accent is
/// near white on the dark theme and near black on the light one, like the
/// keys of a console. The others are soft and warm, like the LEDs of a
/// mixing desk.
abstract final class Accents {
  static const _dark = {
    AccentPreference.neutral: Color(0xFFF0F0F0),
    AccentPreference.orange: Color(0xFFE1AF88),
    AccentPreference.yellow: Color(0xFFE2C984),
    AccentPreference.teal: Color(0xFF7FE0C5),
    AccentPreference.blue: Color(0xFF81C4E2),
    AccentPreference.violet: Color(0xFFC0A9DE),
  };
  static const _light = {
    AccentPreference.neutral: Color(0xFF1F1F1F),
    AccentPreference.orange: Color(0xFF71411C),
    AccentPreference.yellow: Color(0xFF755D1B),
    AccentPreference.teal: Color(0xFF177E65),
    AccentPreference.blue: Color(0xFF1B5976),
    AccentPreference.violet: Color(0xFF392158),
  };

  /// Accent [preference] on the [brightness] theme.
  static Color of(AccentPreference preference, Brightness brightness) =>
      (brightness == Brightness.dark ? _dark : _light)[preference]!;
}

/// Width of the snack bars.
const _snackbarWidth = 520.0;

/// Tooltip: size of its text, vertical padding, delay before it shows.
const _tooltipFontSize = 11.5;
const _tooltipPaddingV = 3.0;
const _tooltipDelay = Duration(milliseconds: 450);

/// Thickness of the scrollbars and height of the track of a slider.
const _scrollbarThickness = 6.0;
const _sliderTrack = 2.0;

/// Material theme built on the design tokens. Material is only the
/// foundation: no splash, flat surfaces, hairlines, nearly square corners.
/// The accent is [accent] (default: neutral).
///
/// The kit is everything under `lib/ui/kit/`. Outside the kit, only these
/// Material widgets may be used, the ones styled here: `MaterialApp`,
/// `Scaffold`, `Dialog`, `AlertDialog`, `Card`, `Divider`, `VerticalDivider`,
/// `SnackBar`, `Tooltip`, `Scrollbar`, `Slider`, `SegmentedButton`, `Theme`,
/// `TextField`, `SelectableText`, `MenuAnchor` with `MenuItemButton` and
/// `SubmenuButton`,
/// `FilledButton`, `OutlinedButton`, `TextButton`, `IconButton`,
/// `LinearProgressIndicator`, `CircularProgressIndicator`, and `LicensePage`
/// with the `MaterialPageRoute` opening it (Flutter's own page of the
/// licenses). Anything else, `Material` and
/// `InkWell` included, is a component of the kit.
ThemeData buildTheme(
  Brightness brightness, {
  AccentPreference accent = AccentPreference.neutral,
}) {
  final dark = brightness == Brightness.dark;
  final tokens = dark ? AppColors.dark : AppColors.light;
  final c = tokens.copyWith(accent: Accents.of(accent, brightness));
  // Labels on a solid accent: a deep shade of the accent on dark.
  final onAccent = dark
      ? Color.lerp(c.accent, Colors.black, 0.88)!
      : Colors.white;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: onAccent,
    secondary: c.accent,
    onSecondary: onAccent,
    error: c.ledRed,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    outline: c.border,
    outlineVariant: c.border,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.raised,
    surfaceContainerHighest: c.raised,
    secondaryContainer: c.accent.withValues(alpha: 0.16),
    onSecondaryContainer: c.text,
    inverseSurface: c.raised,
    onInverseSurface: c.text,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: Fonts.text,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.surface,
    splashFactory: NoSplash.splashFactory,
    hoverColor: c.text.withValues(alpha: 0.05),
    focusColor: c.accent.withValues(alpha: 0.14),
    highlightColor: Colors.transparent,
    extensions: [c, AppText.of(c)],
  );
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);
  // The squarer corners of the keys: buttons, fields and segments share them.
  final square = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.xs),
  );
  final hairline = BorderSide(color: c.border);
  final headlineSmall = text.headlineSmall?.copyWith(
    fontWeight: Weights.semibold,
    letterSpacing: -0.4,
  );
  final titleLarge = text.titleLarge?.copyWith(
    fontWeight: Weights.semibold,
    letterSpacing: -0.3,
  );
  final buttonText = const TextStyle(
    fontFamily: Fonts.text,
    fontSize: 13,
    fontWeight: Weights.semibold,
    letterSpacing: 0.1,
  );
  bool lit(Set<WidgetState> states) =>
      states.contains(WidgetState.hovered) ||
      states.contains(WidgetState.pressed) ||
      states.contains(WidgetState.focused);
  // Shared hover of the secondary buttons: the label brightens and a faint
  // fill appears.
  final litOnHover = WidgetStateProperty.resolveWith<Color>(
    (states) => states.contains(WidgetState.disabled)
        ? c.muted.withValues(alpha: 0.45)
        : lit(states)
        ? c.text
        : c.muted,
  );
  final hoverFill = WidgetStateProperty.resolveWith<Color>(
    (states) => !states.contains(WidgetState.disabled) && lit(states)
        ? c.text.withValues(
            // Stronger on the light theme, where a faint fill hardly shows.
            alpha:
                (states.contains(WidgetState.pressed) ? 0.10 : 0.06) *
                (dark ? 1 : 1.8),
          )
        : Colors.transparent,
  );
  final mainKey = _Key(c, c.accent, dark: dark, main: true);
  final otherKey = _Key(
    c,
    Color.lerp(c.background, c.accent, dark ? 0.6 : 0.5)!,
    dark: dark,
    main: false,
  );
  final menuShape = WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.s),
      side: hairline,
    ),
  );
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: Weights.bold,
        letterSpacing: -0.6,
      ),
      headlineSmall: headlineSmall,
      titleLarge: titleLarge,
      titleMedium: text.titleMedium?.copyWith(
        fontWeight: Weights.semibold,
        letterSpacing: -0.2,
      ),
      // Also the text of the fields: as large as the button labels.
      bodyLarge: text.bodyLarge?.copyWith(
        fontSize: 13,
        height: Leading.normal,
        letterSpacing: 0,
      ),
      labelLarge: text.labelLarge?.copyWith(fontWeight: Weights.medium),
      labelSmall: text.labelSmall?.copyWith(
        fontFamily: Fonts.mono,
        fontWeight: Weights.bold,
        letterSpacing: 1.0,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        side: hairline,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.m),
        side: hairline,
      ),
      // A size above the title of a version.
      titleTextStyle: headlineSmall,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.raised,
      contentTextStyle: TextStyle(color: c.text, fontSize: 13),
      actionTextColor: c.accent,
      elevation: 0,
      width: _snackbarWidth,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        side: hairline,
      ),
    ),
    // Actions: console keys with a backlit legend (SSL style), flat, in
    // the accent; the less important ones (outlined, icon) in a tone
    // between the background and the accent.
    filledButtonTheme: FilledButtonThemeData(
      style: mainKey.style(
        buttonText,
        minimumSize: const Size(64, Sizes.field),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: otherKey.style(
        buttonText,
        minimumSize: const Size(64, Sizes.field),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
      ),
    ),
    // Cancel: discreet, lit only by the hover.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(square),
        textStyle: WidgetStatePropertyAll(buttonText),
        foregroundColor: litOnHover,
        backgroundColor: hoverFill,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    // Small square actions (28): a glyph glowing on hover.
    iconButtonTheme: IconButtonThemeData(
      style: _glowStyle(c).copyWith(
        shape: WidgetStatePropertyAll(square),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        fixedSize: const WidgetStatePropertyAll(Size.square(IconSize.action)),
        iconSize: const WidgetStatePropertyAll(IconSize.m),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // A desktop tool: the plain pointer, no hand.
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(Elevation.menu),
        shape: menuShape,
        padding: const WidgetStatePropertyAll(EdgeInsets.all(Space.xs)),
      ),
    ),
    // Menu entries: compact rows lit with the accent on hover.
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(160, 30)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: Fonts.text,
            fontSize: 13,
            fontWeight: Weights.medium,
          ),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? c.muted : c.text,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? c.accent
              : c.muted,
        ),
        iconSize: const WidgetStatePropertyAll(IconSize.m),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? c.accent.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        side: hairline,
      ),
    ),
    // Fields as high as the buttons (32).
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.raised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 11.5,
      ),
      hintStyle: TextStyle(color: c.muted, fontSize: 13),
      labelStyle: TextStyle(color: c.muted, fontSize: 13),
      floatingLabelStyle: TextStyle(color: c.muted, fontSize: 12),
      helperStyle: TextStyle(color: c.muted, fontSize: 11.5),
      errorStyle: TextStyle(color: c.ledRed, fontSize: 11.5),
      prefixIconConstraints: const BoxConstraints(
        minWidth: Sizes.field,
        minHeight: 0,
      ),
      suffixIconConstraints: const BoxConstraints(
        minWidth: Sizes.field,
        minHeight: 0,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
        borderSide: hairline,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
        borderSide: hairline,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
        borderSide: BorderSide(color: c.accent.withValues(alpha: 0.75)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
    ),
    iconTheme: IconThemeData(color: c.muted, size: IconSize.l),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: Alpha.soft),
      selectionHandleColor: c.accent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s,
        vertical: _tooltipPaddingV,
      ),
      textStyle: TextStyle(
        fontFamily: Fonts.text,
        fontSize: _tooltipFontSize,
        fontWeight: Weights.medium,
        height: Leading.normal,
        color: c.text,
      ),
      waitDuration: _tooltipDelay,
    ),
    // Always shown: where the list stands is always visible.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      thickness: const WidgetStatePropertyAll(_scrollbarThickness),
      radius: const Radius.circular(Radii.xs),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? c.muted.withValues(alpha: 0.65)
            : c.border,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      // The selected segment differs by its fill, a brighter and bolder
      // label: never by the hue alone. The frame is one hairline: Flutter
      // resolves it once for the whole group.
      style: ButtonStyle(
        side: WidgetStatePropertyAll(hairline),
        shape: WidgetStatePropertyAll(square),
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.accent.withValues(alpha: Alpha.tint)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? c.muted.withValues(alpha: Alpha.medium)
              : states.contains(WidgetState.selected) || lit(states)
              ? c.text
              : c.muted,
        ),
        textStyle: WidgetStateProperty.resolveWith(
          (states) => buttonText.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? Weights.bold
                : Weights.medium,
          ),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.border,
    ),
    // A thin flat fader track and a thumb lit like a ChoiceLight.
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.border,
      disabledActiveTrackColor: c.muted,
      disabledInactiveTrackColor: c.border,
      trackHeight: _sliderTrack,
      // Room under and over the track, and half a thumb at each end: a
      // slider never touches its neighbors, nor does its thumb overflow.
      padding: const EdgeInsets.symmetric(
        vertical: Space.s,
        horizontal: Space.s,
      ),
      trackShape: const RectangularSliderTrackShape(),
      thumbShape: LightThumbShape(
        accent: c.accent,
        active: c.text,
        off: c.muted,
        background: c.background,
      ),
      overlayShape: const LightHoverShape(),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      valueIndicatorColor: c.raised,
      valueIndicatorTextStyle: AppText.of(c).readout.copyWith(color: c.text),
    ),
  );
}

/// Style of the light actions (icon buttons, small text actions): no cap,
/// the label lit in the accent with a glow on hover, flashing on a click.
/// [ink] is the color at rest (muted by default), [lit] the color on hover
/// (the accent by default).
ButtonStyle glowButtonStyle(BuildContext context, {Color? ink, Color? lit}) =>
    _glowStyle(context.colors, ink: ink, lit: lit);

ButtonStyle _glowStyle(AppColors c, {Color? ink, Color? lit}) {
  final color = WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? (ink ?? c.muted).withValues(alpha: 0.45)
        : states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)
        ? lit ?? c.accent
        : ink ?? c.muted,
  );
  return ButtonStyle(
    foregroundColor: color,
    iconColor: color,
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: const WidgetStatePropertyAll(BorderSide.none),
    elevation: const WidgetStatePropertyAll(0),
    backgroundBuilder: (context, states, child) =>
        _Glow(states: states, child: child),
  );
}

/// Style of the window close button: a muted glyph at rest, a red console
/// key with a glyph glowing like a LED on hover and on press.
ButtonStyle closeKeyStyle(BuildContext context) {
  final c = context.colors;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final key = _Key(c, c.ledRed, dark: dark, main: true);
  bool lit(Set<WidgetState> states) =>
      !states.contains(WidgetState.disabled) &&
      (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed));
  final ink = WidgetStateProperty.resolveWith(
    (states) => lit(states) ? key.legend(states) : c.muted,
  );
  return ButtonStyle(
    foregroundColor: ink,
    iconColor: ink,
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: const WidgetStatePropertyAll(BorderSide.none),
    elevation: const WidgetStatePropertyAll(0),
    // The key sits inside the button, a small margin around it.
    backgroundBuilder: (context, states, child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: lit(states)
          ? _LitKey(key, states, child)
          : Center(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// Halo behind a light action: a blurred copy of its label, shown on hover
/// and flashing on a click.
class _Glow extends StatefulWidget {
  const _Glow({required this.states, required this.child});

  final Set<WidgetState> states;
  final Widget? child;

  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> with SingleTickerProviderStateMixin {
  late final _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void didUpdateWidget(_Glow old) {
    super.didUpdateWidget(old);
    if (widget.states.contains(WidgetState.pressed) &&
        !old.states.contains(WidgetState.pressed)) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    final states = widget.states;
    final hover =
        !states.contains(WidgetState.disabled) &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused))
        ? 0.6
        : 0.0;
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, _) {
        final flash = _flash.isAnimating ? 1 - _flash.value : 0.0;
        final level = flash > hover ? flash : hover;
        if (level == 0) return child;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: level.clamp(0.0, 1.0),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 2 + 3 * level,
                  sigmaY: 2 + 3 * level,
                ),
                child: child,
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}

/// A console key in [tone], SSL style and flat: on the dark theme a dim cap
/// with a lit frame and a legend glowing like a LED; on the light theme a
/// cap of the tone with a backlit legend. Brighter on hover and on press.
final class _Key {
  const _Key(this.c, this.tone, {required this.dark, required this.main});

  final AppColors c;
  final Color tone;
  final bool dark;

  /// Main action: full glow; the others glow less.
  final bool main;

  /// Light level: idle, hover, press; null when disabled.
  double? level(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
      ? null
      : states.contains(WidgetState.pressed)
      ? 1.0
      : states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)
      ? 0.6
      : 0.2;

  Color cap(Set<WidgetState> states) {
    final l = level(states);
    if (dark) {
      return l == null
          ? Colors.transparent
          : tone.withValues(alpha: 0.04 + 0.10 * l);
    }
    if (l == null) return const Color(0xFFB4B7BE);
    return l == 1
        ? Color.lerp(tone, Colors.black, 0.15)!
        : Color.lerp(tone, Colors.white, 0.18 * (l - 0.2) / 0.4)!;
  }

  Color legend(Set<WidgetState> states) {
    final l = level(states);
    if (dark) {
      return l == null
          ? const Color(0xFF8C909C)
          : Color.lerp(tone, Colors.white, 0.3 * l)!;
    }
    if (l == null) return const Color(0xFFEDEDF0);
    // Light legend on a dark cap, dark legend on a light one.
    return cap(states).computeLuminance() > 0.35
        ? c.text
        : const Color(0xFFFAFAFC);
  }

  Color frame(Set<WidgetState> states) {
    final l = level(states);
    if (!dark) return cap(states);
    return l == null ? c.border : tone.withValues(alpha: 0.35 + 0.45 * l);
  }

  /// Glow of the legend, like a LED behind it.
  List<Shadow> glow(Set<WidgetState> states) {
    final l = level(states);
    final ink = legend(states);
    if (l == null || (!dark && ink == c.text)) return const [];
    return [
      Shadow(
        color: ink.withValues(alpha: (main ? 0.35 : 0.15) + 0.4 * l),
        blurRadius: 4 + 6 * l,
      ),
    ];
  }

  ButtonStyle style(
    TextStyle text, {
    required Size minimumSize,
    required EdgeInsets padding,
  }) => ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
    ),
    textStyle: WidgetStateProperty.resolveWith(
      (states) => text.copyWith(shadows: glow(states)),
    ),
    // Fields and buttons share one height: no compact density shrink.
    minimumSize: WidgetStatePropertyAll(minimumSize),
    visualDensity: VisualDensity.standard,
    padding: WidgetStatePropertyAll(padding),
    elevation: const WidgetStatePropertyAll(0),
    side: const WidgetStatePropertyAll(BorderSide.none),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith(legend),
    iconColor: WidgetStateProperty.resolveWith(legend),
    backgroundBuilder: (context, states, child) => _LitKey(this, states, child),
  );
}

/// Cap of a console [key] for [states].
class _LitKey extends StatelessWidget {
  const _LitKey(this.key_, this.states, this.child);

  final _Key key_;
  final Set<WidgetState> states;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final l = key_.level(states);
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.curve,
      decoration: BoxDecoration(
        color: key_.cap(states),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: key_.frame(states)),
        boxShadow: [
          if (key_.dark && l != null)
            BoxShadow(
              color: key_.tone.withValues(
                alpha: (key_.main ? 0.05 : 0.02) + 0.12 * l,
              ),
              blurRadius: 4 + 8 * l,
            ),
        ],
      ),
      // The icons glow like the legend.
      child: IconTheme.merge(
        data: IconThemeData(shadows: key_.glow(states)),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
