"""
Simple IP-based rate limiting using Flask-Caching (no extra dependency).
"""
import logging
from functools import wraps
from flask import request, jsonify
from config.cache import cache

logger = logging.getLogger(__name__)


def _client_ip():
    forwarded = request.headers.get('X-Forwarded-For', '')
    if forwarded:
        return forwarded.split(',')[0].strip()
    return request.remote_addr or '127.0.0.1'


def rate_limit(scope: str, max_requests: int, window_seconds: int):
    """Reject with 429 when the same IP exceeds max_requests within window_seconds."""

    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            if request.method == 'OPTIONS':
                return fn(*args, **kwargs)
            ip = _client_ip()
            key = f'rl_{scope}_{ip}'
            try:
                count = cache.get(key)
                if count is None:
                    cache.set(key, 1, timeout=window_seconds)
                elif int(count) >= max_requests:
                    return jsonify({
                        'message': 'Too many requests. Please wait a moment and try again.'
                    }), 429
                else:
                    cache.set(key, int(count) + 1, timeout=window_seconds)
            except Exception as e:
                logger.debug('[rate_limit] cache error (allowing request): %s', e)
            return fn(*args, **kwargs)

        return wrapper

    return decorator
