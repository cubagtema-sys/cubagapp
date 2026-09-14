import 'dart:math' as math;
import 'package:flutter/services.dart';

/// Auto-formatter for GhanaPostGPS Digital Address:
/// Automatically enforces maximum 10 alphanumeric characters (e.g. GA12345678)
/// and inserts hyphens: after the first 2 characters and after the next 4 characters (e.g. GA-1234-5678).
class GhanaDigitalAddressFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip everything except uppercase alphanumeric characters
    final clean = newValue.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );

    // Cap at 10 alphanumeric characters maximum
    final capped = clean.length > 10 ? clean.substring(0, 10) : clean;

    final buffer = StringBuffer();
    for (int i = 0; i < capped.length; i++) {
      if (i == 2 || i == 6) {
        buffer.write('-');
      }
      buffer.write(capped[i]);
    }

    final formatted = buffer.toString();

    // Preserve cursor position reasonably
    int selectionIndex = newValue.selection.end;
    // Count how many non-hyphen chars were before cursor
    int nonHyphenBefore = 0;
    for (int i = 0; i < math.min(selectionIndex, newValue.text.length); i++) {
      if (newValue.text[i] != '-') nonHyphenBefore++;
    }

    int newCursorPos = 0;
    int charsCounted = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (charsCounted >= nonHyphenBefore) break;
      if (formatted[i] != '-') charsCounted++;
      newCursorPos = i + 1;
    }

    newCursorPos = math.min(newCursorPos, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
  }
}

/// Validator & Normalization functions for CUBAG forms.
class AppValidators {
  /// Validates GhanaPostGPS Digital Address format.
  /// Standard examples: GA-543-0125, GA-1234-5678, AK-039-5028, ER-200-1987.
  static String? validateGhanaDigitalAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Optional field
    }

    final clean = value.trim().toUpperCase();
    final regExp = RegExp(r'^[A-Z]{2,3}-\d{3,4}-\d{4}$');
    if (!regExp.hasMatch(clean)) {
      return 'Invalid Digital Address format (e.g. GA-183-9023 or GA-1234-5678)';
    }

    return null; // Valid!
  }

  /// Validates full name or contact person name.
  /// Supports spaces, hyphens, apostrophes, periods, and unicode/accented letters.
  static bool isValidName(String name) {
    final clean = name.trim();
    if (clean.length < 2) return false;
    final regex = RegExp(r"^[a-zA-Z\u00C0-\u024F\s\-\'\.]+$");
    return regex.hasMatch(clean);
  }

  /// Normalizes phone numbers (Ghanaian + international format).
  /// Examples:
  /// '+233241234567' -> '0241234567'
  /// '233241234567'  -> '0241234567'
  /// '024 123 4567'  -> '0241234567'
  /// '024-123-4567'  -> '0241234567'
  /// '0241234567'    -> '0241234567'
  static String normalizePhoneNumber(String raw) {
    var clean = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '').trim();

    if (clean.startsWith('+233')) {
      clean = '0${clean.substring(4)}';
    } else if (clean.startsWith('233') && clean.length == 12) {
      clean = '0${clean.substring(3)}';
    } else if (clean.startsWith('00233')) {
      clean = '0${clean.substring(5)}';
    }
    return clean;
  }

  /// Validates whether the normalized phone number is a valid 10-digit Ghanaian mobile/fixed line.
  static bool isValidGhanaPhone(String phone) {
    final normalized = normalizePhoneNumber(phone);
    return RegExp(r'^0[0-9]{9}$').hasMatch(normalized);
  }
}
