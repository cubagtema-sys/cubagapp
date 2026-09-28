import 'package:flutter/material.dart';

/// Comprehensive responsive sizing and layout utilities for CUBAG.
/// Ensures consistent, properly scaled UI across small phones (iPhone SE, budget Androids),
/// standard phones, tablets, and desktops.
class Responsive {
  Responsive._();

  static const double narrowPhoneBreakpoint = 380;
  static const double phoneBreakpoint = 600;
  static const double tabletBreakpoint = 1024;

  static bool isNarrowPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < narrowPhoneBreakpoint;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < phoneBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= phoneBreakpoint && w < tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  /// Dynamic padding for screen bodies to avoid squishing content on small devices.
  static EdgeInsets screenPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < narrowPhoneBreakpoint) {
      return const EdgeInsets.symmetric(horizontal: 10, vertical: 10);
    } else if (w < phoneBreakpoint) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    } else if (w < tabletBreakpoint) {
      return const EdgeInsets.all(20);
    }
    return const EdgeInsets.all(24);
  }

  /// Dynamic internal card padding.
  static EdgeInsets cardPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < narrowPhoneBreakpoint) {
      return const EdgeInsets.all(12);
    } else if (w < phoneBreakpoint) {
      return const EdgeInsets.all(16);
    }
    return const EdgeInsets.all(20);
  }

  /// Calculates a scalable font size clamped safely so it never clips or overflows.
  static double scaledFontSize(BuildContext context, double baseSize) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 340) {
      return baseSize * 0.85;
    } else if (w < narrowPhoneBreakpoint) {
      return baseSize * 0.92;
    }
    return baseSize;
  }
}

/// Extension for fast, readable responsive queries on BuildContext.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  bool get isNarrowPhone => screenWidth < Responsive.narrowPhoneBreakpoint;
  bool get isPhone => screenWidth < Responsive.phoneBreakpoint;
  bool get isTablet => Responsive.isTablet(this);
  bool get isDesktop => screenWidth >= Responsive.tabletBreakpoint;

  EdgeInsets get responsiveScreenPadding => Responsive.screenPadding(this);
  EdgeInsets get responsiveCardPadding => Responsive.cardPadding(this);

  double sp(double base) => Responsive.scaledFontSize(this, base);
}
