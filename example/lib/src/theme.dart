import 'package:flutter/material.dart';

/// The colors and themes the sample app is painted with.
abstract final class AppTheme {
  /// The dark half of the ConfigDirector wordmark.
  static const Color brandDeep = Color(0xFF0C4A6E);

  /// The bright half of the ConfigDirector wordmark, and the app's seed color.
  static const Color brandBright = Color(0xFF0EA5E9);

  /// The badge color of a config that evaluated to `true`.
  static const Color on = Color(0xFF4CAF50);

  /// The badge color of a config that evaluated to `false`.
  static const Color off = Color(0xFF9E9E9E);

  static ThemeData light() => _themeFor(Brightness.light);

  static ThemeData dark() => _themeFor(Brightness.dark);

  static ThemeData _themeFor(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brandBright,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  /// A monospaced version of [style], for config keys and JSON values.
  ///
  /// The family names differ per platform, so the fallbacks cover the ones the
  /// sample runs on.
  static TextStyle monospace(TextStyle style) => style.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
  );
}
