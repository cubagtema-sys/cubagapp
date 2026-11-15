"""Payment codes: tell WhitsunPay which CUBAG bank account each part of a
payment settles into.

Every payment lands in CUBAG's one WhitsunPay merchant account. The
narration starts with the payment code(s) and the amount for each, e.g.
``CUB-SUB 233.00, CUB-ADM 300.00, CUB-DST 250.00 | CUBAG-42-ab12cd34``, and
WhitsunPay settles each amount to the account registered for that code.

The list of codes is data, not code: admins edit it in Admin > Fees >
Payment codes (stored as platform setting ``cubag_payment_codes``). Each
entry has a code, what it is for, ONE bank account, the fee types it is the
default for, and words that identify payments with no fee breakdown.
``DEFAULT_CATALOGUE`` below is only the starting list.

A fee may carry its own ``payment_code``; otherwise the code whose account
matches the fee's account (and whose fee types include the fee's) is used.
"""
import json
import re
from decimal import ROUND_HALF_UP, Decimal

SETTING_KEY = 'cubag_payment_codes'
NARRATION_MAX = 120
CODE_PATTERN = re.compile(r'^[A-Z0-9][A-Z0-9-]{1,19}$')
FALLBACK_CODE = 'CUB-OTH'

# Starting list. For payments with no fee breakdown, the longest matching word
# in a payment's purpose picks the code.
DEFAULT_CATALOGUE = [
    {'code': 'CUB-CTI', 'label': 'Training Institute courses', 'bank_name': 'NIB',
     'account_number': '1110045585101', 'sections': ['cti'], 'keywords': ['cti', 'course', 'training'], 'active': True},
    {'code': 'CUB-CPD', 'label': 'CPD and refresher courses', 'bank_name': 'NIB',
     'account_number': '1110045585101', 'sections': ['national', 'variable'], 'keywords': ['cpd', 'refresher'], 'active': True},
    {'code': 'CUB-DST', 'label': 'District registration, clearance and welfare', 'bank_name': 'Ecobank',
     'account_number': '1441002452360', 'sections': [], 'keywords': ['district', 'clearance'], 'active': True},
    {'code': 'CUB-SUB', 'label': 'Subscription and development levy', 'bank_name': 'Zenith Bank',
     'account_number': '6010309212', 'sections': [], 'keywords': ['subscription', 'levy'], 'active': True},
    {'code': 'CUB-REG', 'label': 'New member registration (registration, vetting, C&F fee, cloth)', 'bank_name': 'GCB',
     'account_number': '107113005326', 'sections': ['new_membership', 'new_reg', 'corporate'],
     'keywords': ['registration', 'onboarding', 'new member', 'vetting'], 'active': True},
    {'code': 'CUB-GST', 'label': 'Public and guest services', 'bank_name': 'GCB',
     'account_number': '107113005326', 'sections': ['guest'], 'keywords': ['guest', 'public'], 'active': True},
    {'code': 'CUB-ADM', 'label': 'Administrative, legal and audit, welfare and other charges', 'bank_name': 'GCB',
     'account_number': '107113005326', 'sections': ['national', 'district', 'variable'],
     'keywords': ['renewal', 'annual', 'dues', 'admin', 'legal', 'audit', 'welfare', 'consolidation', 'card',
                  'badge', 'cloth', 'bond'], 'active': True},
    {'code': 'CUB-OTH', 'label': 'Other payments', 'bank_name': 'GCB',
     'account_number': '107113005326', 'sections': [], 'keywords': [], 'active': True},
]


# ── The code list ─────────────────────────────────────────────────────────────

def clean_entry(e):
    """Normalise one code entry from the admin screen."""
    def words(v):
        if isinstance(v, str):
            v = v.split(',')
        return [str(x).strip().lower() for x in (v or []) if str(x).strip()]
    return {
        'code': str(e.get('code') or '').strip().upper(),
        'label': str(e.get('label') or '').strip(),
        'bank_name': str(e.get('bank_name') or '').strip(),
        'account_number': re.sub(r'\s+', '', str(e.get('account_number') or '')),
        'sections': words(e.get('sections')),
        'keywords': words(e.get('keywords')),
        'active': e.get('active', True) is not False,
    }


def validate_catalogue(entries):
    """None when the list can be saved, else a plain message saying why not."""
    if not isinstance(entries, list) or not entries:
        return 'Add at least one payment code.'
    seen = set()
    for raw in entries:
        if not isinstance(raw, dict):
            return 'Each payment code must be a set of fields.'
        e = clean_entry(raw)
        if not CODE_PATTERN.match(e['code']):
            return (f"'{e['code'] or '(empty)'}' is not a valid code. Use 2 to 20 capital letters, "
                    "numbers or hyphens, for example CUB-LEV.")
        if e['code'] in seen:
            return f"The code {e['code']} is listed twice."
        seen.add(e['code'])
        if not e['label']:
            return f"Say what {e['code']} is for."
        if not e['bank_name'] or not e['account_number']:
            return f"{e['code']} needs a bank and an account number: WhitsunPay pays it into that account."
    return None


