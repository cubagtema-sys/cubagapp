"""
Server-side payment amount validation — never trust client-supplied amounts for catalogued fees.
"""
import logging
import re

logger = logging.getLogger(__name__)

_AMOUNT_TOLERANCE = 0.02
_MUST_VERIFY_KEYWORDS = (
    'registration', 'application', 'package', 'entrance', 'renewal',
    'annual', 'dues', 'cti', 'course', 'training', 'clearing', 'consolidation',
    'licentiate', 'associate', 'membership', 'customs licence', 'customs license',
)


# Money columns are sometimes stored as text with a currency prefix
# (e.g. "GHS 1", "GH₵ 1,000.00"). Strip everything but digits/./- before parsing.
_NON_NUMERIC_RE = re.compile(r'[^0-9.\-]')


def _to_float(value):
    """Coerce a numeric-or-text money value to float. Raises ValueError if no number is present."""
    if value is None:
        raise ValueError('amount is None')
    if isinstance(value, (int, float)):
        return float(value)
    cleaned = _NON_NUMERIC_RE.sub('', str(value).strip())
    if not cleaned or cleaned in ('-', '.', '-.'):
        raise ValueError(f'no numeric value in {value!r}')
    return float(cleaned)


def _close(a, b):
    return abs(_to_float(a) - _to_float(b)) <= _AMOUNT_TOLERANCE


def get_cti_course_amount(cursor, course_name: str) -> float:
    """Resolve CTI / guest course fee from DB. Raises ValueError if fee is not configured."""
    if not cursor:
        raise ValueError("Database cursor required for fee lookup")
    from config.course_payment_policy import strip_course_prefix
    name = strip_course_prefix(course_name or '') or (course_name or '').strip()
    try:
        if name:
            cursor.execute(
                """
                SELECT fee FROM cti_courses
                WHERE deleted_at IS NULL AND is_active = TRUE
                  AND LOWER(title) = LOWER(%s)
                LIMIT 1
                """,
                (name,),
            )
            row = cursor.fetchone()
            if row and row.get('fee') is not None:
                return _to_float(row['fee'])
            cursor.execute(
                """
                SELECT fee FROM cti_courses
                WHERE deleted_at IS NULL AND is_active = TRUE
                  AND LOWER(title) LIKE LOWER(%s)
                ORDER BY id DESC LIMIT 1
                """,
                (f'%{name[:40]}%',),
            )
            row = cursor.fetchone()
            if row and row.get('fee') is not None:
                return _to_float(row['fee'])
        cursor.execute(
            """
            SELECT amount FROM fee_schedules
            WHERE is_active = TRUE
              AND (key ILIKE '%cti%' OR key ILIKE '%course%' OR name ILIKE '%cti%')
            ORDER BY updated_at DESC NULLS LAST LIMIT 1
            """
        )
        row = cursor.fetchone()
        if row and row.get('amount') is not None:
            return _to_float(row['amount'])
    except Exception as e:
        logger.warning('[payment_validation] CTI amount lookup failed: %s', e)
        if isinstance(e, ValueError):
            raise e
    raise ValueError(f"Course fee for '{course_name}' is not configured in database")


def get_hardcopy_certificate_fee(cursor) -> float:
    default = 150.0
    if not cursor:
        return default
    try:
        cursor.execute(
            """
            SELECT amount FROM fee_schedules
            WHERE is_active = TRUE
              AND (key ILIKE '%hardcopy%' OR key ILIKE '%certificate%' OR name ILIKE '%hardcopy%')
            ORDER BY updated_at DESC NULLS LAST LIMIT 1
            """
        )
        row = cursor.fetchone()
        if row and row.get('amount') is not None:
            return _to_float(row['amount'])
    except Exception as e:
        logger.debug('[payment_validation] certificate fee lookup: %s', e)
    return default


