import 'package:flutter/material.dart';
import 'package:reaharvest_library/reaharvest_library.dart'
    show AccentPreference;

/// Spacing scale (logical pixels).
abstract final class Space {
  static const xs = 4.0;
  static const s = 8.0;
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
  static const curve = Curves.easeOutCubic;
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

  /// Console legend: small mono capitals, widely spaced. Callers upper-case
  /// the text themselves.
  TextStyle get legend => TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    height: 1.3,
    color: colors.muted,
  );

  /// Readout: mono figures (tempo, counts, dates, durations).
  TextStyle get readout => TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: colors.muted,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Accent color of the interface: a hue and a saturation, as light as the
/// default accent on each theme. A neutral one (no saturation) is near white
/// on the dark theme and near black on the light one, like the keys of a
/// console.
@immutable
final class Accent {
  const Accent(this.hue, this.saturation);

  /// Default accent; [buildTheme] uses the exact design tokens for it.
  static const teal = Accent(163, 0.63);
  static const blue = Accent(199, 0.63);
  static const neutral = Accent(230, 0);

  final double hue;
  final double saturation;

  Color on(Brightness brightness) {
    final chroma = (saturation / 0.65).clamp(0.0, 1.0);
    final lightness = brightness == Brightness.dark
        ? 0.94 - 0.25 * chroma
        : 0.12 + 0.17 * chroma;
    return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
  }

  @override
  bool operator ==(Object other) =>
      other is Accent && other.hue == hue && other.saturation == saturation;

  @override
  int get hashCode => Object.hash(hue, saturation);
}

/// Accent of the [preference].
Accent accentOf(AccentPreference preference) => switch (preference) {
  AccentPreference.teal => Accent.teal,
  AccentPreference.blue => Accent.blue,
  AccentPreference.neutral => Accent.neutral,
};

/// Material theme built on the design tokens. Material is only the
/// foundation: no splash, flat surfaces, hairlines, nearly square corners.
/// The accent is [accent] (default: teal).
ThemeData buildTheme(Brightness brightness, {Accent accent = Accent.teal}) {
  final dark = brightness == Brightness.dark;
  final tokens = dark ? AppColors.dark : AppColors.light;
  final c = accent == Accent.teal
      ? tokens
      : tokens.copyWith(accent: accent.on(brightness));
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
    extensions: [c],
  );
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);
  final square = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.s),
  );
  final hairline = BorderSide(color: c.border);
  final buttonText = const TextStyle(
    fontFamily: Fonts.text,
    fontSize: 13,
    fontWeight: FontWeight.w600,
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
  final menuShape = WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.s),
      side: hairline,
    ),
  );
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      // Also the text of the fields: as large as the button labels.
      bodyLarge: text.bodyLarge?.copyWith(
        fontSize: 13,
        height: 1.3,
        letterSpacing: 0,
      ),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      labelSmall: text.labelSmall?.copyWith(
        fontFamily: Fonts.mono,
        fontWeight: FontWeight.w700,
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
      titleTextStyle: text.titleLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.raised,
      contentTextStyle: TextStyle(color: c.text, fontSize: 13),
      actionTextColor: c.accent,
      elevation: 0,
      width: 520,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        side: hairline,
      ),
    ),
    // Validation: a console key with a backlit legend (SSL style), flat:
    // the legend glows like a LED, brighter on hover and on press.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
        ),
        textStyle: WidgetStateProperty.resolveWith(
          (states) => buttonText.copyWith(shadows: _keyGlow(states, dark)),
        ),
        // 32 high like the other buttons and the fields: no compact
        // density shrink.
        minimumSize: const WidgetStatePropertyAll(Size(64, 32)),
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Space.m),
        ),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => _keyLegend(states, dark),
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => _keyLegend(states, dark),
        ),
        backgroundBuilder: (context, states, child) =>
            _LitKey(c, states, child, dark: dark),
      ),
    ),
    // Secondary actions: a hairline frame, lit only by the hover like the
    // other buttons.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(square),
        side: WidgetStatePropertyAll(hairline),
        textStyle: WidgetStatePropertyAll(buttonText),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? c.muted : c.text,
        ),
        backgroundColor: hoverFill,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    // Secondary actions (cancel): discreet, lit only by the hover.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(square),
        textStyle: WidgetStatePropertyAll(buttonText),
        foregroundColor: litOnHover,
        backgroundColor: hoverFill,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    // Small square actions (26), lit on hover like the other buttons.
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(square),
        fixedSize: const WidgetStatePropertyAll(Size.square(28)),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        iconSize: const WidgetStatePropertyAll(16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // A desktop tool: the plain pointer, no hand.
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
        foregroundColor: litOnHover,
        backgroundColor: hoverFill,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
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
            fontWeight: FontWeight.w500,
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
        iconSize: const WidgetStatePropertyAll(16),
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
      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
      suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        borderSide: hairline,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        borderSide: hairline,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.s),
        borderSide: BorderSide(color: c.accent.withValues(alpha: 0.75)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
    ),
    iconTheme: IconThemeData(color: c.muted, size: 18),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
      textStyle: TextStyle(
        fontFamily: Fonts.text,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: c.text,
      ),
      waitDuration: const Duration(milliseconds: 450),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
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
      style: ButtonStyle(
        side: WidgetStatePropertyAll(hairline),
        shape: WidgetStatePropertyAll(square),
        visualDensity: VisualDensity.compact,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.border,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.border,
      thumbColor: c.accent,
      overlayColor: c.accent.withValues(alpha: 0.12),
      trackHeight: 3,
      tickMarkShape: SliderTickMarkShape.noTickMark,
    ),
  );
}

