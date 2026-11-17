import 'dart:ui' show ImageFilter;

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
/// teal accent on each theme. A neutral one (no saturation) is near white
/// on the dark theme and near black on the light one, like the keys of a
/// console. The colors are soft and warm, like the LEDs of a mixing desk.
@immutable
final class Accent {
  const Accent(this.hue, this.saturation);

  /// Default accent.
  static const neutral = Accent(230, 0);
  static const orange = Accent(26, 0.6);
  static const yellow = Accent(44, 0.62);

  /// [buildTheme] uses the exact design tokens for it.
  static const teal = Accent(163, 0.63);
  static const blue = Accent(199, 0.63);
  static const violet = Accent(266, 0.45);

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
  AccentPreference.neutral => Accent.neutral,
  AccentPreference.orange => Accent.orange,
  AccentPreference.yellow => Accent.yellow,
  AccentPreference.teal => Accent.teal,
  AccentPreference.blue => Accent.blue,
  AccentPreference.violet => Accent.violet,
};

/// Material theme built on the design tokens. Material is only the
/// foundation: no splash, flat surfaces, hairlines, nearly square corners.
/// The accent is [accent] (default: neutral).
ThemeData buildTheme(Brightness brightness, {Accent accent = Accent.neutral}) {
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
  final headlineSmall = text.headlineSmall?.copyWith(
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );
  final titleLarge = text.titleLarge?.copyWith(
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
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
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineSmall: headlineSmall,
      titleLarge: titleLarge,
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
      // A size above the title of a version.
      titleTextStyle: headlineSmall,
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
    // Actions: console keys with a backlit legend (SSL style), flat, in
    // the accent; the less important ones (outlined, icon) in a tone
    // between the background and the accent.
    filledButtonTheme: FilledButtonThemeData(
      style: mainKey.style(
        buttonText,
        minimumSize: const Size(64, 32),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: otherKey.style(
        buttonText,
        minimumSize: const Size(64, 32),
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
        fixedSize: const WidgetStatePropertyAll(Size.square(28)),
        iconSize: const WidgetStatePropertyAll(16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // A desktop tool: the plain pointer, no hand.
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
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
    // Always shown: where the list stands is always visible.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
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
