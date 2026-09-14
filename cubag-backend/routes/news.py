import requests
import logging
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
import xml.etree.ElementTree as ET
import re
import threading
import time as _time
import feedparser
from bs4 import BeautifulSoup
from utils import log_admin_action, admin_required, sub_admin_required
from config.cache import cache

# Configure logging
logger = logging.getLogger(__name__)

news_bp = Blueprint('news', __name__)

@news_bp.route('/public/bulletins', methods=['GET'])
def get_public_bulletins():
    """Public endpoint returning operational port bulletins managed by admin."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, port_name, code, status, notice, status_color
                FROM port_bulletins
                WHERE deleted_at IS NULL AND is_active = TRUE
                ORDER BY id ASC
                LIMIT 10
            """)
            bulletins = cursor.fetchall()
        return jsonify({'items': bulletins, 'total': len(bulletins)}), 200
    except Exception as e:
        logger.exception("Error in get_public_bulletins: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()

@news_bp.route('/public/feed', methods=['GET'])
def get_public_feed():
    """Public endpoint returning real-time industry news (global RSS + admin blog)."""
    with _cache_lock:
        articles = list(_news_cache) if _news_cache else _MOCK_ARTICLES

    # Also grab latest admin blog posts if any
    try:
        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT title, content as summary, 'CUBAG Official' as source, created_at, image_url
                FROM news_blog
                WHERE deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT 5
            """)
            blogs = cursor.fetchall()
            for b in blogs:
                if hasattr(b.get('created_at'), 'strftime'):
                    b['pubDate'] = b['created_at'].strftime('%d %b %Y')
                articles.insert(0, {
                    'title': b.get('title'),
                    'summary': b.get('summary'),
                    'source': b.get('source', 'CUBAG Official'),
                    'pubDate': b.get('pubDate', 'Recent'),
                    'thumbnail': b.get('image_url', ''),
                    'sourceColor': '#6B3E26',
                })
        conn.close()
    except Exception as e:
        logger.debug("Optional blog merge error: %s", e)

    return jsonify({'items': articles[:20], 'total': len(articles[:20])}), 200

@news_bp.route('/blog', methods=['GET'])
def get_blogs():
    try:
        # Pagination parameters
        try:
            page = max(1, int(request.args.get('page', 1)))
        except Exception:
            page = 1
        try:
            per_page = int(request.args.get('per_page', 20))
        except Exception:
            per_page = 20
        per_page = max(1, min(per_page, 100))
        offset = (page - 1) * per_page

        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM news_blog WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT %s OFFSET %s", (per_page, offset))
            posts = cursor.fetchall()

            # Optional: return pagination metadata
            cursor.execute("SELECT COUNT(*) as total FROM news_blog WHERE deleted_at IS NULL")
            total = cursor.fetchone().get('total', 0)

        return jsonify({
            'items': posts,
            'page': page,
            'per_page': per_page,
            'total': total
        }), 200
    except Exception as e:
        logger.exception("Error in get_blogs: %s", e)
        return jsonify({'error': str(e)}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@news_bp.route('/blog', methods=['POST'])
@sub_admin_required('announcements')
def create_blog():
    data = request.json
    try:
        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO news_blog (title, category, content, image_url, author)
                VALUES (%s, %s, %s, %s, %s) RETURNING id
            """, (
                data.get('title'),
                data.get('category', 'General'),
                data.get('content'),
                data.get('image_url', ''),
                data.get('author', 'CUBAG Admin')
            ))
            new_id = cursor.fetchone()['id']
        conn.commit()
        try:
            from socket_instance import socketio
            socketio.emit('news_updated', {'id': new_id})
        except Exception:
            pass
        return jsonify({'message': 'Blog post created', 'id': new_id}), 201
    except Exception as e:
        if 'conn' in locals():
            conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@news_bp.route('/blog/<int:id>', methods=['DELETE'])
@sub_admin_required('announcements')
def delete_blog(id):
    try:
        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute("UPDATE news_blog SET deleted_at = CURRENT_TIMESTAMP WHERE id = %s", (id,))
        conn.commit()
        try:
            from socket_instance import socketio
            socketio.emit('news_updated', {'id': id, 'deleted': True})
        except Exception:
            pass
        return jsonify({'message': 'Blog post archived'}), 200
    except Exception as e:
        if 'conn' in locals():
            conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        if 'conn' in locals():
            conn.close()