/// Legend of a console key, SSL style: lit (near white on the dark theme,
/// white on the near black cap of the light theme), dimmed when disabled.
Color _keyLegend(Set<WidgetState> states, bool dark) =>
    states.contains(WidgetState.disabled)
    ? (dark ? const Color(0xFF8C909C) : const Color(0xFFEDEDF0))
    : dark
    ? const Color(0xFFF0F0F2)
    : const Color(0xFFFAFAFC);

/// Light level of a console key: idle, hover, press; null when disabled.
double? _keyLevel(Set<WidgetState> states) =>
    states.contains(WidgetState.disabled)
    ? null
    : states.contains(WidgetState.pressed)
    ? 1.0
    : states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)
    ? 0.6
    : 0.2;

/// Glow of a lit legend, like a LED behind it.
List<Shadow> _keyGlow(Set<WidgetState> states, bool dark) {
  final level = _keyLevel(states);
  if (level == null) return const [];
  return [
    Shadow(
      color: _keyLegend(states, dark).withValues(alpha: 0.35 + 0.4 * level),
      blurRadius: 4 + 6 * level,
    ),
  ];
}

/// Cap of a console key for [states], flat: a dark cap with a lit frame on
/// the dark theme, a near black cap on the light theme (lighter when
/// disabled).
class _LitKey extends StatelessWidget {
  const _LitKey(this.c, this.states, this.child, {required this.dark});

  final AppColors c;
  final Set<WidgetState> states;
  final Widget? child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final level = _keyLevel(states);
    final legend = _keyLegend(states, dark);
    final Color cap;
    final Color frame;
    if (dark) {
      cap = level == null
          ? Colors.transparent
          : Colors.white.withValues(alpha: 0.03 + 0.07 * level);
      frame = level == null
          ? c.border
          : legend.withValues(alpha: 0.35 + 0.45 * level);
    } else {
      cap = level == null
          ? const Color(0xFFB4B7BE)
          // Lighter on hover, back to black when pressed.
          : level == 1
          ? const Color(0xFF111215)
          : Color.lerp(
              const Color(0xFF1C1D21),
              const Color(0xFF474A53),
              (level - 0.2) / 0.4,
            )!;
      frame = cap;
    }
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.curve,
      decoration: BoxDecoration(
        color: cap,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: frame),
        boxShadow: [
          if (dark && level != null)
            BoxShadow(
              color: legend.withValues(alpha: 0.05 + 0.12 * level),
              blurRadius: 4 + 8 * level,
            ),
        ],
      ),
      // The icons glow like the legend.
      child: IconTheme.merge(
        data: IconThemeData(shadows: _keyGlow(states, dark)),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
