"""
Simple IP-based rate limiting using Flask-Caching (no extra dependency).
"""
import logging
import os
import time
from functools import wraps
from flask import request, jsonify
from config.cache import cache

logger = logging.getLogger(__name__)

# Number of trusted proxy hops in front of the app (Render's edge proxy = 1).
# The real client IP is the entry that the trusted proxy appended, counting from
# the right. Anything to the left of that is attacker-controlled and must be
# ignored, otherwise rotating X-Forwarded-For bypasses every limit.
_TRUSTED_HOPS = max(1, int(os.getenv('TRUSTED_PROXY_HOPS', '1') or '1'))


def _client_ip():
    forwarded = request.headers.get('X-Forwarded-For', '')
    if forwarded:
        parts = [p.strip() for p in forwarded.split(',') if p.strip()]
        if parts:
            # Take the rightmost IP that a client cannot forge given _TRUSTED_HOPS
            # trusted proxies. With 1 trusted proxy this is the last entry.
            idx = max(0, len(parts) - _TRUSTED_HOPS)
            return parts[idx]
    return request.remote_addr or '127.0.0.1'


def rate_limit(scope: str, max_requests: int, window_seconds: int):
    """Reject with 429 when the same IP exceeds max_requests within a fixed window."""

    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            if request.method == 'OPTIONS':
                return fn(*args, **kwargs)
            ip = _client_ip()
            key = f'rl_{scope}_{ip}'
            try:
                now = time.time()
                rec = cache.get(key)
                if not isinstance(rec, dict) or now - float(rec.get('start', 0)) >= window_seconds:
                    cache.set(key, {'n': 1, 'start': now}, timeout=window_seconds)
                elif int(rec.get('n', 0)) >= max_requests:
                    return jsonify({
                        'message': 'Too many requests. Please wait a moment and try again.'
                    }), 429
                else:
                    rec['n'] = int(rec.get('n', 0)) + 1
                    remaining = window_seconds - (now - float(rec.get('start', now)))
                    cache.set(key, rec, timeout=max(1, int(remaining)))
            except Exception as e:
                logger.debug('[rate_limit] cache error (allowing request): %s', e)
            return fn(*args, **kwargs)

        return wrapper

    return decorator


# ── Per-identifier OTP/reset attempt limiting ─────────────────────────────────
# The IP rate limit above is coarse; a determined attacker can still rotate IPs.
# These helpers bound the number of *wrong code* guesses per email per scope, so
# a 6/8-digit code cannot be brute-forced even if the IP limit is evaded.
# Backed by the same in-process cache (render runs gunicorn with -w 1).

def otp_attempt_limited(scope: str, identifier: str, max_attempts: int = 5) -> bool:
    """True when this identifier has used up its allowed wrong-code guesses."""
    try:
        n = cache.get(f'otp_fail_{scope}_{identifier.lower()}')
        return isinstance(n, int) and n >= max_attempts
    except Exception:
        return False


def record_otp_failure(scope: str, identifier: str, window_seconds: int = 900) -> None:
    """Count one wrong-code guess; auto-expires after window_seconds."""
    key = f'otp_fail_{scope}_{identifier.lower()}'
    try:
        n = cache.get(key)
        n = (n if isinstance(n, int) else 0) + 1
        cache.set(key, n, timeout=window_seconds)
    except Exception as e:
        logger.debug('[otp] failed to record attempt: %s', e)


def clear_otp_failures(scope: str, identifier: str) -> None:
    """Reset the wrong-code counter (on success, or when a fresh code is issued)."""
    try:
        cache.delete(f'otp_fail_{scope}_{identifier.lower()}')
    except Exception:
        pass
