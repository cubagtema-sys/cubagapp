"""Payment codes: each code settles into one account; amounts add up exactly."""
from config.payment_codes import (
    DEFAULT_CATALOGUE, clean_entry, code_for_description, code_for_item, code_split, codes_for_payment,
    conflicting_codes, fee_code_problem, narration, validate_catalogue,
)

RENEWAL = [
    {'label': 'Subscription fee (small companies)', 'amount': '233.00', 'section': 'national', 'bank_name': 'Zenith Bank', 'account_number': '6010309212'},
    {'label': 'Administrative fee', 'amount': '200.00', 'section': 'national', 'bank_name': 'GCB', 'account_number': '107113005326'},
    {'label': 'Legal & Audit Fee', 'amount': '100.00', 'section': 'national', 'bank_name': 'GCB', 'account_number': '107113005326'},
    {'label': 'TM District Clearance', 'amount': '250.00', 'section': 'district', 'bank_name': 'Ecobank', 'account_number': '1441002452360'},
]


def test_default_codes_follow_the_bank():
    assert [code_for_item(i) for i in RENEWAL] == ['SUB', 'ADM', 'ADM', 'DST']
    assert code_for_item({'section': 'new_membership', 'bank_name': 'GCB'}) == 'REG'
    assert code_for_item({'section': 'national', 'bank_name': 'NIB'}) == 'CPD'
    assert code_for_item({'section': 'national', 'bank_name': 'GCB', 'payment_code': 'cub-legal'}) == 'LEGAL'


def test_every_default_code_has_one_account():
    assert all(e['account_number'] and e['bank_name'] for e in DEFAULT_CATALOGUE)
    assert validate_catalogue(DEFAULT_CATALOGUE) is None


def test_split_groups_by_code_and_adds_up():
    split = code_split(RENEWAL, total=783)
    assert [(c['code'], c['amount'], c['bank_name']) for c in split] == [
        ('SUB', 233.0, 'Zenith Bank'), ('ADM', 300.0, 'GCB'), ('DST', 250.0, 'Ecobank'),
    ]


def test_part_payment_is_shared_in_proportion_and_exact():
    split = code_split(RENEWAL, total=391.5)
    assert round(sum(c['amount'] for c in split), 2) == 391.5
    assert split[0]['amount'] == 116.5  # 233 / 783 of 391.50


def test_narration_puts_codes_first_and_stays_short():
    text = narration(code_split(RENEWAL, total=783), 'CUBAG-42-ab12cd34', 'Annual Renewal Dues – National & District Clearance')
    assert text.startswith('SUB 233.00, ADM 300.00, DST 250.00 | CUBAG-42-ab12cd34')
    assert len(text) <= 120


def test_conflicts_are_reported():
    bad = RENEWAL + [{'section': 'variable', 'bank_name': 'NIB', 'account_number': '1110045585101', 'payment_code': 'ADM'}]
    assert conflicting_codes(bad) == {'ADM': ['107113005326', '1110045585101']}
    assert conflicting_codes(RENEWAL) == {}


def test_single_purpose_and_old_payments():
    assert code_for_description('CTI course enrolment') == 'CTI'
    assert code_for_description('Registration fee') == 'REG'
    assert code_for_description('District clearance') == 'DST'
    old = codes_for_payment({'amount': '600', 'description': 'Registration Fee'})
    assert old == [{'code': 'REG', 'amount': 600.0, 'bank_name': 'GCB', 'account_number': '107113005326'}]
    saved = codes_for_payment({'payment_codes': '[{"code": "CUB-SUB", "amount": 10}]'})
    assert saved == [{'code': 'SUB', 'amount': 10}]


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
    assert [(c['code'], c['total']) for c in gcb['codes']] == [('ADM', 300.0), ('REG', 600.0)]
    assert sum(b['total'] for b in rep['banks']) == 1383.0


def test_older_renewal_rebuilt_from_bank_split():
    row = {'amount': '533', 'settlement_distribution': [
        {'bank_name': 'Zenith Bank', 'account_number': '6010309212', 'amount': 233},
        {'bank_name': 'GCB', 'account_number': '107113005326', 'amount': 300},
    ]}
    assert [(c['code'], c['amount']) for c in codes_for_payment(row)] == [('SUB', 233.0), ('ADM', 300.0)]


def test_add_on_descriptions():
    assert code_for_description('ID card') == 'ADM'
    assert code_for_description('Association Cloth') == 'ADM'
    assert code_for_description('Welfare due (small companies)') == 'ADM'



# ── The code list is data: admins add codes without a code change ──
NEW = [clean_entry(e) for e in DEFAULT_CATALOGUE] + [clean_entry({
    'code': 'cub-lev', 'label': 'Port levy', 'bank_name': 'Zenith Bank', 'account_number': '6010 309212',
    'sections': 'levy', 'keywords': 'port levy',
})]


def test_admin_added_code_is_used_everywhere():
    assert NEW[-1]['code'] == 'LEV' and NEW[-1]['account_number'] == '6010309212'
    assert code_for_item({'section': 'levy', 'bank_name': 'Zenith Bank', 'account_number': '6010309212'}, NEW) == 'LEV'
    assert code_for_description('Port levy 2027', catalogue=NEW) == 'LEV'
    rep = settlement_summary([{'ref': 'CUBAG-3', 'amount': 50, 'day': date(2026, 11, 15), 'via_whitsun': True,
                               'description': 'Port levy'}], NEW)
    assert rep['banks'][0]['codes'][0]['label'] == 'Port levy'


def test_bad_lists_are_refused():
    assert 'not a valid code' in validate_catalogue([{'code': 'a b', 'label': 'x', 'bank_name': 'GCB', 'account_number': '1'}])
    assert 'listed twice' in validate_catalogue(NEW + [NEW[0]])
    assert 'needs a bank' in validate_catalogue([{'code': 'LEV', 'label': 'x'}])
    assert validate_catalogue([]) == 'Add at least one payment code.'


def test_fee_codes_must_exist_and_match_the_account():
    fee = {'label': 'Port levy', 'payment_code': 'LEV', 'account_number': '6010309212'}
    assert fee_code_problem([fee], NEW) is None
    assert 'not in the list' in fee_code_problem([fee], DEFAULT_CATALOGUE)
    wrong = {**fee, 'account_number': '107113005326'}
    assert 'Use a code for that account' in fee_code_problem([wrong], NEW)
    off = [dict(e, active=False) if e['code'] == 'LEV' else e for e in NEW]
    assert 'switched off' in fee_code_problem([fee], off)
