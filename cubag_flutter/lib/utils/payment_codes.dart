/// Payment codes as the server works them out (cubag-backend/config/payment_codes.py):
/// each code settles into one CUBAG account, so WhitsunPay can route by code.
const paymentCodeLabels = {
  'CUB-REG': 'New member registration',
  'CUB-SUB': 'Subscription and development levy',
  'CUB-ADM': 'Administrative, legal, welfare and other charges',
  'CUB-DST': 'District registration, clearance and welfare',
  'CUB-CPD': 'CPD and refresher courses',
  'CUB-CTI': 'Training Institute courses',
  'CUB-GST': 'Public and guest services',
  'CUB-OTH': 'Other payments',
};

/// The code a fee gets when no code is typed in: from its bank, and for GCB
/// from whether it is a new-member fee.
String defaultPaymentCode(String? section, String? bank) {
  final b = (bank ?? '').toLowerCase();
  final s = (section ?? '').toLowerCase();
  if (b.contains('zenith')) return 'CUB-SUB';
  if (b.contains('ecobank')) return 'CUB-DST';
  if (b.contains('nib') || b.contains('national investment')) return s == 'cti' ? 'CUB-CTI' : 'CUB-CPD';
  if (s == 'new_membership' || s == 'new_reg' || s == 'corporate') return 'CUB-REG';
  if (s == 'guest') return 'CUB-GST';
  if (const ['national', 'district', 'variable'].contains(s) || b.contains('gcb')) return 'CUB-ADM';
  return 'CUB-OTH';
}

/// A fee's code: the one an admin typed, else the default.
String paymentCodeFor(Map<String, dynamic> fee) {
  final own = (fee['payment_code'] ?? '').toString().trim().toUpperCase();
  return own.isNotEmpty ? own : defaultPaymentCode(fee['section']?.toString(), fee['bank_name']?.toString());
}
