import 'package:flutter/material.dart';

class AppThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static void toggle() {
    mode.value =
        mode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2A6F7B),
      brightness: Brightness.light,
    );
    return _base(scheme, false);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2A6F7B),
      brightness: Brightness.dark,
    );
    return _base(scheme, true);
  }

  static ThemeData _base(ColorScheme scheme, bool isDark) {
    final textTheme = Typography.material2021().black.apply(
      fontFamily: 'Segoe UI',
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: isDark ? 1 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.35 : 0.8,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
  }
}
