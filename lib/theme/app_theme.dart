import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  static const secondary = Color(0xFFE91E63);
  static const accent = Color(0xFFFF526B);
  static const surface = Color(0xFFF5F5F7);
  static const darkBackground = Color(0xFF17171D);
  static const coral = Color(0xFFFF315A);
  static const orange = Color(0xFFD81B60);
  static const ink = Color(0xFF282832);
  static const muted = Color(0xFF696570);
  static const background = Color(0xFFFFFFFF);
  static const rose = Color(0xFFFFEDF2);
  static const green = Color(0xFF147D62);
  static const blue = Color(0xFF326C9B);
  static const danger = Color(0xFFB32636);
  static const wine = Color(0xFFD81B60);
  static const line = Color(0xFFE7E4E9);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, coral, orange],
  );
}

abstract final class AppTheme {
  static const radius = 24.0;
  static const pagePadding = 20.0;
  static const compactGap = 8.0;
  static const sectionGap = 24.0;
  static const nightSystemBars = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF100D15),
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData get night {
    const canvas = Color(0xFF0E0B13);
    const surface = Color(0xFF191320);
    const outline = Color(0xFF514366);
    const ink = Color(0xFFF9F5FF);
    const secondaryText = Color(0xFFC9BDD8);
    const pink = Color(0xFFFF8DB2);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: pink,
          brightness: Brightness.dark,
        ).copyWith(
          primary: pink,
          onPrimary: const Color(0xFF33091E),
          primaryContainer: const Color(0xFF48223B),
          onPrimaryContainer: const Color(0xFFFFDAE8),
          secondary: const Color(0xFFCBB2FF),
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: secondaryText,
          outline: outline,
          outlineVariant: outline,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: outline),
    );
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        systemOverlayStyle: nightSystemBars,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: outline, thickness: 1),
      textTheme: base.textTheme
          .copyWith(
            headlineSmall: const TextStyle(
              fontSize: 30,
              height: 1.12,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: -.8,
            ),
            titleLarge: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            bodyMedium: const TextStyle(fontSize: 14, height: 1.45, color: ink),
          )
          .apply(fontFamily: 'Roboto'),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: pink, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFCC1557),
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.coral).copyWith(
      primary: AppColors.wine,
      secondary: AppColors.secondary,
      tertiary: AppColors.accent,
      outline: AppColors.line,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      error: AppColors.danger,
      primaryContainer: AppColors.rose,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE3DFE6)),
    );
    return base.copyWith(
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
      tooltipTheme: const TooltipThemeData(preferBelow: false),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 8,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.coral,
        thumbColor: AppColors.coral,
        overlayColor: AppColors.rose,
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(AppColors.surface),
        dividerThickness: .6,
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
        ),
      ),
      textTheme: base.textTheme
          .copyWith(
            headlineSmall: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -.7,
            ),
            titleLarge: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.ink,
            ),
          )
          .apply(fontFamily: 'Roboto'),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: AppColors.ink,
          fontSize: 21,
          fontWeight: FontWeight.w800,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.coral, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          backgroundColor: AppColors.wine,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.wine,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: Color(0xFFECE7ED)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.rose,
        checkmarkColor: AppColors.coral,
        side: const BorderSide(color: Color(0xFFE3DFE6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.rose,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.wine
                : AppColors.muted,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.coral,
      ),
    );
  }
}

abstract final class AppMotion {
  static const normal = Duration(milliseconds: 240);
  static const fast = Duration(milliseconds: 160);
  static const curve = Curves.easeOutCubic;
}

abstract final class AppSpace {
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0;
}

abstract final class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x14282832), blurRadius: 28, offset: Offset(0, 10)),
  ];
}
