"""Payment codes: tell WhitsunPay which CUBAG bank account each part of a
payment settles into.

Every payment lands in CUBAG's one WhitsunPay merchant account. The
narration starts with the payment code(s) and the amount for each, e.g.
``CUB-SUB 233.00, CUB-ADM 300.00, CUB-DST 250.00 | CUBAG-42-ab12cd34``, and WhitsunPay
settles each amount to the account registered for that code.

Codes come from the fee settings (Admin > Fees). A fee may carry its own
``payment_code``; otherwise its bank (and section) decide.
"""
from decimal import ROUND_HALF_UP, Decimal

# Each code settles into exactly ONE account, so WhitsunPay can route by code.
# Several codes may share an account (finance still sees the type of income).
CODE_LABELS = {
    'CUB-REG': 'New member registration (registration, vetting, C&F fee, cloth)',
    'CUB-SUB': 'Subscription and development levy',
    'CUB-ADM': 'Administrative, legal and audit, welfare and other charges',
    'CUB-DST': 'District registration, clearance and welfare',
    'CUB-CPD': 'CPD and refresher courses',
    'CUB-CTI': 'Training Institute courses',
    'CUB-GST': 'Public and guest services',
    'CUB-OTH': 'Other payments',
}

DEFAULT_ACCOUNTS = {
    'CUB-REG': ('GCB', '107113005326'),
    'CUB-SUB': ('Zenith Bank', '6010309212'),
    'CUB-ADM': ('GCB', '107113005326'),
    'CUB-DST': ('Ecobank', '1441002452360'),
    'CUB-CPD': ('NIB', '1110045585101'),
    'CUB-CTI': ('NIB', '1110045585101'),
    'CUB-GST': ('GCB', '107113005326'),
    'CUB-OTH': ('GCB', '107113005326'),
}

NARRATION_MAX = 120


