import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Named text styles matching the roles defined in design.md. Headlines
/// and price displays use Hanken Grotesk; everything else uses Inter.
///
/// Deliberately colourless. Baking `onSurface` into each style made the
/// text unreadable the moment a light theme existed, because the style
/// carried the dark palette's colour with it. Flutter resolves an unset
/// text colour from the ambient theme, which is exactly the behaviour a
/// two-mode app needs; a widget wanting a specific role still says so
/// with `.copyWith(color: context.colors.x)`.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get headlineLg => GoogleFonts.hankenGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 40 / 32,
        letterSpacing: -0.02 * 32,
      );

  static TextStyle get headlineMd => GoogleFonts.hankenGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 32 / 24,
        letterSpacing: -0.01 * 24,
      );

  static TextStyle get headlineSm => GoogleFonts.hankenGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 28 / 20,
      );

  static TextStyle get bodyLg => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 28 / 18,
      );

  static TextStyle get bodyMd => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 24 / 16,
      );

  static TextStyle get bodySm => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 20 / 14,
      );

  static TextStyle get labelLg => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 20 / 14,
        letterSpacing: 0.01 * 14,
      );

  static TextStyle get labelMd => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 16 / 12,
      );

  static TextStyle get priceDisplay => GoogleFonts.hankenGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 24 / 20,
      );

  static TextTheme get textTheme => TextTheme(
        headlineLarge: headlineLg,
        headlineMedium: headlineMd,
        headlineSmall: headlineSm,
        titleLarge: headlineSm,
        titleMedium: labelLg,
        titleSmall: labelMd,
        bodyLarge: bodyLg,
        bodyMedium: bodyMd,
        bodySmall: bodySm,
        labelLarge: labelLg,
        labelMedium: labelMd,
        labelSmall: labelMd,
      );
}
