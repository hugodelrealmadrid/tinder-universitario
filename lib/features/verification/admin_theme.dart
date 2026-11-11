import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

abstract final class AdminTheme {
  static const sidebar = Color(0xFF111019);
  static const muted = Color(0xFFB8B2C5);
  static const alert = Color(0xFFFFA5B2);
  static const canvas = Color(0xFF0C0B11);
  static const surface = Color(0xFF161420);
  static const border = Color(0xFF353044);

  static ThemeData get dark {
    final base = AppTheme.night;
    final colors = base.colorScheme.copyWith(
      primary: const Color(0xFFD9ADFF),
      onPrimary: const Color(0xFF280943),
      primaryContainer: const Color(0xFF382051),
      onPrimaryContainer: const Color(0xFFF2D9FF),
      surface: surface,
      onSurfaceVariant: muted,
      outline: const Color(0xFF776B89),
      outlineVariant: border,
      error: alert,
    );
    return base.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: canvas,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: canvas),
      dividerTheme: const DividerThemeData(color: border),
      cardTheme: base.cardTheme.copyWith(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(Color(0xFF201A2B)),
        dividerThickness: .7,
        horizontalMargin: 16,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF7131A0),
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