def _money(v):
    return Decimal(str(v or 0)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def code_for_item(item):
    """Code for one fee line: its own payment_code if an admin set one;
    otherwise worked out from the bank it settles into (and, for GCB, whether
    it is a new-member fee), so a default code never points at two banks."""
    own = str(item.get('payment_code') or '').strip().upper()
    if own:
        return own
    bank = str(item.get('bank_name') or '').lower()
    section = str(item.get('section') or '').strip().lower()
    if 'zenith' in bank:
        return 'CUB-SUB'
    if 'ecobank' in bank:
        return 'CUB-DST'
    if 'nib' in bank or 'national investment' in bank:
        return 'CUB-CTI' if section == 'cti' else 'CUB-CPD'
    if section in ('new_membership', 'new_reg', 'corporate'):
        return 'CUB-REG'
    if section == 'guest':
        return 'CUB-GST'
    if section in ('national', 'district', 'variable') or 'gcb' in bank:
        return 'CUB-ADM'
    return 'CUB-OTH'


def conflicting_codes(fees):
    """Codes that would settle into more than one account: {code: [accounts]}.
    WhitsunPay routes by code, so each code must have exactly one account."""
    seen = {}
    for f in fees or []:
        code = code_for_item(f)
        acc = str(f.get('account_number') or DEFAULT_ACCOUNTS.get(code, ('', ''))[1])
        seen.setdefault(code, set()).add(acc)
    return {c: sorted(a) for c, a in seen.items() if len(a) > 1}


def code_for_description(description, fee_key=None):
    """Best code for a payment with no fee breakdown (one purpose)."""
    text = f"{fee_key or ''} {description or ''}".lower()
    if 'cti' in text or 'course' in text or 'training' in text:
        return 'CUB-CTI'
    if 'cpd' in text or 'refresher' in text:
        return 'CUB-CPD'
    if 'district' in text or 'clearance' in text:
        return 'CUB-DST'
    if 'subscription' in text or 'levy' in text:
        return 'CUB-SUB'
    if 'registration' in text or 'onboarding' in text or 'new member' in text or 'vetting' in text:
        return 'CUB-REG'
    if 'guest' in text or 'public' in text:
        return 'CUB-GST'
    if any(k in text for k in ('renewal', 'annual', 'dues', 'admin', 'legal', 'audit', 'welfare',
                                'consolidation', 'id card', 'card', 'badge', 'cloth', 'bond')):
        return 'CUB-ADM'
    return 'CUB-OTH'


def code_split(items, total=None):
    """Group fee lines by (code, account) and return a list of
    {code, amount, bank_name, account_number} whose amounts add up exactly
    to ``total`` (when given). If the lines do not add up to the amount
    charged (a part payment), each code gets its share in proportion."""
    groups = {}
    order = []
    for it in items or []:
        code = code_for_item(it)
        bank = it.get('bank_name') or DEFAULT_ACCOUNTS.get(code, DEFAULT_ACCOUNTS['CUB-OTH'])[0]
        acc = it.get('account_number') or DEFAULT_ACCOUNTS.get(code, DEFAULT_ACCOUNTS['CUB-OTH'])[1]
        key = (code, str(acc))
        if key not in groups:
            groups[key] = {'code': code, 'amount': Decimal('0'), 'bank_name': bank, 'account_number': str(acc)}
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


def single_code(code, amount):
    bank, acc = DEFAULT_ACCOUNTS.get(code, DEFAULT_ACCOUNTS['CUB-OTH'])
    return [{'code': code, 'amount': float(_money(amount)), 'bank_name': bank, 'account_number': acc}]


def narration(codes, reference, purpose=''):
    """Text sent to WhitsunPay: codes and amounts first (never cut), then the
    reference, then as much of the purpose as fits."""
    parts = ', '.join(f"{c['code']} {_money(c['amount'])}" for c in codes) or 'CUB-OTH'
    text = f"{parts} | {reference}"
    if purpose:
        room = NARRATION_MAX - len(text) - 3
        if room > 8:
            text += ' | ' + purpose[:room]
    return text


def codes_for_payment(row):
    """Codes for a stored payment: saved codes, else rebuilt from its saved
    bank split or description (payments made before codes existed)."""
    saved = row.get('payment_codes')
    if isinstance(saved, str):
        import json
        try:
            saved = json.loads(saved)
        except ValueError:
            saved = None
    if saved:
        return saved
    amount = row.get('amount') or 0
    dist = row.get('settlement_distribution')
    if isinstance(dist, str):
        import json
        try:
            dist = json.loads(dist)
        except ValueError:
            dist = None
    if isinstance(dist, list) and dist:
        # Older renewals saved only their split by bank: one line per bank.
        lines = [{'bank_name': d.get('bank_name'), 'account_number': d.get('account_number'),
                  'amount': d.get('amount'), 'section': 'national'} for d in dist if isinstance(d, dict)]
        split = code_split(lines, total=amount)
        if split:
            return split
    return single_code(code_for_description(row.get('description')), amount)


def codes_for_new_payment(cursor, member_id, amount, description, kind=None, comp_app_id=None):
    """Work out the codes for a payment about to be sent to WhitsunPay.

    Renewal bills: each bill line is matched by name to its fee (to learn its
    bank). New-member packages: the new-member fees. Anything else: one code
    from the payment's purpose. Amounts always add up to ``amount``.
    """
    import json

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
        return single_code('CUB-CTI', amount)

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
                item['payment_code'] = code_for_description(label)
            matched.append(item)
        split = code_split(matched, total=amount)
        if split:
            return split
        return single_code('CUB-ADM', amount)

    if kind in ('package', 'registration'):
        known, _ = fee_lookup()
        new_fees = [f for f in known if str(f.get('section') or '').lower() in ('new_membership', 'new_reg')]
        if kind == 'package' and new_fees:
            split = code_split(new_fees, total=amount)
            if split:
                return split
        return single_code('CUB-REG', amount)

    # One fee paid on its own: use that fee's own code and bank when we can find it.
    known, _ = fee_lookup()
    want = (description or '').strip().lower()
    for f in known:
        if str(f.get('label') or '').strip().lower() == want:
            split = code_split([f], total=amount)
            if split:
                return split
    return single_code(code_for_description(description), amount)


def settlement_summary(rows):
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
        for c in codes_for_payment(r):
            code = c.get('code') or 'CUB-OTH'
            bank = c.get('bank_name') or DEFAULT_ACCOUNTS.get(code, DEFAULT_ACCOUNTS['CUB-OTH'])[0]
            acc = str(c.get('account_number') or DEFAULT_ACCOUNTS.get(code, DEFAULT_ACCOUNTS['CUB-OTH'])[1])
            part = _money(c.get('amount'))
            b = banks.setdefault(acc, {'bank_name': bank, 'account_number': acc, 'total': Decimal('0'), 'payments': set(), 'codes': {}})
            b['total'] += part
            b['payments'].add(r.get('ref') or id(r))
            cd = b['codes'].setdefault(code, {'code': code, 'label': CODE_LABELS.get(code, code), 'total': Decimal('0'), 'count': 0})
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
