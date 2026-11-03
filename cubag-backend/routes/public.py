import os
import logging
import json
from datetime import datetime, date
from flask import Blueprint, jsonify, request
from config.db import get_db
from config.cache import cache, cache_single_flight_lock
from config.rate_limit import rate_limit
from routes.members import get_public_members, get_public_ports, verify_member_public
from routes.news import get_public_feed, get_public_bulletins
from routes.events_surveys import get_public_events, get_public_courses, get_public_gallery, get_public_active_surveys
from routes.complaints import submit_complaint, track_complaint
from routes.payments import verify_receipt_public

logger = logging.getLogger(__name__)

public_bp = Blueprint('public', __name__)


@public_bp.route('/portal-summary', methods=['GET'])
@rate_limit('portal_summary', max_requests=60, window_seconds=60)
def get_portal_summary():
    """
    Consolidated public homepage endpoint for external websites.
    Caches aggregated stats, latest news, circulars, events, CTI cohorts,
    operating ports, and official Bank of Ghana indicative exchange rates for 60 seconds.
    Single-flight lock protected against database thundering-herd spikes on cache miss.
    """
    cache_key = 'public_portal_summary_payload'
    try:
        cached_data = cache.get(cache_key)
        if cached_data is not None:
            resp = jsonify(cached_data)
            resp.headers['X-Cache'] = 'HIT'
            resp.headers['Cache-Control'] = 'public, max-age=60'
            resp.headers['Access-Control-Allow-Origin'] = '*'
            return resp, 200
    except Exception as e:
        logger.debug("Cache lookup failed: %s", e)

    # Acquire mutex lock to ensure single-flight regeneration across threads
    with cache_single_flight_lock:
        # Re-check cache inside lock in case a parallel thread just completed it
        try:
            cached_data = cache.get(cache_key)
            if cached_data is not None:
                resp = jsonify(cached_data)
                resp.headers['X-Cache'] = 'HIT'
                resp.headers['Cache-Control'] = 'public, max-age=60'
                resp.headers['Access-Control-Allow-Origin'] = '*'
                return resp, 200
        except Exception:
            pass

        conn = get_db()
        try:
            with conn.cursor() as cursor:
                # 1. Official Member & Operations Stats
                cursor.execute("""
                    SELECT 
                        COUNT(*) FILTER (WHERE LOWER(COALESCE(status, '')) IN ('active', 'approved') 
                                          AND LOWER(COALESCE(role, 'member')) NOT IN ('admin', 'super_admin', 'sub_admin', 'staff', 'system')) as active_members,
                        COUNT(DISTINCT license_number) FILTER (WHERE license_number IS NOT NULL AND license_number != '') as licensed_brokers
                    FROM members
                """)
                mem_stats = cursor.fetchone() or {}

                cursor.execute("SELECT COUNT(*) as count FROM ports_of_operation WHERE is_active = TRUE")
                port_row = cursor.fetchone() or {}
                port_count = port_row.get('count', 0) if isinstance(port_row, dict) else 0

                cursor.execute("SELECT COUNT(*) as count FROM cti_courses WHERE deleted_at IS NULL AND is_active = TRUE")
                course_row = cursor.fetchone() or {}
                course_count = course_row.get('count', 0) if isinstance(course_row, dict) else 0

                stats = {
                    'active_members': mem_stats.get('active_members', 0),
                    'licensed_brokers': mem_stats.get('licensed_brokers', 0),
                    'operating_ports': port_count or 6,
                    'cti_courses': course_count or 0,
                }

                # 2. Exchange Rates — genuinely pulled from Bank of Ghana platform_settings
                cursor.execute("SELECT config_value, updated_at FROM platform_settings WHERE config_key = 'intelligence_data'")
                row = cursor.fetchone()
                forex = {}
                updated_dt = None
                if row:
                    raw_cfg = row.get('config_value')
                    if isinstance(raw_cfg, str):
                        try:
                            raw_cfg = json.loads(raw_cfg)
                        except Exception:
                            raw_cfg = {}
                    if isinstance(raw_cfg, dict):
                        forex = raw_cfg.get('forex', {})
                    updated_dt = row.get('updated_at')

                usd = float(forex['USD']) if 'USD' in forex and str(forex['USD']).replace('.', '', 1).isdigit() else None
                eur = float(forex['EUR']) if 'EUR' in forex and str(forex['EUR']).replace('.', '', 1).isdigit() else None
                gbp = float(forex['GBP']) if 'GBP' in forex and str(forex['GBP']).replace('.', '', 1).isdigit() else None
                cny = float(forex['CNY']) if 'CNY' in forex and str(forex['CNY']).replace('.', '', 1).isdigit() else None

                exchange_rates = {
                    'usd_ghs': usd,
                    'eur_ghs': eur,
                    'gbp_ghs': gbp,
                    'cny_ghs': cny,
                    'source': 'Bank of Ghana Indicative Rates',
                    'effective_date': updated_dt.isoformat() if hasattr(updated_dt, 'isoformat') and updated_dt else date.today().isoformat(),
                }

                # 3. Latest Official News & Press Releases (Top 4)
                cursor.execute("""
                    SELECT id, title, content as summary, image_url, created_at
                    FROM news_blog
                    WHERE deleted_at IS NULL
                    ORDER BY created_at DESC
                    LIMIT 4
                """)
                news_rows = cursor.fetchall() or []
                latest_news = []
                for n in news_rows:
                    created_at = n.get('created_at')
                    pub_date = created_at.isoformat() if isinstance(created_at, (datetime, date)) else str(created_at or '')
                    latest_news.append({
                        'id': n.get('id'),
                        'title': n.get('title') or '',
                        'summary': n.get('summary') or '',
                        'image_url': n.get('image_url') or '',
                        'source': 'CUBAG Official Press',
                        'published_at': pub_date,
                    })

                # 4. Port Operational Bulletins (Top 4)
                cursor.execute("""
                    SELECT id, port_name, code, status, notice, status_color
                    FROM port_bulletins
                    WHERE deleted_at IS NULL AND is_active = TRUE
                    ORDER BY id ASC
                    LIMIT 4
                """)
                bulletins = cursor.fetchall() or []

                # 5. Upcoming Industry Events (Top 3)
                cursor.execute("""
                    SELECT id, title, description, date, time, location, capacity
                    FROM events
                    WHERE deleted_at IS NULL
                    ORDER BY 
                        CASE WHEN date >= CURRENT_DATE THEN 0 ELSE 1 END ASC,
                        CASE WHEN date >= CURRENT_DATE THEN date END ASC,
                        date DESC
                    LIMIT 3
                """)
                events_rows = cursor.fetchall() or []
                upcoming_events = []
                for ev in events_rows:
                    d = ev.get('date')
                    upcoming_events.append({
                        'id': ev.get('id'),
                        'title': ev.get('title') or '',
                        'description': ev.get('description') or '',
                        'date': d.isoformat() if isinstance(d, (datetime, date)) else str(d or ''),
                        'time': str(ev.get('time') or ''),
                        'location': ev.get('location') or 'Tema Port / Accra',
                        'capacity': ev.get('capacity'),
                    })

                # 6. Featured CTI Courses & Upcoming Cohorts (Top 4)
                cursor.execute("""
                    SELECT id, title, start_date, duration, mode, fee, description
                    FROM cti_courses
                    WHERE deleted_at IS NULL AND is_active = TRUE
                    ORDER BY id ASC
                    LIMIT 4
                """)
                course_rows = cursor.fetchall() or []
                cti_courses = []
                for c in course_rows:
                    sd = c.get('start_date')
                    fee_val = c.get('fee')
                    try:
                        fee_num = float(fee_val) if fee_val is not None else 0.0
                    except (ValueError, TypeError):
                        fee_num = 0.0

                    cti_courses.append({
                        'id': c.get('id'),
                        'title': c.get('title') or '',
                        'start_date': str(sd or 'Upcoming Cohort'),
                        'duration': c.get('duration') or '4 Weeks',
                        'mode': c.get('mode') or 'In-Person / Online',
                        'fee': fee_num,
                        'currency': 'GHS',
                        'cohort_status': 'Enrollment Open',
                        'description': c.get('description') or '',
                        'accredited': True,
                    })

                # 7. Operating Ports
                cursor.execute("""
                    SELECT id, name, code
                    FROM ports_of_operation
                    WHERE is_active = TRUE
                    ORDER BY name ASC
                """)
                ports = cursor.fetchall() or []
                if not ports:
                    ports = [
                        {'id': 1, 'name': 'Tema Port', 'code': 'TMP'},
                        {'id': 2, 'name': 'Takoradi Port', 'code': 'TKD'},
                        {'id': 3, 'name': 'Accra International Airport', 'code': 'ACC'},
                        {'id': 4, 'name': 'Aflao Border Port', 'code': 'AFL'},
                        {'id': 5, 'name': 'Elubo Border Port', 'code': 'ELB'},
                        {'id': 6, 'name': 'Paga Border Port', 'code': 'PAG'},
                    ]

                payload = {
                    'success': True,
                    'stats': stats,
                    'exchange_rates': exchange_rates,
                    'latest_news': latest_news,
                    'bulletins': bulletins,
                    'upcoming_events': upcoming_events,
                    'cti_courses': cti_courses,
                    'ports': ports,
                    'timestamp': datetime.utcnow().isoformat() + 'Z',
                }

                try:
                    cache.set(cache_key, payload, timeout=60)
                except Exception as e:
                    logger.debug("Cache write failed: %s", e)

                resp = jsonify(payload)
                resp.headers['X-Cache'] = 'MISS'
                resp.headers['Cache-Control'] = 'public, max-age=60'
                resp.headers['Access-Control-Allow-Origin'] = '*'
                return resp, 200

        except Exception as e:
            logger.exception("Error in get_portal_summary: %s", e)
            return jsonify({
                'success': False,
                'message': 'Unable to assemble portal summary',
                'error': str(e)
            }), 500
        finally:
            conn.close()


