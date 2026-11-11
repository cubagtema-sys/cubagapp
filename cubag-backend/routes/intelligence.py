import copy
import json
import logging
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from config.db import get_db
from utils import sub_admin_required
from config.cache import cache

logger = logging.getLogger(__name__)

intelligence_bp = Blueprint('intelligence', __name__)

DEFAULT_DATA = {
    "ports": [
        {"port": "Tema Port",     "status": "High (4 Days)",    "color": "#ef4444"},
        {"port": "Takoradi Port", "status": "Low (1 Day)",      "color": "#10b981"},
        {"port": "Lagos, Apapa",  "status": "Severe (8+ Days)", "color": "#ef4444"},
        {"port": "Abidjan Port",  "status": "Moderate (2 Days)","color": "#f59e0b"}
    ],
    "bunkers": [
        {"loc": "Singapore", "price": "$630.50", "change": "-1.2%", "up": False},
        {"loc": "Rotterdam", "price": "$595.00", "change": "+0.8%", "up": True},
        {"loc": "Houston",   "price": "$612.25", "change": "+0.4%", "up": True}
    ],
    "alerts": [
        {"id": 1, "title": "Red Sea Shipping Disruptions",
         "detail": "Major shipping lines continue to reroute vessels around the Cape of Good Hope, adding 10-14 days to transit.",
         "severity": "high"},
        {"id": 2, "title": "Panama Canal Transit Limits",
         "detail": "Water levels stabilizing; daily transit limits remain in effect causing minor delays for East Coast-bound cargo.",
         "severity": "medium"}
    ],
    "forex": {
        "USD": "15.45",
        "EUR": "16.80",
        "GBP": "19.50",
        "CNY": "2.15"
    }
}

SETTING_KEY = 'intelligence_data'


# Response-only fields; never stored.
META_KEYS = ('is_sample', 'sample_sections', 'updated_at')


def _with_meta(data, updated_at=None):
    """Mark every section that is still the built-in placeholder (BUG-10/IOS-15).

    A section counts as sample when its value equals DEFAULT_DATA, whether it
    came from the fallback or was saved back unchanged by the admin page.
    """
    out = copy.deepcopy(data)
    for k in META_KEYS:
        out.pop(k, None)
    sample = [k for k, v in DEFAULT_DATA.items() if out.get(k, v) == v]
    for k in sample:
        out.setdefault(k, copy.deepcopy(DEFAULT_DATA[k]))
    out['sample_sections'] = sample
    out['is_sample'] = 'forex' in sample
    out['updated_at'] = updated_at.isoformat() if hasattr(updated_at, 'isoformat') else updated_at
    return out


def load_data():
    """Load from DB platform_settings table, fall back to (labelled) defaults."""
    try:
        conn = get_db()
        try:
            with conn.cursor() as cursor:
                cursor.execute(
                    "SELECT config_value, updated_at FROM platform_settings WHERE config_key = %s",
                    (SETTING_KEY,)
                )
                row = cursor.fetchone()
            if row and row.get('config_value'):
                data = row['config_value']
                if isinstance(data, str):
                    try:
                        data = json.loads(data)
                    except Exception:
                        data = None
                if isinstance(data, dict):
                    return _with_meta(data, row.get('updated_at'))
        finally:
            conn.close()
    except Exception as e:
        logger.exception("[intelligence] DB load failed: %s", e)
    return _with_meta({})


def save_data(data):
    """Upsert intelligence data into DB platform_settings table."""
    data = {k: v for k, v in (data or {}).items() if k not in META_KEYS}
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO platform_settings (config_key, config_value)
                VALUES (%s, %s)
                ON CONFLICT (config_key) DO UPDATE SET config_value = EXCLUDED.config_value, updated_at = CURRENT_TIMESTAMP
            """, (SETTING_KEY, json.dumps(data)))
            conn.commit()
    finally:
        conn.close()


@intelligence_bp.route('/', methods=['GET'])
@cache.cached(timeout=120)  # Cache for 2 minutes
def get_intelligence():
    return jsonify(load_data()), 200


@intelligence_bp.route('/', methods=['POST'])
@sub_admin_required('intelligence')
def update_intelligence():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"message": "Expected a JSON object"}), 400
    save_data(data)
    cache.clear()  # Invalidate intelligence cache on update
    return jsonify({"message": "Intelligence data updated successfully"}), 200
