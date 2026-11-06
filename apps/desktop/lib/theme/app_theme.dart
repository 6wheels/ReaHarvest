import 'package:flutter/material.dart';

/// Spacing scale (logical pixels).
abstract final class Space {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
}

/// Motion: durations and curves shared by every animation.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
}

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
  });

  final Color background;
  final Color surface;
  final Color raised;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;

  /// Tint over blurred content behind popups.
  final Color scrim;

  static const dark = AppColors(
    background: Color(0xFF0E0F13),
    surface: Color(0xFF16181E),
    raised: Color(0xFF1D2028),
    border: Color(0xFF2A2E38),
    text: Color(0xFFECEEF3),
    muted: Color(0xFF8D93A1),
    accent: Color(0xFF7FE0C5),
    scrim: Color(0xFF05060A),
  );

  static const light = AppColors(
    background: Color(0xFFF4F3EF),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    border: Color(0xFFE2E0DA),
    text: Color(0xFF17181C),
    muted: Color(0xFF6B6F7A),
    accent: Color(0xFF1F8A70),
    scrim: Color(0xFFE9E7E1),
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
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Material theme built on the design tokens. Material is only the
/// foundation: no splash, flat surfaces, own colors and typography.
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
    error: const Color(0xFFE5484D),
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    outline: c.border,
    outlineVariant: c.border,
    surfaceContainerHighest: c.raised,
    secondaryContainer: c.accent.withValues(alpha: 0.18),
    onSecondaryContainer: c.text,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: c.background,
    splashFactory: NoSplash.splashFactory,
    hoverColor: c.text.withValues(alpha: 0.05),
    focusColor: c.accent.withValues(alpha: 0.12),
    highlightColor: Colors.transparent,
    extensions: [c],
  );
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);
  return base.copyWith(
    textTheme: text.copyWith(
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
    ),
    iconTheme: IconThemeData(color: c.muted, size: 20),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      textStyle: TextStyle(color: c.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        visualDensity: VisualDensity.compact,
      ),
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
