import '../services/api_service.dart';

/// One payment code from the admin-edited code list (server:
/// GET/POST /admin/payment-codes, setting `cubag_payment_codes`). Nothing
/// about the codes is fixed in the app; the server holds the list.
class PaymentCode {
  final String code;
  final String label;
  final String bankName;
  final String accountNumber;
  final List<String> sections;
  final List<String> keywords;
  final bool active;

  const PaymentCode({
    required this.code,
    required this.label,
    required this.bankName,
    required this.accountNumber,
    this.sections = const [],
    this.keywords = const [],
    this.active = true,
  });

  factory PaymentCode.fromJson(Map<String, dynamic> j) {
    List<String> words(dynamic v) =>
        (v is List ? v : (v?.toString() ?? '').split(',')).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    final rawCode = (j['code'] ?? '').toString().trim().toUpperCase();
    final code = rawCode.startsWith('CUB-') ? rawCode.substring(4) : rawCode;
    return PaymentCode(
      code: code,
      label: (j['label'] ?? '').toString(),
      bankName: (j['bank_name'] ?? '').toString(),
      accountNumber: (j['account_number'] ?? '').toString().replaceAll(RegExp(r'\s+'), ''),
      sections: words(j['sections']),
      keywords: words(j['keywords']),
      active: j['active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'label': label,
        'bank_name': bankName,
        'account_number': accountNumber,
        'sections': sections,
        'keywords': keywords,
        'active': active,
      };

  PaymentCode copyWith({bool? active}) => PaymentCode(
        code: code,
        label: label,
        bankName: bankName,
        accountNumber: accountNumber,
        sections: sections,
        keywords: keywords,
        active: active ?? this.active,
      );

  /// Loads the list from the server (admins only).
  static Future<List<PaymentCode>> fetch() async {
    final res = await ApiService().get('/admin/payment-codes');
    final list = (res.data is Map ? res.data['codes'] : null) as List? ?? [];
    return list.map((e) => PaymentCode.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}

/// The code a fee gets when no code is typed in, worked out the same way as
/// the server (config/payment_codes.py code_for_item): the active code for the
/// fee's account that lists the fee's type, else one with no types, else the
/// first for that account.
String defaultPaymentCode(List<PaymentCode> codes, {String? section, String? bank, String? account}) {
  final active = codes.where((c) => c.active).toList();
  final s = (section ?? '').trim().toLowerCase();
  final acc = (account ?? '').replaceAll(RegExp(r'\s+'), '');
  final b = (bank ?? '').trim().toLowerCase();
  final same = acc.isNotEmpty
      ? active.where((c) => c.accountNumber == acc).toList()
      : (b.isNotEmpty ? active.where((c) => c.bankName.toLowerCase().contains(b)).toList() : <PaymentCode>[]);
  if (same.isNotEmpty) {
    for (final c in same) {
      if (s.isNotEmpty && c.sections.contains(s)) return c.code;
    }
    for (final c in same) {
      if (c.sections.isEmpty) return c.code;
    }
    return same.first.code;
  }
  for (final c in active) {
    if (s.isNotEmpty && c.sections.contains(s)) return c.code;
  }
  return 'OTH';
}

/// A fee's code: the one an admin chose, else the default.
String paymentCodeFor(Map<String, dynamic> fee, List<PaymentCode> codes) {
  var own = (fee['payment_code'] ?? '').toString().trim().toUpperCase();
  if (own.startsWith('CUB-')) own = own.substring(4);
  if (own.isNotEmpty) return own;
  return defaultPaymentCode(
    codes,
    section: fee['section']?.toString(),
    bank: fee['bank_name']?.toString(),
    account: fee['account_number']?.toString(),
  );
}
