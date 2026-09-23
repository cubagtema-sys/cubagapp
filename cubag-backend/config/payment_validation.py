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
    name = (course_name or '').strip()
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

    sched_amt = _match_fee_schedule(cursor, description)
    if sched_amt is not None:
        if not _close(client_amount, sched_amt):
            return sched_amt, None
        return sched_amt, None

    if any(k in desc_lower for k in _MUST_VERIFY_KEYWORDS):
        return None, 'Could not verify this fee against the official schedule. Please contact the Secretariat.'

    return client_amount, None