def _match_fee_schedule(cursor, description: str):
    desc = (description or '').lower()
    try:
        cursor.execute(
            "SELECT key, name, amount FROM fee_schedules WHERE is_active = TRUE"
        )
        for row in cursor.fetchall():
            name = (row.get('name') or '').lower()
            key = (row.get('key') or '').lower().replace('_', ' ')
            amt = row.get('amount')
            if amt is None:
                continue
            if name and name in desc:
                return _to_float(amt)
            if key and key in desc:
                return _to_float(amt)
    except Exception as e:
        logger.warning('[payment_validation] fee_schedules scan failed: %s', e)
    return None


def _member_registration_fee(cursor, member_id):
    """Resolve a member's registration fee by member type from the admin-set
    fee_schedules. Mirrors routes/documents.py reg_key logic so the amount the
    server charges always matches what the app displayed. Returns float or None.
    """
    try:
        cursor.execute("SELECT member_type FROM members WHERE id = %s", (member_id,))
        m = cursor.fetchone()
        m_type = ((m.get('member_type') or '') if m else '').lower()
        if 'licentiate' in m_type:
            reg_key = 'licentiate_reg_form_fee'
        elif 'associate' in m_type:
            reg_key = 'associate_reg_form_fee'
        else:
            reg_key = 'reg_form_fee'
        cursor.execute(
            "SELECT amount FROM fee_schedules WHERE key = %s AND is_active = TRUE LIMIT 1",
            (reg_key,),
        )
        row = cursor.fetchone()
        if row and row.get('amount') is not None:
            return _to_float(row['amount'])
        cursor.execute(
            "SELECT amount FROM fee_schedules WHERE key IN ('reg_form_fee', 'new_reg_fee') AND is_active = TRUE LIMIT 1"
        )
        row = cursor.fetchone()
        if row and row.get('amount') is not None:
            return _to_float(row['amount'])
    except Exception as e:
        logger.warning('[payment_validation] member registration fee lookup failed: %s', e)
    return None


def _member_package_fee(cursor, member_id):
    """Resolve a member's package fee (new membership dues) by member type / scale / category
    from the admin-set fee_schedules. Mirrors routes/documents.py package_fee_amount logic.
    Returns float or None.
    """
    try:
        cursor.execute(
            "SELECT member_type, member_scale, fee_category FROM members WHERE id = %s",
            (member_id,)
        )
        mem_row = cursor.fetchone()
        m_type_clean = (mem_row.get('member_type') or 'corporate').lower().strip() if mem_row else 'corporate'
        fee_cat = (mem_row.get('fee_category') if mem_row else '') or 'cf_only'
        member_scale = str(mem_row.get('member_scale') or 'sme').lower().strip() if mem_row else 'sme'
        is_large = member_scale in ('large_corporate', 'large', 'corporate')

        cursor.execute("SELECT key, amount FROM fee_schedules WHERE is_active = TRUE")
        sched_map = {r['key']: r for r in cursor.fetchall()}

        def get_fee_amt(key, default_amt=0.0):
            row = sched_map.get(key)
            if row and row.get('amount') is not None:
                return _to_float(row['amount'])
            return default_amt

        if 'licentiate' in m_type_clean:
            sched_row = sched_map.get('licentiate_package')
            if sched_row and sched_row.get('amount') is not None:
                return _to_float(sched_row['amount'])
            return (
                get_fee_amt('licentiate_sub_fee')
                + get_fee_amt('licentiate_vetting_fee')
                + get_fee_amt('licentiate_district_fee')
                + get_fee_amt('licentiate_welfare_dues')
                + get_fee_amt('licentiate_legal_audit_fee')
                + get_fee_amt('licentiate_agm_levy')
            )
        elif 'associate' in m_type_clean:
            sched_row = sched_map.get('associate_package')
            if sched_row and sched_row.get('amount') is not None:
                return _to_float(sched_row['amount'])
            return (
                get_fee_amt('associate_sub_fee')
                + get_fee_amt('associate_vetting_fee')
                + get_fee_amt('associate_district_fee')
                + get_fee_amt('associate_welfare_dues')
                + get_fee_amt('associate_legal_audit_fee')
                + get_fee_amt('associate_agm_levy')
            )
        else:
            if is_large:
                if fee_cat == 'cf_only':
                    schedule_key = 'new_large_cf_only'
                elif fee_cat == 'consolidation':
                    schedule_key = 'new_large_consolidation'
                else:
                    schedule_key = 'new_large_cf_consolidation'
            else:
                if fee_cat == 'cf_only':
                    schedule_key = 'new_cf_only'
                elif fee_cat == 'consolidation':
                    schedule_key = 'new_consolidation'
                else:
                    schedule_key = 'new_cf_consolidation'

            sched_row = sched_map.get(schedule_key)
            if sched_row and sched_row.get('amount') is not None:
                return _to_float(sched_row['amount'])

            sub_amt = get_fee_amt('new_sub_fee')
            vetting_amt = get_fee_amt('new_vetting_fee')
            district_amt = get_fee_amt('new_district_fee')
            cf_amt = get_fee_amt('new_cf_fee')
            consol_amt = get_fee_amt('new_consolidation_fee')

            total = sub_amt + vetting_amt + district_amt
            if is_large:
                if fee_cat == 'cf_consolidation':
                    total += consol_amt + cf_amt
                elif fee_cat == 'consolidation':
                    total += consol_amt
                else:
                    total += cf_amt
            elif fee_cat == 'cf_only':
                total += cf_amt
            elif fee_cat == 'consolidation':
                total += consol_amt
            else:
                total += consol_amt + cf_amt
            return total
    except Exception as e:
        logger.warning('[payment_validation] member package fee lookup failed: %s', e)
    return None


