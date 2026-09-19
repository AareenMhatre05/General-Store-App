import 'package:flutter/material.dart';

/// Every colour the apps use, as an instance rather than static
/// constants, so the same names resolve to different values in light and
/// dark mode.
///
/// The app was originally built dark-only against `AppColors.<name>`
/// constants, which meant a light mode was impossible without touching
/// every widget. Widgets now read `context.colors.<name>`, and the theme
/// decides which palette that is.
///
/// The two modes use two different design systems, deliberately:
/// **Lumina Marketplace** (deep navy, violet) for dark, and **Fresh
/// Market System** (green, orange, cool near-white) for light. A light
/// theme derived from Lumina's violets was tried first and its mid-tones
/// sat too close to the surfaces behind them, so text faded out. Each
/// mode now uses a palette actually designed for that brightness, and
/// every foreground/background pair was checked against WCAG contrast --
/// the lowest text pair is 4.54:1, above the 4.5 body-text threshold.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceVariant,
    required this.onBackground,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.inversePrimary,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.success,
    required this.onSuccess,
  });

  final Brightness brightness;

  final Color background;
  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color surfaceVariant;

  final Color onBackground;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color inversePrimary;

  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color inverseSurface;
  final Color inverseOnSurface;

  /// Functional accent from design.md ("teal-cyan for success").
  final Color success;
  final Color onSuccess;

  /// Categorical chart series, in fixed order — series 1 is always
  /// [chartSeries1], never cycled or reassigned when a filter changes
  /// which series are present.
  ///
  /// Identical in both modes: the pair was validated against the dark
  /// surface (#010F1F) and again against white, passing the lightness
  /// band, chroma floor, ΔE 33 under protanopia and contrast in both.
  /// Keeping one pair means a chart does not change colour when the
  /// theme does.
  static const Color chartSeries1 = Color(0xFF7A5AF8); // delivery
  static const Color chartSeries2 = Color(0xFFCC7A00); // in-store

  /// Recessive gridlines — present for reading values off, never
  /// competing with the data. This one does differ by mode, because a
  /// gridline must sit just above the surface it is drawn on.
  Color get chartGrid =>
      brightness == Brightness.dark ? const Color(0xFF273647) : const Color(0xFFE3DCEA);

  /// The dark scheme this app shipped with: deep navy surfaces, violet
  /// primary.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF051424),
    surface: Color(0xFF051424),
    surfaceDim: Color(0xFF051424),
    surfaceBright: Color(0xFF2C3A4C),
    surfaceContainerLowest: Color(0xFF010F1F),
    surfaceContainerLow: Color(0xFF0D1C2D),
    surfaceContainer: Color(0xFF122131),
    surfaceContainerHigh: Color(0xFF1C2B3C),
    surfaceContainerHighest: Color(0xFF273647),
    surfaceVariant: Color(0xFF273647),
    onBackground: Color(0xFFD4E4FA),
    onSurface: Color(0xFFD4E4FA),
    onSurfaceVariant: Color(0xFFCBC3D7),
    outline: Color(0xFF958EA0),
    outlineVariant: Color(0xFF494454),
    primary: Color(0xFFD0BCFF),
    onPrimary: Color(0xFF3C0091),
    primaryContainer: Color(0xFFA078FF),
    onPrimaryContainer: Color(0xFF340080),
    inversePrimary: Color(0xFF6D3BD7),
    secondary: Color(0xFFDBB8FF),
    onSecondary: Color(0xFF3F2160),
    secondaryContainer: Color(0xFF573878),
    onSecondaryContainer: Color(0xFFCAA6EF),
    tertiary: Color(0xFFBEC6E0),
    onTertiary: Color(0xFF283044),
    tertiaryContainer: Color(0xFF8990A8),
    onTertiaryContainer: Color(0xFF22293D),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    inverseSurface: Color(0xFFD4E4FA),
    inverseOnSurface: Color(0xFF233143),
    success: Color(0xFF4FD1C5),
    onSuccess: Color(0xFF00382F),
  );

  /// The light counterpart, using the **Fresh Market System** palette
  /// (Stitch, "Local Mart Retail System"): Fresh Leaf green as primary,
  /// Market Orange as the high-priority accent, on cool near-white
  /// surfaces.
  ///
  /// A different system from dark on purpose. The first attempt was a
  /// hand-mixed light version of Lumina's violet, and its mid-tones were
  /// too close to the surfaces behind them, so text faded out. These
  /// values are a designed light palette rather than a dark one turned
  /// inside out, and every foreground/background pair here was checked
  /// against WCAG contrast.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF8F9FF),
    surface: Color(0xFFF8F9FF),
    surfaceDim: Color(0xFFCBDBF5),
    surfaceBright: Color(0xFFF8F9FF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFEFF4FF),
    surfaceContainer: Color(0xFFE5EEFF),
    surfaceContainerHigh: Color(0xFFDCE9FF),
    surfaceContainerHighest: Color(0xFFD3E4FE),
    surfaceVariant: Color(0xFFD3E4FE),
    onBackground: Color(0xFF0B1C30),
    onSurface: Color(0xFF0B1C30),
    onSurfaceVariant: Color(0xFF3C4A42),
    outline: Color(0xFF6C7A71),
    outlineVariant: Color(0xFFBBCABF),
    primary: Color(0xFF006C49),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF10B981),
    onPrimaryContainer: Color(0xFF00422B),
    inversePrimary: Color(0xFF4EDEA3),
    // Market Orange: reserved for high-priority actions.
    secondary: Color(0xFF9D4300),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFD761A),
    onSecondaryContainer: Color(0xFF5C2400),
    tertiary: Color(0xFF2B6954),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF71AF97),
    onTertiaryContainer: Color(0xFF004231),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    inverseSurface: Color(0xFF213145),
    inverseOnSurface: Color(0xFFEAF1FF),
    // Success shares the Fresh Leaf green: in this system, green already
    // means "good".
    success: Color(0xFF006C49),
    onSuccess: Color(0xFFFFFFFF),
  );

  ColorScheme get colorScheme => ColorScheme(
        brightness: brightness,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        inversePrimary: inversePrimary,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        inverseSurface: inverseSurface,
        onInverseSurface: inverseOnSurface,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
      );
}

/// `context.colors.primary` instead of `AppColors.primary`.
///
/// Reads the palette from the ambient theme's brightness, so a widget
/// never needs to know which mode is active.
extension AppPaletteContext on BuildContext {
  AppPalette get colors => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}
