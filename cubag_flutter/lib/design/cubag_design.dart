import 'package:flutter/material.dart';

/// CUBAG design system — member app (mobile).
///
/// Direction: the member's licence is treated as an official document. The
/// interface is quiet (white, warm ink, hairlines); the brand is spent on one
/// strong surface per screen (the cocoa licence card, the sign-in header).
///
/// Contrast (WCAG 2.2): every text pairing below is >= 4.5:1 on its intended
/// background. Bright [CubagColors.seal] is for the seal, focus rings and
/// graphics only — never for text or as a button fill behind white text.
abstract final class CubagColors {
  // Ink & text
  static const ink = Color(0xFF2A1810); // headings, primary text (17:1)
  static const inkSoft = Color(0xFF4A3A32); // body copy (10.8:1)
  static const muted = Color(0xFF6E625B); // secondary text (5.9:1 white, 5.4:1 sand)

  // Brand
  static const cocoa = Color(0xFF5C3421); // licence card, sign-in header
  static const cocoaDeep = Color(0xFF4A2A1B); // pressed / gradient end
  static const onCocoa = Color(0xFFFFFFFF);
  static const onCocoaMuted = Color(0xFFE8C4AE); // 6.6:1 on cocoa
  static const seal = Color(0xFFFF5000); // brand mark, focus, graphics only
  static const action = Color(0xFFC2410C); // buttons, links (white on it: 5.2:1)
  static const actionPressed = Color(0xFFA3360A);
  static const actionTint = Color(0xFFFBEDE5);

  // Surfaces & lines
  static const paper = Color(0xFFFFFFFF);
  static const sand = Color(0xFFF7F4F1); // grouped/background areas
  static const line = Color(0xFFE9E2DB); // hairlines, input borders
  static const lineStrong = Color(0xFFD6CCC2);

  // Status: text colour + tint background
  static const valid = Color(0xFF1F7A4D);
  static const validTint = Color(0xFFE6F3EC);
  static const due = Color(0xFFA15C07);
  static const dueTint = Color(0xFFFCF0DC);
  static const lapsed = Color(0xFFB42318);
  static const lapsedTint = Color(0xFFFDECEA);
}

/// 4-pt spacing scale.
abstract final class CubagSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0; // screen gutter
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
}

/// Three radii, by hierarchy: controls, containers, hero surfaces.
abstract final class CubagRadius {
  static const control = 10.0; // inputs, buttons, chips
  static const card = 14.0; // grouped lists, sheets' inner blocks
  static const hero = 22.0; // licence card, bottom sheets
}

/// Type: Public Sans for the interface; Source Serif Display only for
/// certificate-like moments (association name, member name, screen titles).
abstract final class CubagType {
  static const sans = 'Public Sans';
  static const serif = 'Source Serif Display';
  static const _tabular = [FontFeature.tabularFigures()];

  /// Screen title / greeting (serif).
  static const display = TextStyle(
    fontFamily: serif, fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w600,
    color: CubagColors.ink, letterSpacing: -0.3,
  );
  /// Section-leading serif title (member name on the licence, sheet titles).
  static const title = TextStyle(
    fontFamily: serif, fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w600,
    color: CubagColors.ink, letterSpacing: -0.2,
  );
  static const headline = TextStyle(
    fontFamily: sans, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600,
    color: CubagColors.ink,
  );
  static const body = TextStyle(
    fontFamily: sans, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400,
    color: CubagColors.inkSoft,
  );
  static const bodyStrong = TextStyle(
    fontFamily: sans, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600,
    color: CubagColors.ink,
  );
  static const small = TextStyle(
    fontFamily: sans, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400,
    color: CubagColors.muted,
  );
  static const label = TextStyle(
    fontFamily: sans, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600,
    color: CubagColors.ink,
  );
  static const caption = TextStyle(
    fontFamily: sans, fontSize: 12.5, height: 16 / 12.5, fontWeight: FontWeight.w500,
    color: CubagColors.muted,
  );
  /// Amounts, licence numbers, dates in lists: even-width figures.
  static const figure = TextStyle(
    fontFamily: sans, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600,
    color: CubagColors.ink, fontFeatures: _tabular,
  );
}
