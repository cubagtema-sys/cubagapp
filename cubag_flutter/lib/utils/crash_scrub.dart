/// Pure helpers for crash reporting (BUG-04). No plugin imports, so they can be
/// unit-tested and compiled for every platform.
class CrashScrub {
  CrashScrub._();

  static final _queryString = RegExp(r'\?[^\s"\x27)]*');
  static final _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+', caseSensitive: false);
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}');
  static final _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
  static final _longDigits = RegExp(r'\+?\d[\d\s\-]{7,}\d');
  static const maxLength = 500;

  /// Remove things that must never leave the phone in a crash report:
  /// URL query strings (tokens), bearer tokens / JWTs, e-mail addresses and
  /// phone/account numbers. Truncates long messages.
  static String scrub(String input) {
    var s = input
        .replaceAllMapped(_bearer, (m) => '${m[1]}[redacted]')
        .replaceAll(_jwt, '[token]')
        .replaceAll(_queryString, '?[redacted]')
        .replaceAll(_email, '[email]')
        .replaceAll(_longDigits, '[number]');
    if (s.length > maxLength) s = '${s.substring(0, maxLength)}…';
    return s;
  }
}

/// Holds errors raised before the crash reporter is ready, then hands them
/// over once it is. Bounded so a crash loop cannot exhaust memory.
class PendingCrashBuffer<T> {
  PendingCrashBuffer({this.capacity = 20});

  final int capacity;
  final List<T> _items = [];
  int dropped = 0;

  void add(T item) {
    if (_items.length >= capacity) {
      dropped++;
      return;
    }
    _items.add(item);
  }

  /// Returns everything buffered, oldest first, and empties the buffer.
  List<T> drain() {
    final out = List<T>.from(_items);
    _items.clear();
    return out;
  }

  int get length => _items.length;
}
