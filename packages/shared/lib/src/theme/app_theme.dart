import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_text_theme.dart';

/// Assembles the Lumina Marketplace design system into a Flutter
/// [ThemeData], in either mode.
///
/// Both themes come from one builder rather than two hand-written
/// copies: a light theme maintained separately drifts from the dark one
/// the first time anybody adjusts a corner radius.
class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(AppPalette.dark);
  static ThemeData get light => _build(AppPalette.light);

  static ThemeData _build(AppPalette palette) {
    final colorScheme = palette.colorScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      // Coloured from the palette rather than left to Flutter's
      // default. A null text colour resolves differently depending on
      // which widget renders it, and in light mode some of those
      // defaults are near-white -- which is how profile text and the
      // add-to-cart snackbar came out invisible.
      textTheme: AppTextStyles.textTheme.apply(
        bodyColor: palette.onSurface,
        displayColor: palette.onSurface,
      ),
      dividerTheme: DividerThemeData(
        color: palette.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surfaceContainer,
        foregroundColor: palette.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle:
            AppTextStyles.headlineSm.copyWith(color: palette.onSurface),
      ),
      cardTheme: CardThemeData(
        color: palette.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: Color(0x1AFFFFFF)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          disabledBackgroundColor: palette.surfaceContainerHigh,
          disabledForegroundColor: palette.onSurfaceVariant,
          textStyle: AppTextStyles.labelLg,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.base * 1.75,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.dp),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.onSurface,
          side: BorderSide(color: palette.outlineVariant),
          textStyle: AppTextStyles.labelLg,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.base * 1.75,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.dp),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: AppTextStyles.labelLg,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceContainerLow,
        hintStyle: AppTextStyles.bodyMd.copyWith(color: palette.outline),
        labelStyle: AppTextStyles.labelLg.copyWith(color: palette.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.containerPaddingMobile,
          vertical: AppSpacing.base * 1.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.dp),
          borderSide: BorderSide(color: palette.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.dp),
          borderSide: BorderSide(color: palette.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.dp),
          borderSide: BorderSide(color: palette.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.dp),
          borderSide: BorderSide(color: palette.error),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.secondaryContainer.withValues(alpha: 0.4),
        labelStyle: AppTextStyles.labelLg.copyWith(color: palette.onSecondaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base * 1.5),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surfaceContainerHigh,
        indicatorColor: palette.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTextStyles.labelMd.copyWith(
            color: states.contains(WidgetState.selected)
                ? palette.onPrimaryContainer
                : palette.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceContainerHigh,
        // Explicit: the snackbar draws this style directly, and with no
        // colour it fell back to onInverseSurface -- near-white text on
        // a light background.
        contentTextStyle:
            AppTextStyles.bodyMd.copyWith(color: palette.onSurface),
        actionTextColor: palette.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dp),
        ),
      ),
    );
  }
}