FEED_SOURCES = [
    { 'url': 'https://gcaptain.com/feed/',                  'source': 'gCaptain',            'color': '#FF5000' },
    { 'url': 'https://www.hellenicshippingnews.com/feed/',  'source': 'Hellenic Shipping',   'color': '#1a6b3c' },
    { 'url': 'https://splash247.com/feed/',                 'source': 'Splash247',           'color': '#0066cc' },
    { 'url': 'https://www.ship-technology.com/feed/',       'source': 'Ship Technology',     'color': '#c0392b' },
    { 'url': 'https://www.freightwaves.com/news/feed',      'source': 'FreightWaves',        'color': '#003580' },
]

HEADERS = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}

def _parse_feed(source_config):
    """Fetch and parse one RSS feed, returning a list of article dicts."""
    results = []
    try:
        # Increase timeout slightly and handle errors more gracefully
        # Enforce TLS verification; do not disable certificate checks
        res = requests.get(source_config['url'], headers=HEADERS, timeout=12, verify=True)
        if not res.ok:
            logger.warning(f"Feed server returned {res.status_code} for {source_config['source']}")
            return results

        # Clean up XML string to prevent encoding errors
        content = res.content.decode('utf-8', errors='replace')
        # Some feeds have leading whitespace
        content = content.strip()

        try:
            root = ET.fromstring(content)
            for item in root.findall('./channel/item')[:10]:
                title_el     = item.find('title')
                link_el      = item.find('link')
                pubdate_el   = item.find('pubDate')
                desc_el      = item.find('description')
                content_el   = item.find('{http://purl.org/rss/1.0/modules/content/}encoded')
                media_el     = item.find('{http://search.yahoo.com/mrss/}thumbnail')
                media_cont   = item.find('{http://search.yahoo.com/mrss/}content')

                t_str    = (title_el.text   or '').strip()  if title_el   is not None else ''
                l_str    = (link_el.text    or '').strip()  if link_el    is not None else ''
                d_str    = (pubdate_el.text or '').strip()  if pubdate_el is not None else ''
                desc_str = (desc_el.text    or '').strip()  if desc_el    is not None else ''
                c_str    = (content_el.text or desc_str)    if content_el is not None else desc_str

                thumbnail = ''
                if media_el is not None and media_el.get('url'):
                    thumbnail = media_el.get('url')
                elif media_cont is not None and media_cont.get('url'):
                    thumbnail = media_cont.get('url')
                elif c_str:
                    img_match = re.search(r'<img[^>]+src=["\']([^"\'> ]+)', c_str)
                    if img_match:
                        thumbnail = img_match.group(1)

                clean_desc = re.sub(r'<[^>]+>', '', desc_str).strip()

                try:
                    from email.utils import parsedate_to_datetime
                    pub_ts = parsedate_to_datetime(d_str).timestamp() if d_str else 0
                except Exception:
                    pub_ts = 0

                results.append({
                    'title':       t_str,
                    'link':        l_str,
                    'pubDate':     d_str,
                    'pub_ts':      pub_ts,
                    'description': clean_desc,
                    'thumbnail':   thumbnail,
                    'source':      source_config['source'],
                    'sourceColor': source_config.get('color', '#3b82f6'),
                })
        except Exception as xml_err:
            logger.warning(f"ET.fromstring failed for [{source_config['source']}]: {xml_err}; falling back to feedparser.")
            parsed = feedparser.parse(content)
            for entry in parsed.entries[:10]:
                t_str = entry.get('title', '').strip()
                l_str = entry.get('link', '').strip()
                d_str = entry.get('published', '') or entry.get('updated', '')
                desc_str = entry.get('summary', '') or entry.get('description', '')
                clean_desc = re.sub(r'<[^>]+>', '', desc_str).strip()

                thumbnail = ''
                if 'media_thumbnail' in entry and entry.media_thumbnail:
                    thumbnail = entry.media_thumbnail[0].get('url', '')
                elif 'media_content' in entry and entry.media_content:
                    thumbnail = entry.media_content[0].get('url', '')
                elif desc_str:
                    img_match = re.search(r'<img[^>]+src=["\']([^"\'> ]+)', desc_str)
                    if img_match:
                        thumbnail = img_match.group(1)

                try:
                    from email.utils import parsedate_to_datetime
                    pub_ts = parsedate_to_datetime(d_str).timestamp() if d_str else 0
                except Exception:
                    pub_ts = 0

                results.append({
                    'title':       t_str,
                    'link':        l_str,
                    'pubDate':     d_str,
                    'pub_ts':      pub_ts,
                    'description': clean_desc,
                    'thumbnail':   thumbnail,
                    'source':      source_config['source'],
                    'sourceColor': source_config.get('color', '#3b82f6'),
                })
    except Exception as e:
        logger.error(f"Feed error [{source_config['source']}]: {e}")
    return results

