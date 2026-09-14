import 'package:flutter/material.dart';

/// Centralized CUBAG Brand & Design System Colors.
/// Ratio: White 55% -> Light Cream 25% -> Primary Brown 15% -> Dark Brown 5% -> Accent Orange 5%
class AppColors {
  // Brand Core Palette
  static const Color primaryBrown = Color(
    0xFF6B3E26,
  ); // Primary branding, headers, app bar
  static const Color darkBrown = Color(
    0xFF3E2418,
  ); // Deep contrast, headings, main text
  static const Color accentOrange = Color(
    0xFFFF5000,
  ); // CTAs, active indicators, highlights
  static const Color lightCream = Color(
    0xFFF8F4F0,
  ); // Section & card backgrounds
  static const Color white = Color(
    0xFFFFFFFF,
  ); // Main background & card surfaces
  static const Color border = Color(0xFFE8DED6); // Subtle light neutral borders

  // Text Hierarchy
  static const Color textPrimary = Color(0xFF2B211D); // Main body text
  static const Color textSecondary = Color(
    0xFF6B3E26,
  ); // Subtitles / secondary info
  static const Color textMuted = Color(0xFF94A3B8); // Muted captions & hints

  // Semantic Status Colors (Separated from Brand Orange!)
  static const Color statusGoodStanding = Color(
    0xFF2E7D32,
  ); // 🟢 Good Standing Green
  static const Color statusPending = Color(
    0xFFF59E0B,
  ); // 🟠 Pending / In Review Amber
  static const Color statusError = Color(
    0xFFC62828,
  ); // 🔴 Error / Failed / Suspended Red
  static const Color statusNeutral = Color(0xFF6B7280); // ⚪ Neutral Slate

  /// Safely parses any hex color string (e.g. '#FF941D', 'FF941D', '#FFF', '0xFF941D')
  /// or returns [fallback] if null, empty, or invalid without ever throwing.
  static Color parseHexColor(
    dynamic hexString, {
    Color fallback = accentOrange,
  }) {
    if (hexString == null) return fallback;
    String hex = hexString.toString().trim();
    if (hex.isEmpty) return fallback;

    if (hex.startsWith('0x') || hex.startsWith('0X')) {
      hex = hex.substring(2);
    } else if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    hex = hex.trim();

    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }

    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    if (hex.length != 8) return fallback;

    final val = int.tryParse(hex, radix: 16);
    if (val == null) return fallback;
    return Color(val);
  }
}