def _renewal_expected_amount(cursor, member_id, comp_app_id=None):
    try:
        if comp_app_id:
            cursor.execute(
                "SELECT payment_amount, amount_paid FROM compliance_applications WHERE id = %s AND member_id = %s",
                (comp_app_id, member_id),
            )
            app = cursor.fetchone()
            if app and app.get('payment_amount') is not None:
                total = float(app['payment_amount'])
                paid = float(app.get('amount_paid') or 0)
                return max(0.0, total - paid)
        cursor.execute(
            """
            SELECT payment_amount, amount_paid FROM compliance_applications
            WHERE member_id = %s AND type = 'renewal'
              AND status NOT IN ('approved', 'completed', 'payment_confirmed')
            ORDER BY id DESC LIMIT 1
            """,
            (member_id,),
        )
        app = cursor.fetchone()
        if app and app.get('payment_amount') is not None:
            total = float(app['payment_amount'])
            paid = float(app.get('amount_paid') or 0)
            return max(0.0, total - paid)
        from routes.auth import get_member_renewal_breakdown
        cursor.execute(
            "SELECT member_scale, fee_category, member_type FROM members WHERE id = %s",
            (member_id,),
        )
        m = cursor.fetchone()
        if m:
            info = get_member_renewal_breakdown(
                m.get('member_scale'), m.get('fee_category'), cursor, m.get('member_type')
            )
            return float(info.get('renewal_fee_amount') or 0)
    except Exception as e:
        logger.warning('[payment_validation] renewal amount: %s', e)
    return None


