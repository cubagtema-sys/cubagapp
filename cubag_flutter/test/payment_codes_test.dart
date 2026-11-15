import 'package:cubag_flutter/utils/payment_codes.dart';
import 'package:flutter_test/flutter_test.dart';

// Same starting list and rules as cubag-backend/config/payment_codes.py.
final _codes = [
  for (final j in [
    {'code': 'CUB-CTI', 'label': 'Courses', 'bank_name': 'NIB', 'account_number': '1110045585101', 'sections': ['cti']},
    {'code': 'CUB-CPD', 'label': 'CPD', 'bank_name': 'NIB', 'account_number': '1110045585101', 'sections': ['national', 'variable']},
    {'code': 'CUB-DST', 'label': 'District', 'bank_name': 'Ecobank', 'account_number': '1441002452360', 'sections': []},
    {'code': 'CUB-SUB', 'label': 'Subscription', 'bank_name': 'Zenith Bank', 'account_number': '6010309212', 'sections': []},
    {'code': 'CUB-REG', 'label': 'Registration', 'bank_name': 'GCB', 'account_number': '107113005326', 'sections': ['new_membership']},
    {'code': 'CUB-ADM', 'label': 'Admin', 'bank_name': 'GCB', 'account_number': '107113005326', 'sections': ['national', 'district', 'variable']},
    {'code': 'CUB-OTH', 'label': 'Other', 'bank_name': 'GCB', 'account_number': '107113005326', 'sections': []},
  ])
    PaymentCode.fromJson(j),
];

void main() {
  test('default code follows the fee account and type', () {
    expect(defaultPaymentCode(_codes, section: 'national', account: '6010309212'), 'CUB-SUB');
    expect(defaultPaymentCode(_codes, section: 'national', account: '107113005326'), 'CUB-ADM');
    expect(defaultPaymentCode(_codes, section: 'new_membership', account: '107113005326'), 'CUB-REG');
    expect(defaultPaymentCode(_codes, section: 'district', account: '1441002452360'), 'CUB-DST');
    expect(defaultPaymentCode(_codes, section: 'national', account: '1110045585101'), 'CUB-CPD');
    expect(defaultPaymentCode(_codes, section: 'guest', account: '107113005326'), 'CUB-OTH');
  });

  test('a code added by an admin is used, and switched-off codes are skipped', () {
    final withLevy = [
      ..._codes,
      PaymentCode.fromJson({'code': 'cub-lev', 'label': 'Port levy', 'bank_name': 'Zenith Bank', 'account_number': '6010 309212', 'sections': 'levy'}),
    ];
    expect(withLevy.last.code, 'CUB-LEV');
    expect(defaultPaymentCode(withLevy, section: 'levy', account: '6010309212'), 'CUB-LEV');
    final off = [for (final c in withLevy) c.code == 'CUB-LEV' ? c.copyWith(active: false) : c];
    expect(defaultPaymentCode(off, section: 'levy', account: '6010309212'), 'CUB-SUB');
  });

  test('a fee keeps the code an admin chose', () {
    expect(paymentCodeFor({'section': 'national', 'account_number': '107113005326', 'payment_code': ' cub-legal '}, _codes), 'CUB-LEGAL');
    expect(paymentCodeFor({'section': 'variable', 'account_number': '107113005326'}, _codes), 'CUB-ADM');
  });
}