# ─── In-memory news cache ─────────────────────────────────────────────────────
_news_cache = []
_cache_lock = threading.Lock()
_cache_populated = threading.Event()

# Fallback articles if all feeds fail
_MOCK_ARTICLES = [
    {
        'title': 'CUBAG Digital Platform Optimization Complete',
        'link': 'https://cubag.org',
        'pubDate': 'Wed, 03 Jun 2026 08:00:00 GMT',
        'description': 'The Secretariat is pleased to announce the successful migration of our enterprise platform to Flutter, providing enhanced performance and mobile support for all members.',
        'thumbnail': '',
        'source': 'CUBAG Official',
        'sourceColor': '#FF5000',
    },
    {
        'title': 'West Africa Maritime Traffic Overview',
        'link': 'https://cubag.org',
        'pubDate': 'Wed, 03 Jun 2026 07:30:00 GMT',
        'description': 'Maritime activity in the Gulf of Guinea remains steady. Member firms are advised to monitor live vessel movements via the CUBAG Intelligence Hub.',
        'thumbnail': '',
        'source': 'Logistics Hub',
        'sourceColor': '#1a6b3c',
    }
]

def _refresh_cache():
    """Fetch all feeds and update the in-memory cache."""
    logger.info("[NewsCache] Refreshing feeds...")
    all_items = []

    # Try fetching from real sources
    for s in FEED_SOURCES:
        try:
            feed_items = _parse_feed(s)
            if feed_items:
                all_items.extend(feed_items)
                logger.info(f"[NewsCache] Fetched {len(feed_items)} items from {s['source']}")
        except Exception as e:
            logger.error(f"[NewsCache] Feed error [{s['source']}]: {e}")

    # Sort by timestamp
    all_items.sort(key=lambda x: x.get('pub_ts', 0), reverse=True)

    # Remove timestamp field before caching
    for item in all_items:
        item.pop('pub_ts', None)

    with _cache_lock:
        global _news_cache
        if all_items:
            _news_cache = all_items[:40]
            logger.info(f"[NewsCache] Refreshed with {len(_news_cache)} real articles.")
        else:
            # Fallback to mock data if all feeds failed
            _news_cache = _MOCK_ARTICLES
            logger.warning("[NewsCache] All feeds failed. Using mock fallback data.")

    _cache_populated.set()

def _cache_worker():
    """Background daemon that refreshes the cache every 15 minutes."""
    while True:
        try:
            _refresh_cache()
        except Exception as e:
            logger.error(f"[NewsCache] Worker error: {e}")
        _time.sleep(900)  # 15 minutes

def start_news_worker():
    """Start the background worker thread."""
    worker = threading.Thread(target=_cache_worker, daemon=True, name='news-cache-worker')
    worker.start()
    logger.info("[NewsCache] Background worker started.")

@news_bp.route('/global', methods=['GET'])
@cache.cached(timeout=300)
def get_global_news():
    """Return cached news — refreshed by background thread."""
    # Don't block — if cache isn't ready yet, return mock articles immediately.
    # The client can refresh after a few seconds to get real data.
    if not _cache_populated.is_set():
        logger.info("[NewsCache] Cache not ready yet, returning mock fallback.")
        return jsonify(_MOCK_ARTICLES), 200

    with _cache_lock:
        articles = list(_news_cache)

    if not articles:
        return jsonify(_MOCK_ARTICLES), 200
    return jsonify(articles), 200

@news_bp.route('/proxy-image', methods=['GET'])
def proxy_image():
    url = request.args.get('url')
    if not url:
        return jsonify({'message': 'URL required'}), 400
    try:
        r = requests.get(url, stream=True, timeout=10)
        if r.status_code == 200:
            from flask import Response
            return Response(r.iter_content(chunk_size=10*1024), content_type=r.headers.get('content-type'))
        return jsonify({'message': 'Failed to fetch image'}), r.status_code
    except Exception as e:
        return jsonify({'message': str(e)}), 500

