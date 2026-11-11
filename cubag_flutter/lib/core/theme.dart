import 'package:flutter/material.dart';
import '../design/cubag_design.dart';

class AppTheme {
  // CUBAG Light Theme Palette (White 55% -> Light Cream 25% -> Brown 15% -> Dark Brown 5% -> Orange 5%)
  static const Color primaryBrown = Color(
    0xFF6B3E26,
  ); // Brand identity, app bar, headers
  static const Color darkBrown = Color(
    0xFF3E2418,
  ); // Deep contrast, headings, primary text
  static const Color accentOrange = Color(
    0xFFFF5000,
  ); // CTAs, active states, focus borders
  static const Color bgWhite = Color(0xFFFFFFFF); // Main background surface
  static const Color lightCream = Color(
    0xFFF8F4F0,
  ); // Section & card background blocks
  static const Color borderLight = Color(
    0xFFE8DED6,
  ); // Subtle light neutral borders
  static const Color textPrimary = Color(0xFF2B211D); // Body text

  // Rich Shining Chocolate Dark Theme Colors
  static const Color textDark = Color(0xFFC8ADA0); // Soft cocoa tan text
  static const Color textHDark = Color(0xFFFFF8F3); // Warm ivory cream headings
  static const Color bgDark = Color(
    0xFF1A0F0A,
  ); // Deep rich chocolate espresso background
  static const Color borderDark = Color(
    0xFF4D2D20,
  ); // Warm chocolate bronze border
  static const Color codeBgDark = Color(
    0xFF281710,
  ); // Warm dark velvet chocolate cards & surfaces
  static const Color accentDark = Color(
    0xFFFF5000,
  ); // Radiant shining caramel gold accent
  static const Color accentBgDark = Color(0x26FF5000);

  /// Member app theme, built from the design system (lib/design/cubag_design.dart).
  /// Screens not yet redesigned still inherit the new type, controls and dialogs.
  static ThemeData get lightTheme {
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CubagRadius.control),
    );
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(CubagRadius.control),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: CubagType.sans,
      primaryColor: CubagColors.cocoa,
      scaffoldBackgroundColor: CubagColors.paper,
      canvasColor: CubagColors.paper,
      cardColor: CubagColors.paper,
      dividerColor: CubagColors.line,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: CubagColors.action,
        onPrimary: Colors.white,
        primaryContainer: CubagColors.actionTint,
        onPrimaryContainer: CubagColors.actionPressed,
        secondary: CubagColors.cocoa,
        onSecondary: Colors.white,
        surface: CubagColors.paper,
        onSurface: CubagColors.ink,
        onSurfaceVariant: CubagColors.muted,
        surfaceContainerLowest: CubagColors.paper,
        surfaceContainerLow: CubagColors.sand,
        surfaceContainer: CubagColors.sand,
        surfaceContainerHigh: CubagColors.sand,
        outline: CubagColors.lineStrong,
        outlineVariant: CubagColors.line,
        error: CubagColors.lapsed,
        onError: Colors.white,
      ),
      textTheme: const TextTheme(
        displaySmall: CubagType.display,
        headlineMedium: CubagType.title,
        headlineSmall: CubagType.headline,
        titleLarge: CubagType.headline,
        titleMedium: CubagType.bodyStrong,
        titleSmall: CubagType.label,
        bodyLarge: CubagType.body,
        bodyMedium: CubagType.body,
        bodySmall: CubagType.small,
        labelLarge: CubagType.label,
        labelMedium: CubagType.caption,
        labelSmall: CubagType.caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: CubagColors.paper,
        foregroundColor: CubagColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: CubagType.headline,
      ),
      cardTheme: CardThemeData(
        color: CubagColors.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CubagRadius.card),
          side: const BorderSide(color: CubagColors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CubagColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CubagRadius.hero)),
        titleTextStyle: CubagType.title,
        contentTextStyle: CubagType.body,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CubagColors.paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: CubagColors.lineStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(CubagRadius.hero)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CubagColors.ink,
        contentTextStyle: CubagType.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CubagRadius.control)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CubagColors.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border(CubagColors.lineStrong),
        enabledBorder: border(CubagColors.lineStrong),
        focusedBorder: border(CubagColors.seal, 2),
        errorBorder: border(CubagColors.lapsed),
        focusedErrorBorder: border(CubagColors.lapsed, 2),
        labelStyle: CubagType.body.copyWith(color: CubagColors.muted),
        floatingLabelStyle: CubagType.label.copyWith(color: CubagColors.ink),
        hintStyle: CubagType.body.copyWith(color: CubagColors.muted),
        helperStyle: CubagType.caption,
        errorStyle: CubagType.caption.copyWith(color: CubagColors.lapsed),
        prefixIconColor: CubagColors.muted,
        suffixIconColor: CubagColors.muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CubagColors.action,
          foregroundColor: Colors.white,
          disabledBackgroundColor: CubagColors.line,
          disabledForegroundColor: CubagColors.muted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: controlShape,
          textStyle: CubagType.bodyStrong,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CubagColors.action,
          foregroundColor: Colors.white,
          disabledBackgroundColor: CubagColors.line,
          disabledForegroundColor: CubagColors.muted,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: controlShape,
          textStyle: CubagType.bodyStrong,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CubagColors.ink,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: const BorderSide(color: CubagColors.lineStrong),
          shape: controlShape,
          textStyle: CubagType.bodyStrong,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CubagColors.action,
          minimumSize: const Size(48, 44),
          shape: controlShape,
          textStyle: CubagType.label,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: CubagColors.paper,
        selectedColor: CubagColors.actionTint,
        side: const BorderSide(color: CubagColors.line),
        labelStyle: CubagType.label,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CubagRadius.control)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: CubagColors.muted,
        titleTextStyle: CubagType.bodyStrong,
        subtitleTextStyle: CubagType.small,
        contentPadding: EdgeInsets.symmetric(horizontal: CubagSpace.lg),
      ),
      dividerTheme: const DividerThemeData(color: CubagColors.line, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: CubagColors.action),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: CubagColors.lineStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? CubagColors.action : null,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? CubagColors.action : null,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CubagColors.paper,
        surfaceTintColor: Colors.transparent,
        indicatorColor: CubagColors.actionTint,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => CubagType.caption.copyWith(
            color: s.contains(WidgetState.selected) ? CubagColors.ink : CubagColors.muted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? CubagColors.action : CubagColors.muted,
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: accentDark,
      scaffoldBackgroundColor: bgDark,
      cardColor: codeBgDark,
      canvasColor: codeBgDark,
      dialogTheme: const DialogThemeData(backgroundColor: codeBgDark),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: const CardThemeData(color: codeBgDark, elevation: 0),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textHDark,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: textHDark,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: TextStyle(
          color: textHDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: textHDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: textHDark,
          fontSize: 18,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: textDark,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: const Color(0xFFC8ADA0),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: TextStyle(
          color: textDark,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: accentDark,
        secondary: accentDark,
        surface: codeBgDark,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textHDark,
        surfaceContainerHighest: Color(0xFF4D2D20),
      ),
      dividerColor: borderDark,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: codeBgDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: accentDark, width: 2),
        ),
        floatingLabelStyle: TextStyle(color: accentDark),
        labelStyle: TextStyle(color: Color(0xFFC8ADA0)),
        hintStyle: TextStyle(color: Color(0xFF8C6E61)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentDark,
          side: const BorderSide(color: accentDark),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentDark),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentDark,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accentDark : null,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accentDark : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accentDark.withAlpha(100)
              : null,
        ),
      ),
    );
  }
}
