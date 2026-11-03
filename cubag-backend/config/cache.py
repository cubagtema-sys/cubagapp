import os
import logging
import threading
from flask_caching import Cache

logger = logging.getLogger(__name__)

# Mutex to protect cache recalculation against thundering-herd / stampede on cache miss
cache_single_flight_lock = threading.Lock()

redis_url = os.getenv('REDIS_URL') or os.getenv('UPSTASH_REDIS_REST_URL')

if redis_url and redis_url.startswith(('redis://', 'rediss://')):
    cache_config = {
        'CACHE_TYPE': 'RedisCache',
        'CACHE_REDIS_URL': redis_url,
        'CACHE_DEFAULT_TIMEOUT': 120,
        'CACHE_KEY_PREFIX': 'cubag_',
        'CACHE_OPTIONS': {
            'socket_timeout': 3,
            'socket_connect_timeout': 3,
            'retry_on_timeout': True
        }
    }
    logger.info("[CACHE] Initializing production RedisCache with URL: %s", redis_url[:12] + '...')
else:
    cache_config = {
        'CACHE_TYPE': 'SimpleCache',
        'CACHE_DEFAULT_TIMEOUT': 120,
        'CACHE_THRESHOLD': 1000
    }
    logger.info("[CACHE] Initializing thread-safe in-memory SimpleCache")

cache = Cache(config=cache_config)
