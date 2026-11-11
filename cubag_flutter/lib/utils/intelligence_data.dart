/// Parses the `/intelligence` payload (BUG-10 / IOS-15).
///
/// The server sets `is_sample: true` while the forex section is still the
/// built-in placeholder; the app must then label the rates as sample figures
/// and never call them official. Older servers omit the flag (treated as
/// not sample, the previous behaviour).
class ForexSnapshot {
  final Map<String, String> rates;
  final bool isSample;
  final DateTime? updatedAt;

  const ForexSnapshot(this.rates, {this.isSample = false, this.updatedAt});

  static const currencies = ['USD', 'EUR', 'GBP', 'CNY'];

  static const empty = ForexSnapshot({'USD': '—', 'EUR': '—', 'GBP': '—', 'CNY': '—'});

  /// Returns null when [data] has no usable forex section.
  static ForexSnapshot? fromIntelligence(Object? data) {
    if (data is! Map || data['forex'] is! Map) return null;
    final forex = data['forex'] as Map;
    return ForexSnapshot(
      {for (final c in currencies) c: forex[c]?.toString() ?? '—'},
      isSample: data['is_sample'] == true,
      updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? '')?.toLocal(),
    );
  }

  /// e.g. "Updated 11 Nov 2026"; empty when unknown.
  String get updatedLabel {
    final d = updatedAt;
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Updated ${d.day} ${m[d.month - 1]} ${d.year}';
  }

  static const sampleNotice =
      'Sample figures, not official rates. The Secretariat has not published rates yet.';
}
