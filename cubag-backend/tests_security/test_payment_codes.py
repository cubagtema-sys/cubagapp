"""Payment codes: each code settles into one account; amounts add up exactly."""
from config.payment_codes import (
    DEFAULT_ACCOUNTS, code_for_description, code_for_item, code_split, codes_for_payment,
    conflicting_codes, narration,
)

RENEWAL = [
    {'label': 'Subscription fee (small companies)', 'amount': '233.00', 'section': 'national', 'bank_name': 'Zenith Bank', 'account_number': '6010309212'},
    {'label': 'Administrative fee', 'amount': '200.00', 'section': 'national', 'bank_name': 'GCB', 'account_number': '107113005326'},
    {'label': 'Legal & Audit Fee', 'amount': '100.00', 'section': 'national', 'bank_name': 'GCB', 'account_number': '107113005326'},
    {'label': 'TM District Clearance', 'amount': '250.00', 'section': 'district', 'bank_name': 'Ecobank', 'account_number': '1441002452360'},
]


def test_default_codes_follow_the_bank():
    assert [code_for_item(i) for i in RENEWAL] == ['CUB-SUB', 'CUB-ADM', 'CUB-ADM', 'CUB-DST']
    assert code_for_item({'section': 'new_membership', 'bank_name': 'GCB'}) == 'CUB-REG'
    assert code_for_item({'section': 'national', 'bank_name': 'NIB'}) == 'CUB-CPD'
    assert code_for_item({'section': 'national', 'bank_name': 'GCB', 'payment_code': 'cub-legal'}) == 'CUB-LEGAL'


def test_every_default_code_has_one_account():
    assert all(len(v) == 2 for v in DEFAULT_ACCOUNTS.values())


def test_split_groups_by_code_and_adds_up():
    split = code_split(RENEWAL, total=783)
    assert [(c['code'], c['amount'], c['bank_name']) for c in split] == [
        ('CUB-SUB', 233.0, 'Zenith Bank'), ('CUB-ADM', 300.0, 'GCB'), ('CUB-DST', 250.0, 'Ecobank'),
    ]


def test_part_payment_is_shared_in_proportion_and_exact():
    split = code_split(RENEWAL, total=391.5)
    assert round(sum(c['amount'] for c in split), 2) == 391.5
    assert split[0]['amount'] == 116.5  # 233 / 783 of 391.50


def test_narration_puts_codes_first_and_stays_short():
    text = narration(code_split(RENEWAL, total=783), 'CUBAG-42-ab12cd34', 'Annual Renewal Dues – National & District Clearance')
    assert text.startswith('CUB-SUB 233.00, CUB-ADM 300.00, CUB-DST 250.00 | CUBAG-42-ab12cd34')
    assert len(text) <= 120


def test_conflicts_are_reported():
    bad = RENEWAL + [{'section': 'variable', 'bank_name': 'NIB', 'account_number': '1110045585101', 'payment_code': 'CUB-ADM'}]
    assert conflicting_codes(bad) == {'CUB-ADM': ['107113005326', '1110045585101']}
    assert conflicting_codes(RENEWAL) == {}


def test_single_purpose_and_old_payments():
    assert code_for_description('CTI course enrolment') == 'CUB-CTI'
    assert code_for_description('Registration fee') == 'CUB-REG'
    assert code_for_description('District clearance') == 'CUB-DST'
    old = codes_for_payment({'amount': '600', 'description': 'Registration Fee'})
    assert old == [{'code': 'CUB-REG', 'amount': 600.0, 'bank_name': 'GCB', 'account_number': '107113005326'}]
    saved = codes_for_payment({'payment_codes': '[{"code": "CUB-SUB", "amount": 10}]'})
    assert saved == [{'code': 'CUB-SUB', 'amount': 10}]


from datetime import date  # noqa: E402

from config.payment_codes import settlement_summary  # noqa: E402


def test_settlement_summary_by_bank_and_code():
    rows = [
        {'ref': 'CUBAG-1-a', 'amount': '783', 'day': date(2026, 11, 14), 'via_whitsun': True,
         'payment_codes': code_split(RENEWAL, total=783)},
        {'ref': 'CUBAG-2-b', 'amount': '600', 'day': date(2026, 11, 15), 'via_whitsun': True,
         'description': 'Registration Fee'},
        {'ref': 'BANK-9', 'amount': '500', 'day': date(2026, 11, 15), 'via_whitsun': False},
    ]
    rep = settlement_summary(rows)
    assert rep['whitsun_total'] == 1383.0 and rep['whitsun_count'] == 2
    assert rep['direct_total'] == 500.0 and rep['direct_count'] == 1
    gcb = next(b for b in rep['banks'] if b['bank_name'] == 'GCB')
    assert gcb['total'] == 900.0 and gcb['count'] == 2
    assert [(c['code'], c['total']) for c in gcb['codes']] == [('CUB-ADM', 300.0), ('CUB-REG', 600.0)]
    assert sum(b['total'] for b in rep['banks']) == 1383.0


def test_older_renewal_rebuilt_from_bank_split():
    row = {'amount': '533', 'settlement_distribution': [
        {'bank_name': 'Zenith Bank', 'account_number': '6010309212', 'amount': 233},
        {'bank_name': 'GCB', 'account_number': '107113005326', 'amount': 300},
    ]}
    assert [(c['code'], c['amount']) for c in codes_for_payment(row)] == [('CUB-SUB', 233.0), ('CUB-ADM', 300.0)]


def test_add_on_descriptions():
    assert code_for_description('ID card') == 'CUB-ADM'
    assert code_for_description('Association Cloth') == 'CUB-ADM'
    assert code_for_description('Welfare due (small companies)') == 'CUB-ADM'
