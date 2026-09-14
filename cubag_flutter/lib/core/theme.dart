import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryBrown,
      scaffoldBackgroundColor: bgWhite,
      canvasColor: lightCream,
      cardColor: bgWhite,
      dialogTheme: const DialogThemeData(backgroundColor: bgWhite),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: const CardThemeData(color: bgWhite, elevation: 0),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBrown,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: TextTheme(
        headlineLarge: GoogleFonts.outfit(
          color: darkBrown,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: GoogleFonts.outfit(
          color: darkBrown,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: GoogleFonts.outfit(
          color: darkBrown,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.outfit(
          color: darkBrown,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: GoogleFonts.inter(
          color: const Color(0xFF64748B),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: GoogleFonts.inter(
          color: primaryBrown,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryBrown,
        secondary: accentOrange,
        surface: bgWhite,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      dividerColor: borderLight,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: bgWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: accentOrange, width: 2),
        ),
        floatingLabelStyle: TextStyle(
          color: primaryBrown,
          fontWeight: FontWeight.bold,
        ),
        labelStyle: TextStyle(color: primaryBrown),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentOrange,
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
          foregroundColor: primaryBrown,
          side: const BorderSide(color: primaryBrown, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryBrown),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentOrange,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accentOrange : null,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accentOrange : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accentOrange.withAlpha(100)
              : null,
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
        headlineLarge: GoogleFonts.outfit(
          color: textHDark,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: GoogleFonts.outfit(
          color: textHDark,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: GoogleFonts.outfit(
          color: textHDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.outfit(
          color: textHDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(
          color: textHDark,
          fontSize: 18,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: GoogleFonts.inter(
          color: textDark,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: GoogleFonts.inter(
          color: const Color(0xFFC8ADA0),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: GoogleFonts.inter(
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
