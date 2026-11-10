"""
CTI course payment policy (approved owner decision, Nov 2026).

On the iOS app, ONLINE and HYBRID CTI courses must not start any in-app
payment (no MoMo prompt, no bank-slip submission, no checkout). Course details
and enrolment status stay visible. IN-PERSON courses keep in-app payment.
Android and web are unaffected.

Rules are enforced here on the server; the Flutter UI also hides the controls,
but the server must not rely on that.

The mobile app identifies its platform with the ``X-Client-Platform`` header
(``ios`` / ``android`` / ``web``). Requests without the header are treated as
not-iOS so already-installed Android builds and the web portal keep working.

User-facing wording is deliberately neutral: it must not point users to an
external website or another way to pay (Apple anti-steering rules).
"""
import re

from flask import request

PLATFORM_HEADER = 'X-Client-Platform'

COURSE_PAYMENT_UNAVAILABLE_CODE = 'COURSE_PAYMENT_UNAVAILABLE_IN_APP'
COURSE_PAYMENT_UNAVAILABLE_MESSAGE = 'In-app payment is not available for this course.'

_COURSE_PREFIXES = re.compile(
    r'^\s*(cti\s*course|cubag\s*cti|accredited\s*customs\s*training|cti\s*training|cti|course)\s*[:\-–]\s*',
    re.I,
)
_COURSE_KEYWORDS = ('cti', 'course', 'training', 'enrol', 'enroll')


def client_platform() -> str:
    try:
        return (request.headers.get(PLATFORM_HEADER) or '').strip().lower()
    except Exception:
        return ''


def normalize_mode(raw) -> str:
    """Map free-text course modes to 'online' | 'hybrid' | 'in_person' | 'unknown'."""
    m = re.sub(r'[\s_\-]+', ' ', str(raw or '')).strip().lower()
    if not m:
        return 'unknown'
    if 'hybrid' in m or 'blended' in m:
        return 'hybrid'
    if any(k in m for k in ('online', 'virtual', 'remote', 'e learning', 'elearning', 'zoom', 'webinar')):
        return 'online'
    if any(k in m for k in ('in person', 'inperson', 'physical', 'on site', 'onsite', 'classroom', 'face to face')):
        return 'in_person'
    return 'unknown'


def strip_course_prefix(text: str) -> str:
    return _COURSE_PREFIXES.sub('', str(text or '')).strip()


def looks_like_course_payment(description: str = '', meta=None, service_type: str = '') -> bool:
    meta = meta if isinstance(meta, dict) else {}
    if str(meta.get('type') or '').lower() in ('cti_course', 'course', 'cti_training'):
        return True
    if meta.get('course_id'):
        return True
    if str(service_type or '').lower() in ('cti_training', 'cti_course', 'course'):
        return True
    d = str(description or '').lower()
    return any(k in d for k in _COURSE_KEYWORDS)


def resolve_course(cursor, course_id=None, title_or_description: str = ''):
    """Return {'id','title','mode'} for the course, or None if it can't be identified."""
    if course_id:
        try:
            cursor.execute(
                "SELECT id, title, mode FROM cti_courses WHERE id = %s AND deleted_at IS NULL",
                (int(course_id),),
            )
            row = cursor.fetchone()
            if row:
                return row
        except (TypeError, ValueError):
            pass
    title = strip_course_prefix(title_or_description)
    if title:
        cursor.execute(
            "SELECT id, title, mode FROM cti_courses WHERE deleted_at IS NULL AND LOWER(title) = LOWER(%s) "
            "ORDER BY id DESC LIMIT 1",
            (title,),
        )
        row = cursor.fetchone()
        if row:
            return row
        cursor.execute(
            "SELECT id, title, mode FROM cti_courses WHERE deleted_at IS NULL AND LOWER(title) LIKE LOWER(%s) "
            "ORDER BY id DESC LIMIT 1",
            (f'%{title[:60]}%',),
        )
        return cursor.fetchone()
    return None


def in_app_payment_allowed(mode, platform: str = None) -> bool:
    platform = client_platform() if platform is None else platform
    if platform != 'ios':
        return True
    return normalize_mode(mode) == 'in_person'


def course_payment_block(cursor, *, course_id=None, description='', meta=None, service_type='', platform=None):
    """Return a (json_body, status) tuple if this course payment must be refused, else None.

    Only ever blocks iOS clients, and only for course payments. If an iOS course
    payment can't be matched to a course we refuse it (we can't prove it is
    in-person) rather than risk a policy violation.
    """
    platform = client_platform() if platform is None else platform
    if platform != 'ios':
        return None
    meta = meta if isinstance(meta, dict) else {}
    if not looks_like_course_payment(description, meta, service_type):
        return None
    course = resolve_course(cursor, course_id or meta.get('course_id'),
                            meta.get('course_title') or description)
    if course and normalize_mode(course.get('mode')) == 'in_person':
        return None
    return ({
        'message': COURSE_PAYMENT_UNAVAILABLE_MESSAGE,
        'error_code': COURSE_PAYMENT_UNAVAILABLE_CODE,
        'in_app_payment_available': False,
    }, 403)


def annotate_course(course: dict, platform: str = None) -> dict:
    """Add delivery_mode + in_app_payment_available to a course dict (for the app UI)."""
    mode = normalize_mode(course.get('mode'))
    course['delivery_mode'] = mode
    course['in_app_payment_available'] = in_app_payment_allowed(course.get('mode'), platform)
    return course