@public_bp.route('/stats', methods=['GET'])
@rate_limit('public_stats', max_requests=60, window_seconds=60)
def get_public_stats():
    """Returns quick top-level public stats only."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT 
                    COUNT(*) FILTER (WHERE LOWER(COALESCE(status, '')) IN ('active', 'approved') 
                                      AND LOWER(COALESCE(role, 'member')) NOT IN ('admin', 'super_admin', 'sub_admin', 'staff', 'system')) as active_members,
                    COUNT(DISTINCT license_number) FILTER (WHERE license_number IS NOT NULL AND license_number != '') as licensed_brokers
                FROM members
            """)
            mem_stats = cursor.fetchone() or {}

            cursor.execute("SELECT COUNT(*) as count FROM ports_of_operation WHERE is_active = TRUE")
            port_row = cursor.fetchone() or {}
            port_count = port_row.get('count', 0) if isinstance(port_row, dict) else 0

            cursor.execute("SELECT COUNT(*) as count FROM cti_courses WHERE deleted_at IS NULL AND is_active = TRUE")
            course_row = cursor.fetchone() or {}
            course_count = course_row.get('count', 0) if isinstance(course_row, dict) else 0

            resp = jsonify({
                'success': True,
                'active_members': mem_stats.get('active_members', 0),
                'licensed_brokers': mem_stats.get('licensed_brokers', 0),
                'operating_ports': port_count or 6,
                'cti_courses': course_count or 0,
            })
            resp.headers['Access-Control-Allow-Origin'] = '*'
            resp.headers['Cache-Control'] = 'public, max-age=120'
            return resp, 200
    except Exception as e:
        logger.exception("Error in get_public_stats: %s", e)
        return jsonify({'success': False, 'active_members': 0, 'licensed_brokers': 0, 'operating_ports': 6, 'cti_courses': 0}), 200
    finally:
        conn.close()


