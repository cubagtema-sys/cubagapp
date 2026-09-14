library;

/// Shared Dart extension methods.
///
/// This file must be eagerly imported (not deferred) because extension methods
/// cannot be loaded lazily — the type system needs them available at compile time.
/// Any page file that is imported as `deferred as` must NOT define extensions;
/// they belong here instead.

extension StringCapitalize on String {
  /// Returns this string with the first character uppercased.
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
