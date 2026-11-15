import 'package:flutter/material.dart';

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
    text: Color(0xFF17181C),
    muted: Color(0xFF656974),
    accent: Color(0xFF177E65),
    scrim: Color(0xFFE9E7E1),
    ledAmber: Color(0xFFE07B00),
    ledGreen: Color(0xFF1E9E5E),
    ledRed: Color(0xFFD13438),
  );

  @override
  AppColors copyWith() => this;

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

/// Material theme built on the design tokens. Material is only the
/// foundation: no splash, flat surfaces, hairlines, nearly square corners.
ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final onAccent = brightness == Brightness.dark
      ? const Color(0xFF07211A)
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: square, textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: square,
        side: hairline,
        foregroundColor: c.text,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: square, textStyle: buttonText),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: square),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shape: menuShape,
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
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.raised,
      isDense: true,
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
      textStyle: TextStyle(color: c.text, fontSize: 12),
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