def load_catalogue(cursor):
    """The saved code list, or the starting list when none is saved yet."""
    try:
        cursor.execute("SELECT config_value FROM platform_settings WHERE config_key = %s", (SETTING_KEY,))
        row = cursor.fetchone()
        val = row and (row.get('config_value') if isinstance(row, dict) else row[0])
        if isinstance(val, str):
            val = json.loads(val)
        if isinstance(val, list) and val:
            return [clean_entry(e) for e in val if isinstance(e, dict)]
    except Exception:
        try:
            cursor.connection.rollback()
        except Exception:
            pass
    return [dict(e) for e in DEFAULT_CATALOGUE]


def _index(catalogue):
    return {e['code']: e for e in (catalogue or DEFAULT_CATALOGUE)}


def code_label(code, catalogue=None):
    e = _index(catalogue).get(code)
    return e['label'] if e else code


def code_account(code, catalogue=None):
    """(bank, account) a code settles into."""
    idx = _index(catalogue)
    e = idx.get(code) or idx.get(FALLBACK_CODE) or next(iter(idx.values()))
    return e['bank_name'], e['account_number']


def _money(v):
    return Decimal(str(v or 0)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


# ── Which code a fee or payment gets ─────────────────────────────────────────

def code_for_item(item, catalogue=None):
    """Code for one fee line: its own payment_code if an admin set one;
    otherwise the active code whose account matches the fee's account (one
    listing the fee's type first), so a default never points at two banks."""
    own = str(item.get('payment_code') or '').strip().upper()
    if own:
        return own
    cat = [e for e in (catalogue or DEFAULT_CATALOGUE) if e.get('active', True)]
    section = str(item.get('section') or '').strip().lower()
    acc = re.sub(r'\s+', '', str(item.get('account_number') or ''))
    bank = str(item.get('bank_name') or '').strip().lower()
    if acc:
        same = [e for e in cat if e['account_number'] == acc]
    elif bank:
        same = [e for e in cat if e['bank_name'].lower() == bank or bank in e['bank_name'].lower()]
    else:
        same = []
    if same:
        for e in same:
            if section and section in e.get('sections', []):
                return e['code']
        # No code lists this fee type: prefer one with no fee types (a catch-all for that account).
        for e in same:
            if not e.get('sections'):
                return e['code']
        return same[0]['code']
    for e in cat:
        if section and section in e.get('sections', []):
            return e['code']
    return FALLBACK_CODE


def code_for_description(description, fee_key=None, catalogue=None):
    """Best code for a payment with no fee breakdown: the code with the
    longest of its words found in the payment's purpose (so a specific new
    code such as 'port levy' beats a general one such as 'levy'); ties go to
    the code listed first."""
    text = f"{fee_key or ''} {description or ''}".lower()
    best, best_len = FALLBACK_CODE, 0
    for e in catalogue or DEFAULT_CATALOGUE:
        if not e.get('active', True):
            continue
        for k in e.get('keywords', []):
            if k and k in text and len(k) > best_len:
                best, best_len = e['code'], len(k)
    return best


def conflicting_codes(fees, catalogue=None):
    """Codes that would settle into more than one account: {code: [accounts]}."""
    seen = {}
    for f in fees or []:
        code = code_for_item(f, catalogue)
        acc = re.sub(r'\s+', '', str(f.get('account_number') or code_account(code, catalogue)[1]))
        seen.setdefault(code, set()).add(acc)
    return {c: sorted(a) for c, a in seen.items() if len(a) > 1}


def fee_code_problem(fees, catalogue):
    """None when every fee's code is in the list and matches its account,
    else a plain message."""
    clashes = conflicting_codes(fees, catalogue)
    if clashes:
        code, accounts = next(iter(clashes.items()))
        return (f'Payment code {code} is set to more than one bank account ({", ".join(accounts)}). '
                'Each code must go to one account. Change the code or the account on one of the fees.')
    idx = _index(catalogue)
    for f in fees or []:
        code = code_for_item(f, catalogue)
        e = idx.get(code)
        label = f.get('label') or 'A fee'
        if not e:
            return (f"{label} uses the payment code {code}, which is not in the list. "
                    'Add it under Payment codes first.')
        if not e.get('active', True):
            return f"{label} uses the payment code {code}, which is switched off."
        acc = re.sub(r'\s+', '', str(f.get('account_number') or ''))
        if acc and acc != e['account_number']:
            return (f"{label} is paid into account {acc}, but its code {code} settles into "
                    f"{e['bank_name']} {e['account_number']}. Use a code for that account.")
    return None


# ── Splitting a payment and the narration ────────────────────────────────────

def code_split(items, total=None, catalogue=None):
    """Group fee lines by (code, account) and return a list of
    {code, amount, bank_name, account_number} whose amounts add up exactly
    to ``total`` (when given). If the lines do not add up to the amount
    charged (a part payment), each code gets its share in proportion."""
    groups = {}
    order = []
    for it in items or []:
        code = code_for_item(it, catalogue)
        dbank, dacc = code_account(code, catalogue)
        bank = it.get('bank_name') or dbank
        acc = re.sub(r'\s+', '', str(it.get('account_number') or dacc))
        key = (code, acc)
        if key not in groups:
            groups[key] = {'code': code, 'amount': Decimal('0'), 'bank_name': bank, 'account_number': acc}
            order.append(key)
        groups[key]['amount'] += _money(it.get('amount'))
    lines = [groups[k] for k in order if groups[k]['amount'] > 0]
    if not lines:
        return []
    if total is not None:
        target = _money(total)
        current = sum(l['amount'] for l in lines)
        if current != target and current > 0:
            running = Decimal('0')
            for i, l in enumerate(lines):
                if i == len(lines) - 1:
                    l['amount'] = target - running
                else:
                    l['amount'] = (l['amount'] * target / current).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
                    running += l['amount']
    return [{**l, 'amount': float(l['amount'])} for l in lines]


def single_code(code, amount, catalogue=None):
    bank, acc = code_account(code, catalogue)
    return [{'code': code, 'amount': float(_money(amount)), 'bank_name': bank, 'account_number': acc}]


def narration(codes, reference, purpose=''):
    """Text sent to WhitsunPay: codes and amounts first (never cut), then the
    reference, then as much of the purpose as fits."""
    parts = ', '.join(f"{c['code']} {_money(c['amount'])}" for c in codes) or FALLBACK_CODE
    text = f"{parts} | {reference}"
    if purpose:
        room = NARRATION_MAX - len(text) - 3
        if room > 8:
            text += ' | ' + purpose[:room]
    return text


def codes_for_payment(row, catalogue=None):
    """Codes for a stored payment: saved codes, else rebuilt from its saved
    bank split or its description (payments made before codes existed)."""
    saved = row.get('payment_codes')
    if isinstance(saved, str):
        try:
            saved = json.loads(saved)
        except ValueError:
            saved = None
    if saved:
        return saved
    amount = row.get('amount') or 0
    dist = row.get('settlement_distribution')
    if isinstance(dist, str):
        try:
            dist = json.loads(dist)
        except ValueError:
            dist = None
    if isinstance(dist, list) and dist:
        # Older renewals saved only their split by bank: one line per bank.
        lines = [{'bank_name': d.get('bank_name'), 'account_number': d.get('account_number'),
                  'amount': d.get('amount'), 'section': 'national'} for d in dist if isinstance(d, dict)]
        split = code_split(lines, total=amount, catalogue=catalogue)
        if split:
            return split
    return single_code(code_for_description(row.get('description'), catalogue=catalogue), amount, catalogue)


def codes_for_new_payment(cursor, member_id, amount, description, kind=None, comp_app_id=None):
    """Work out the codes for a payment about to be sent to WhitsunPay.

    Renewal bills: each bill line is matched by name to its fee (to learn its
    bank). New-member packages: the new-member fees. Anything else: one code
    from the payment's purpose. Amounts always add up to ``amount``.
    """
    catalogue = load_catalogue(cursor)

    def fee_lookup():
        items = []
        try:
            cursor.execute("SELECT config_value FROM platform_settings WHERE config_key = 'cubag_fees_v2'")
            row = cursor.fetchone()
            val = row and (row.get('config_value') if isinstance(row, dict) else row[0])
            if isinstance(val, str):
                val = json.loads(val)
            if isinstance(val, list):
                items.extend(v for v in val if isinstance(v, dict))
        except Exception:
            pass
        try:
            from routes.auth import get_member_renewal_breakdown
            cursor.execute(
                "SELECT member_scale, fee_category, member_type, port_of_operation FROM members WHERE id = %s",
                (member_id,),
            )
            m = cursor.fetchone()
            if m:
                ren = get_member_renewal_breakdown(
                    m.get('member_scale'), m.get('fee_category'), cursor, m.get('member_type'),
                    m.get('port_of_operation'), member_id=member_id)
                items.extend(ren.get('renewal_fee_breakdown') or [])
                items.extend(ren.get('variable_fee_options') or [])
                return items, ren
        except Exception:
            pass
        return items, None

    desc = (description or '').lower()
    if kind == 'course' or 'cti' in desc or 'course' in desc:
        return single_code(code_for_description('cti course', catalogue=catalogue), amount, catalogue)

    is_renewal = kind == 'renewal' or any(k in desc for k in ('renewal', 'dues', 'annual', 'bill'))
    if is_renewal or comp_app_id:
        known, ren = fee_lookup()
        by_label = {str(i.get('label') or '').strip().lower(): i for i in known if i.get('label')}
        lines = []
        if comp_app_id:
            try:
                cursor.execute("SELECT fee_breakdown FROM compliance_applications WHERE id = %s", (comp_app_id,))
                row = cursor.fetchone()
                raw = row and (row.get('fee_breakdown') if isinstance(row, dict) else row[0])
                lines = json.loads(raw) if isinstance(raw, str) and raw.strip() else (raw or [])
            except Exception:
                lines = []
        if not lines and ren:
            lines = ren.get('renewal_fee_breakdown') or []
        matched = []
        for ln in lines if isinstance(lines, list) else []:
            if not isinstance(ln, dict):
                continue
            label = str(ln.get('label') or '').strip()
            fee = by_label.get(label.lower(), {})
            item = {**fee, **{k: v for k, v in ln.items() if v not in (None, '')}}
            if not item.get('bank_name') and not item.get('payment_code') and not item.get('section'):
                item['payment_code'] = code_for_description(label, catalogue=catalogue)
            matched.append(item)
        split = code_split(matched, total=amount, catalogue=catalogue)
        if split:
            return split
        return single_code(code_for_description('renewal', catalogue=catalogue), amount, catalogue)

    if kind in ('package', 'registration'):
        known, _ = fee_lookup()
        new_fees = [f for f in known if str(f.get('section') or '').lower() in ('new_membership', 'new_reg')]
        if kind == 'package' and new_fees:
            split = code_split(new_fees, total=amount, catalogue=catalogue)
            if split:
                return split
        return single_code(code_for_description('registration', catalogue=catalogue), amount, catalogue)

    # One fee paid on its own: use that fee's own code and bank when we can find it.
    known, _ = fee_lookup()
    want = (description or '').strip().lower()
    for f in known:
        if str(f.get('label') or '').strip().lower() == want:
            split = code_split([f], total=amount, catalogue=catalogue)
            if split:
                return split
    return single_code(code_for_description(description, catalogue=catalogue), amount, catalogue)


def settlement_summary(rows, catalogue=None):
    """Totals for a settlement report.

    rows: dicts with amount, description, payment_codes (may be empty), day
    (date), via_whitsun (bool). Returns banks (with per-code totals), days and
    overall totals. Only WhitsunPay payments need settling; bank deposits and
    office payments already reached CUBAG's accounts and are counted apart.
    """
    banks, days = {}, {}
    total = Decimal('0')
    direct = Decimal('0')
    count = direct_count = 0
    for r in rows:
        amt = _money(r.get('amount'))
        if not r.get('via_whitsun'):
            direct += amt
            direct_count += 1
            continue
        total += amt
        count += 1
        for c in codes_for_payment(r, catalogue):
            code = c.get('code') or FALLBACK_CODE
            dbank, dacc = code_account(code, catalogue)
            bank = c.get('bank_name') or dbank
            acc = str(c.get('account_number') or dacc)
            part = _money(c.get('amount'))
            b = banks.setdefault(acc, {'bank_name': bank, 'account_number': acc, 'total': Decimal('0'), 'payments': set(), 'codes': {}})
            b['total'] += part
            b['payments'].add(r.get('ref') or id(r))
            cd = b['codes'].setdefault(code, {'code': code, 'label': code_label(code, catalogue), 'total': Decimal('0'), 'count': 0})
            cd['total'] += part
            cd['count'] += 1
            day = str(r.get('day'))
            dk = (day, code, acc)
            d = days.setdefault(dk, {'date': day, 'code': code, 'bank_name': bank, 'account_number': acc, 'total': Decimal('0'), 'count': 0})
            d['total'] += part
            d['count'] += 1
    out_banks = []
    for b in sorted(banks.values(), key=lambda x: -x['total']):
        out_banks.append({
            'bank_name': b['bank_name'], 'account_number': b['account_number'],
            'total': float(b['total']), 'count': len(b['payments']),
            'codes': [{**c, 'total': float(c['total'])} for c in sorted(b['codes'].values(), key=lambda x: x['code'])],
        })
    out_days = [{**d, 'total': float(d['total'])} for d in sorted(days.values(), key=lambda x: (x['date'], x['code']))]
    return {
        'whitsun_total': float(total), 'whitsun_count': count,
        'direct_total': float(direct), 'direct_count': direct_count,
        'banks': out_banks, 'days': out_days,
    }
