import 'package:flutter/material.dart';
import 'colors.dart';

/// Tipografía Harmonix: redondeada, clara, jerarquía MD3.
class HarmonixTypography {
  HarmonixTypography._();

  static const String displayFont = 'Roboto';
  static const String bodyFont = 'Roboto';

  static TextTheme get textTheme => TextTheme(
        displayLarge: TextStyle(
          fontFamily: displayFont,
          fontSize: 57,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          color: HarmonixColors.textPrimary,
        ),
        displayMedium: TextStyle(
          fontFamily: displayFont,
          fontSize: 45,
          height: 1.16,
          fontWeight: FontWeight.w700,
          color: HarmonixColors.textPrimary,
        ),
        displaySmall: TextStyle(
          fontFamily: displayFont,
          fontSize: 36,
          height: 1.22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: HarmonixColors.textPrimary,
        ),
        headlineLarge: TextStyle(
          fontFamily: displayFont,
          fontSize: 32,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: HarmonixColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: displayFont,
          fontSize: 28,
          height: 1.29,
          fontWeight: FontWeight.w600,
          color: HarmonixColors.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: displayFont,
          fontSize: 24,
          height: 1.33,
          fontWeight: FontWeight.w600,
          color: HarmonixColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: displayFont,
          fontSize: 22,
          height: 1.27,
          fontWeight: FontWeight.w600,
          color: HarmonixColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: displayFont,
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: HarmonixColors.textPrimary,
        ),
        titleSmall: TextStyle(
          fontFamily: displayFont,
          fontSize: 14,
          height: 1.43,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: HarmonixColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: bodyFont,
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
          color: HarmonixColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: bodyFont,
          fontSize: 14,
          height: 1.43,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          color: HarmonixColors.textSecondary,
        ),
        bodySmall: TextStyle(
          fontFamily: bodyFont,
          fontSize: 12,
          height: 1.33,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
          color: HarmonixColors.textSecondary,
        ),
        labelLarge: TextStyle(
          fontFamily: bodyFont,
          fontSize: 14,
          height: 1.43,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: HarmonixColors.textPrimary,
        ),
        labelMedium: TextStyle(
          fontFamily: bodyFont,
          fontSize: 12,
          height: 1.33,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: HarmonixColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontFamily: bodyFont,
          fontSize: 11,
          height: 1.45,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: HarmonixColors.textSecondary,
        ),
      );
}