def validate_member_payment_amount(
    cursor,
    member_id,
    description: str,
    client_amount: float,
    comp_app_id=None,
    is_installment: bool = False,
    installment_number: int = 1,
):
    """
    Returns (server_amount, error_message).
    error_message is set when the payment must be rejected.
    """
    desc_lower = (description or '').lower()
    client_amount = float(client_amount)

    if comp_app_id:
        cursor.execute(
            """
            SELECT id, member_id, payment_amount, amount_paid, allow_installments, min_installment_amount
            FROM compliance_applications WHERE id = %s
            """,
            (comp_app_id,),
        )
        app = cursor.fetchone()
        if not app or str(app.get('member_id')) != str(member_id):
            return None, 'Invalid compliance application.'
        total = float(app.get('payment_amount') or 0)
        paid = float(app.get('amount_paid') or 0)
        remaining = max(0.0, total - paid)
        if is_installment:
            if remaining <= 0:
                return None, 'This bill is already settled.'
            min_inst = float(app.get('min_installment_amount') or 0.0)
            if client_amount > remaining + _AMOUNT_TOLERANCE:
                return None, f'Amount exceeds the remaining balance of GHS {remaining:,.2f}.'
            if min_inst > 0 and client_amount + _AMOUNT_TOLERANCE < min_inst and client_amount + _AMOUNT_TOLERANCE < remaining:
                return None, f'Amount is below the required minimum installment of GHS {min_inst:,.2f}.'
            if client_amount <= 0:
                return None, 'Installment amount must be greater than zero.'
            return client_amount, None
        if remaining > 0 and not _close(client_amount, remaining):
            return None, f'Amount must match the outstanding balance of GHS {remaining:,.2f}.'
        return remaining if remaining > 0 else client_amount, None

    if any(k in desc_lower for k in ('cti', 'course', 'training', 'enroll')):
        expected = get_cti_course_amount(cursor, description)
        if expected and expected > 0:
            if is_installment:
                if client_amount <= 0 or client_amount > expected + _AMOUNT_TOLERANCE:
                    return None, f'Course installment must be between GHS 0.01 and GHS {expected:,.2f}.'
                return client_amount, None
            if not _close(client_amount, expected):
                return expected, None
            return expected, None

    if any(k in desc_lower for k in ('renewal', 'annual dues', 'annual renewal', 'license renewal')):
        expected = _renewal_expected_amount(cursor, member_id, comp_app_id)
        if expected is not None and expected > 0:
            if is_installment:
                if client_amount <= 0 or client_amount > expected + _AMOUNT_TOLERANCE:
                    return None, f'Renewal installment must be between GHS 0.01 and GHS {expected:,.2f}.'
                return client_amount, None
            if not _close(client_amount, expected):
                return None, f'Renewal amount must be GHS {expected:,.2f}.'
            return expected, None

    # Registration fees are member-type specific (Associate / Licentiate / standard
    # each have their own admin-set row). Resolve by member type BEFORE the generic
    # description-substring match, which would otherwise grab the wrong row.
    if any(k in desc_lower for k in ('registration', 'reg form', 'application fee', 'entrance')):
        expected = _member_registration_fee(cursor, member_id)
        if expected is not None and expected > 0:
            if is_installment:
                if client_amount <= 0 or client_amount > expected + _AMOUNT_TOLERANCE:
                    return None, f'Registration installment must be between GHS 0.01 and GHS {expected:,.2f}.'
                return client_amount, None
            return expected, None

    # New membership package / dues fees are member-type specific (Licentiate / Associate / SME / Large).
    # Must be resolved via _member_package_fee BEFORE _MUST_VERIFY_KEYWORDS check.
    if any(k in desc_lower for k in ('new member', 'membership dues', 'package', 'membership package')):
        expected = _member_package_fee(cursor, member_id)
        if expected is not None and expected > 0:
            if is_installment:
                if client_amount <= 0 or client_amount > expected + _AMOUNT_TOLERANCE:
                    return None, f'Installment must be between GHS 0.01 and GHS {expected:,.2f}.'
                return client_amount, None
            if not _close(client_amount, expected):
                return expected, None
            return expected, None

    sched_amt = _match_fee_schedule(cursor, description)
    if sched_amt is not None:
        if is_installment:
            if client_amount <= 0 or client_amount > sched_amt + _AMOUNT_TOLERANCE:
                return None, f'Installment must be between GHS 0.01 and GHS {sched_amt:,.2f}.'
            return client_amount, None
        if not _close(client_amount, sched_amt):
            return sched_amt, None
        return sched_amt, None

    if any(k in desc_lower for k in _MUST_VERIFY_KEYWORDS):
        return None, 'Could not verify this fee against the official schedule. Please contact the Secretariat.'

    return client_amount, None