@news_bp.route('/test/refresh', methods=['POST'])
@sub_admin_required('announcements')
def trigger_refresh():
    """Admin endpoint to manually trigger a news refresh."""
    threading.Thread(target=_refresh_cache, daemon=True).start()
    return jsonify({'message': 'Refresh triggered in background'}), 200


# ─────────────────────────────────────────────
#  ADMIN PORT BULLETINS / PORT NEWS CRUD
# ─────────────────────────────────────────────

@news_bp.route('/admin/bulletins', methods=['GET'])
@sub_admin_required('announcements')
def get_admin_bulletins():
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, port_name, code, status, notice, status_color, is_active, created_at
                FROM port_bulletins
                WHERE deleted_at IS NULL
                ORDER BY id ASC
            """)
            bulletins = cursor.fetchall()
            for b in bulletins:
                if hasattr(b.get('created_at'), 'isoformat'):
                    b['created_at'] = b['created_at'].isoformat()
        return jsonify({'items': bulletins, 'total': len(bulletins)}), 200
    except Exception as e:
        logger.exception("Error in get_admin_bulletins: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@news_bp.route('/admin/bulletins', methods=['POST'])
@sub_admin_required('announcements')
def create_admin_bulletin():
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    port_name = (data.get('port_name') or '').strip()
    notice = (data.get('notice') or '').strip()
    if not port_name:
        return jsonify({'message': 'Port name is required'}), 400
    if not notice:
        return jsonify({'message': 'Port operational notice is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO port_bulletins (port_name, code, status, notice, status_color, is_active)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id, port_name, code, status, notice, status_color, is_active
            """, (
                port_name,
                data.get('code', 'GHA'),
                data.get('status', 'Operational'),
                notice,
                data.get('status_color', '#2E7D32'),
                data.get('is_active', True)
            ))
            new_bulletin = cursor.fetchone()
            conn.commit()
        log_admin_action(admin_id, 'Created Port Bulletin', 'bulletin', new_bulletin['id'], port_name)
        try:
            from socket_instance import socketio
            socketio.emit('bulletins_updated', {'id': new_bulletin['id']})
        except Exception:
            pass
        return jsonify({'message': 'Port bulletin created successfully', 'bulletin': new_bulletin}), 201
    except Exception as e:
        conn.rollback()
        logger.exception("Error creating port bulletin: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@news_bp.route('/admin/bulletins/<int:bulletin_id>', methods=['PUT'])
@sub_admin_required('announcements')
def update_admin_bulletin(bulletin_id):
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE port_bulletins
                SET port_name = COALESCE(NULLIF(%s, ''), port_name),
                    code = COALESCE(%s, code),
                    status = COALESCE(%s, status),
                    notice = COALESCE(%s, notice),
                    status_color = COALESCE(%s, status_color),
                    is_active = COALESCE(%s, is_active)
                WHERE id = %s AND deleted_at IS NULL
                RETURNING id, port_name, code, status, notice, status_color, is_active
            """, (
                data.get('port_name'),
                data.get('code'),
                data.get('status'),
                data.get('notice'),
                data.get('status_color'),
                data.get('is_active'),
                bulletin_id
            ))
            updated = cursor.fetchone()
            if not updated:
                return jsonify({'message': 'Port bulletin not found'}), 404
            conn.commit()
        log_admin_action(admin_id, 'Updated Port Bulletin', 'bulletin', bulletin_id, updated['port_name'])
        try:
            from socket_instance import socketio
            socketio.emit('bulletins_updated', {'id': bulletin_id})
        except Exception:
            pass
        return jsonify({'message': 'Port bulletin updated successfully', 'bulletin': updated}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error updating port bulletin: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@news_bp.route('/admin/bulletins/<int:bulletin_id>', methods=['DELETE'])
@sub_admin_required('announcements')
def delete_admin_bulletin(bulletin_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("UPDATE port_bulletins SET deleted_at = CURRENT_TIMESTAMP WHERE id = %s RETURNING port_name", (bulletin_id,))
            res = cursor.fetchone()
            if not res:
                return jsonify({'message': 'Port bulletin not found'}), 404
            conn.commit()
        log_admin_action(admin_id, 'Archived Port Bulletin', 'bulletin', bulletin_id, res['port_name'])
        try:
            from socket_instance import socketio
            socketio.emit('bulletins_updated', {'id': bulletin_id, 'deleted': True})
        except Exception:
            pass
        return jsonify({'message': 'Port bulletin archived successfully'}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error deleting port bulletin: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