# ── Unified Developer Convenience Aliases Under /api/v1/public/* ──
@public_bp.route('/members', methods=['GET'])
def public_members_alias():
    return get_public_members()

@public_bp.route('/ports', methods=['GET'])
def public_ports_alias():
    return get_public_ports()

@public_bp.route('/verify-member', methods=['GET'])
def public_verify_member_alias():
    return verify_member_public()

@public_bp.route('/verify-receipt', methods=['GET'])
def public_verify_receipt_alias():
    return verify_receipt_public()

@public_bp.route('/news', methods=['GET'])
def public_news_alias():
    return get_public_feed()

@public_bp.route('/bulletins', methods=['GET'])
def public_bulletins_alias():
    return get_public_bulletins()

@public_bp.route('/events', methods=['GET'])
def public_events_alias():
    return get_public_events()

@public_bp.route('/courses', methods=['GET'])
def public_courses_alias():
    return get_public_courses()

@public_bp.route('/gallery', methods=['GET'])
def public_gallery_alias():
    return get_public_gallery()

@public_bp.route('/surveys', methods=['GET'])
def public_surveys_alias():
    return get_public_active_surveys()

@public_bp.route('/complaints', methods=['POST'])
def public_complaint_submit_alias():
    return submit_complaint()

@public_bp.route('/complaints/track/<complaint_id>', methods=['GET'])
def public_complaint_track_alias(complaint_id):
    return track_complaint(complaint_id)

@public_bp.route('/openapi.json', methods=['GET'])
def get_openapi_spec():
    """Returns the OpenAPI 3.0 specification for the CUBAG Public API."""
    try:
        spec_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'static', 'openapi.json')
        with open(spec_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        resp = jsonify(data)
        resp.headers['Access-Control-Allow-Origin'] = '*'
        resp.headers['Cache-Control'] = 'public, max-age=300'
        return resp, 200
    except Exception as e:
        logger.exception("Error loading openapi.json: %s", e)
        return jsonify({'error': 'Failed to load API specification'}), 500

@public_bp.route('/docs', methods=['GET'])
def get_swagger_ui():
    """Interactive Swagger UI Documentation."""
    html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>CUBAG Public REST API Documentation</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css" />
  <link rel="icon" type="image/png" href="https://cubag-api-server.fly.dev/static/favicon.ico" />
  <style>
    body { margin: 0; background: #fafafa; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
    .topbar { display: none !important; }
    .swagger-ui .info .title { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = () => {
      window.ui = SwaggerUIBundle({
        url: '/api/v1/public/openapi.json',
        dom_id: '#swagger-ui',
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        layout: "BaseLayout",
        deepLinking: true,
        showExtensions: true,
        showCommonExtensions: true,
        tryItOutEnabled: true,
        displayRequestDuration: true,
        filter: true
      });
    };
  </script>
</body>
</html>"""
    return html, 200, {'Content-Type': 'text/html; charset=utf-8'}

