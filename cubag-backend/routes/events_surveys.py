import logging
import json
import time
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from config.db import get_db
from utils import admin_required, log_admin_action, sub_admin_required, send_push_notification
from socket_instance import socketio
from config.cache import cache

logger = logging.getLogger(__name__)
events_bp = Blueprint('events', __name__)
surveys_bp = Blueprint('surveys', __name__)

# ─────────────────────────────────────────────
#  PUBLIC EVENTS, MEETINGS, CTI COURSES & GALLERY
# ─────────────────────────────────────────────

@events_bp.route('/public', methods=['GET'])
def get_public_events():
    """Public endpoint for landing page to fetch upcoming events and meetings."""
    event_type = request.args.get('type', 'all').lower()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, title, description, date, time, location, capacity
                FROM events
                WHERE deleted_at IS NULL
                ORDER BY 
                    CASE WHEN date >= CURRENT_DATE THEN 0 ELSE 1 END ASC,
                    CASE WHEN date >= CURRENT_DATE THEN date END ASC,
                    date DESC
                LIMIT 30
            """)
            data = cursor.fetchall()

            for ev in data:
                if hasattr(ev.get('date'), 'isoformat'):
                    ev['date'] = ev['date'].isoformat()
                # Categorize as meeting if title contains meeting, board, committee
                t = (ev.get('title') or '').lower()
                ev['is_meeting'] = any(w in t for w in ['meeting', 'board', 'committee', 'coordination', 'executive'])

            if event_type == 'meeting':
                filtered = [e for e in data if e['is_meeting']]
            elif event_type == 'event':
                filtered = [e for e in data if not e['is_meeting']]
            else:
                filtered = data

        return jsonify({'items': filtered, 'total': len(filtered)}), 200
    except Exception as e:
        logger.exception("Error in get_public_events: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()

@events_bp.route('/public/courses', methods=['GET'])
def get_public_courses():
    """Public endpoint for landing page to fetch active CTI courses."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, title, start_date, duration, mode, fee, description
                FROM cti_courses
                WHERE deleted_at IS NULL AND is_active = TRUE
                ORDER BY id ASC
                LIMIT 10
            """)
            courses = cursor.fetchall()
        return jsonify({'items': courses, 'total': len(courses)}), 200
    except Exception as e:
        logger.exception("Error in get_public_courses: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()

@events_bp.route('/public/gallery', methods=['GET'])
def get_public_gallery():
    """Public endpoint for landing page to fetch active gallery photo items."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, title, category, image_url, grad_start, grad_end
                FROM gallery_items
                WHERE deleted_at IS NULL AND is_active = TRUE
                ORDER BY id ASC
                LIMIT 10
            """)
            items = cursor.fetchall()
        return jsonify({'items': items, 'total': len(items)}), 200
    except Exception as e:
        logger.exception("Error in get_public_gallery: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()

# ─────────────────────────────────────────────
#  MEMBER & ADMIN PROTECTED EVENTS
# ─────────────────────────────────────────────

@events_bp.route('/', methods=['GET'])
@jwt_required()
@cache.cached(timeout=90, query_string=True, key_prefix=lambda: f"events_{request.args.get('status','')}_{request.args.get('include_past','false')}")
def get_events():
    status_filter = request.args.get('status', '').lower()
    include_past = request.args.get('include_past', 'false').lower() == 'true'
    
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            if status_filter == 'past' or include_past:
                cursor.execute("SELECT * FROM events WHERE deleted_at IS NULL AND date < CURRENT_DATE ORDER BY date DESC")
            elif status_filter == 'all':
                cursor.execute("SELECT * FROM events WHERE deleted_at IS NULL ORDER BY date DESC")
            else:
                cursor.execute("SELECT * FROM events WHERE deleted_at IS NULL AND date >= (CURRENT_DATE - INTERVAL '1 day') ORDER BY date ASC")
            data = cursor.fetchall()

            # Ensure dates are stringified
            for ev in data:
                if hasattr(ev.get('date'), 'isoformat'):
                    ev['date'] = ev['date'].isoformat()
                if hasattr(ev.get('created_at'), 'isoformat'):
                    ev['created_at'] = ev['created_at'].isoformat()

        return jsonify({'items': data, 'total': len(data)}), 200
    finally:
        conn.close()

@events_bp.route('/', methods=['POST'])
@sub_admin_required('events')
def create_event():
    # B-17 fix: validate required fields before inserting
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    event_date = (data.get('date') or '').strip()
    if not title:
        return jsonify({'message': 'Event title is required'}), 400
    if not event_date:
        return jsonify({'message': 'Event date is required'}), 400
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO events (title, description, date, time, location, capacity)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (title, data.get('description'), event_date,
                  data.get('time'), data.get('location'), data.get('capacity') or None))
            conn.commit()
        log_admin_action(admin_id, 'Created event', 'event', None, title, f"Date: {event_date}, Location: {data.get('location')}")
        try:
            socketio.emit('events_updated', {'title': title})
        except Exception:
            pass
        return jsonify({'message': 'Event created'}), 201
    except Exception as e:
        conn.rollback()
        logger.error(f'[create_event] {e}')
        return jsonify({'message': 'Failed to create event'}), 500
    finally:
        conn.close()

@events_bp.route('/<int:event_id>', methods=['PUT'])
@sub_admin_required('events')
def update_event(event_id):
    admin_id = get_jwt_identity()
    data = request.get_json()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE events SET title=%s, description=%s, date=%s, time=%s, location=%s, capacity=%s
                WHERE id=%s
            """, (data.get('title'), data.get('description'), data.get('date'),
                  data.get('time'), data.get('location'), data.get('capacity') or None, event_id))
            conn.commit()
        log_admin_action(admin_id, 'Updated event', 'event', event_id, data.get('title'), f"Date: {data.get('date')}")
        try:
            socketio.emit('events_updated', {'id': event_id})
        except Exception:
            pass
        return jsonify({'message': 'Event updated'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/<int:event_id>', methods=['DELETE'])
@sub_admin_required('events')
def delete_event(event_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT title FROM events WHERE id = %s", (event_id,))
            event = cursor.fetchone()
            cursor.execute("UPDATE events SET deleted_at = CURRENT_TIMESTAMP WHERE id = %s", (event_id,))
            conn.commit()
        title = event['title'] if event else f'#{event_id}'
        log_admin_action(admin_id, 'Archived event', 'event', event_id, title)
        try:
            socketio.emit('events_updated', {'id': event_id, 'deleted': True})
        except Exception:
            pass
        return jsonify({'message': 'Event archived'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('events')
def get_all_events_admin():
    try:
        page = max(1, int(request.args.get('page', 1)))
        per_page = int(request.args.get('per_page', 20))
        per_page = max(1, min(per_page, 200))
        offset = (page - 1) * per_page
        event_status = request.args.get('status', 'all').lower()

        where_clause = "WHERE deleted_at IS NULL"
        if event_status == 'upcoming':
            where_clause += " AND date >= (CURRENT_DATE - INTERVAL '1 day')"
        elif event_status == 'history' or event_status == 'past':
            where_clause += " AND date < CURRENT_DATE"

        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute(f"SELECT * FROM events {where_clause} ORDER BY date DESC LIMIT %s OFFSET %s", (per_page, offset))
            data = cursor.fetchall()
            cursor.execute(f"SELECT COUNT(*) as total FROM events {where_clause}")
            total = cursor.fetchone().get('total', 0)

            # Ensure dates are stringified
            for ev in data:
                if hasattr(ev.get('date'), 'isoformat'):
                    ev['date'] = ev['date'].isoformat()
                if hasattr(ev.get('created_at'), 'isoformat'):
                    ev['created_at'] = ev['created_at'].isoformat()

        return jsonify({'data': data, 'page': page, 'per_page': per_page, 'total': total}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@events_bp.route('/<int:event_id>/check-in', methods=['POST'])
@sub_admin_required('events')
def check_in_member(event_id):
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    member_id = data.get('member_id')
    if not member_id:
        return jsonify({'message': 'Member ID is required'}), 400
    
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Verify event exists
            cursor.execute("SELECT title FROM events WHERE id = %s", (event_id,))
            event = cursor.fetchone()
            if not event:
                return jsonify({'message': 'Event not found'}), 404
            
            # Duplicate check
            cursor.execute("SELECT checked_in_at FROM event_attendance WHERE event_id = %s AND member_id = %s", (event_id, member_id))
            if cursor.fetchone():
                cursor.execute("SELECT name, company, profile_photo, license_number FROM members WHERE id = %s", (member_id,))
                member = cursor.fetchone()
                return jsonify({
                    'message': 'Error: This QR code has already been scanned for this event!',
                    'member': member
                }), 400

            # Insert into event_attendance
            cursor.execute("""
                INSERT INTO event_attendance (event_id, member_id)
                VALUES (%s, %s)
            """, (event_id, member_id))
            
            # Fetch member details to return to scanner for visual verification
            cursor.execute("""
                SELECT name, company, profile_photo, license_number
                FROM members WHERE id = %s
            """, (member_id,))
            member = cursor.fetchone()

            conn.commit()
            
            log_admin_action(admin_id, 'Checked in member', 'event', event_id, event['title'], f"Member ID: {member_id}")
            
        return jsonify({
            'message': f'Member #{member_id} checked in successfully',
            'member': member
        }), 200
    except Exception as e:
        conn.rollback()
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/<int:event_id>/attendees', methods=['GET'])
@sub_admin_required('events')
def get_attendees(event_id):
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # We want all members to know who attended and who didn't.
            cursor.execute("""
                SELECT m.id, m.name, m.email, m.company, m.member_type, ea.checked_in_at
                FROM members m
                LEFT JOIN event_attendance ea ON m.id = ea.member_id AND ea.event_id = %s
                ORDER BY ea.checked_in_at DESC NULLS LAST, m.name ASC
            """, (event_id,))
            data = cursor.fetchall()
            for row in data:
                if hasattr(row.get('checked_in_at'), 'isoformat'):
                    row['checked_in_at'] = row['checked_in_at'].isoformat()
        return jsonify({'attendees': data}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─────────────────────────────────────────────
#  SURVEYS
# ─────────────────────────────────────────────

@surveys_bp.route('/public/active', methods=['GET'])
def get_public_active_surveys():
    """Public endpoint for landing page to fetch active surveys open to the public/guests."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT s.id, s.title, s.description, s.type, s.deadline, s.options, s.cover_image, s.target_audience, s.created_at
                FROM surveys s
                WHERE s.deleted_at IS NULL 
                  AND s.active = TRUE 
                  AND (s.deadline IS NULL OR s.deadline >= CURRENT_DATE)
                  AND (s.target_audience IN ('both', 'guests') OR s.target_audience IS NULL)
                ORDER BY s.created_at DESC
                LIMIT 10
            """)
            data = cursor.fetchall()

            for s in data:
                # Parse options
                if isinstance(s.get('options'), str):
                    try:
                        s['options'] = json.loads(s['options'])
                    except (json.JSONDecodeError, ValueError):
                        s['options'] = []
                elif not s.get('options'):
                    s['options'] = []

                if hasattr(s.get('created_at'), 'isoformat'):
                    s['created_at'] = s['created_at'].isoformat()
                if hasattr(s.get('deadline'), 'isoformat'):
                    s['deadline'] = s['deadline'].isoformat()

                # Calculate tallies for this survey
                cursor.execute("""
                    SELECT answers FROM survey_responses WHERE survey_id = %s
                """, (s['id'],))
                responses = cursor.fetchall()
                
                tallies = {}
                total_votes = 0
                total_stars = 0
                star_count = 0
                
                for r in responses:
                    ans = {}
                    try:
                        if isinstance(r.get('answers'), dict):
                            ans = r['answers']
                        elif r.get('answers'):
                            ans = json.loads(r['answers'])
                    except Exception:
                        pass
                    
                    vote = ans.get('vote')
                    if vote is not None:
                        total_votes += 1
                        try:
                            vote_int = int(vote)
                            total_stars += vote_int
                            star_count += 1
                        except (ValueError, TypeError):
                            pass
                        tallies[str(vote)] = tallies.get(str(vote), 0) + 1

                s['total_votes'] = total_votes
                s['tallies'] = tallies
                s['average_stars'] = round(total_stars / star_count, 1) if star_count > 0 else 0

        return jsonify({'items': data, 'total': len(data)}), 200
    except Exception as e:
        logger.exception("Error in get_public_active_surveys: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()

@surveys_bp.route('/public/<int:survey_id>/respond', methods=['POST'])
def submit_public_guest_response(survey_id):
    """Allows guest visitors to respond to a public survey on the landing page."""
    conn = get_db()
    try:
        data = request.get_json() or {}
        answers = data.get('answers', {})
        guest_id = data.get('guest_id') or data.get('guest_identifier') or request.headers.get('X-Forwarded-For') or request.remote_addr
        guest_name = data.get('guest_name')
        guest_email = data.get('guest_email')

        if not answers.get('vote'):
            return jsonify({'message': 'Please select an option to vote'}), 400

        with conn.cursor() as cursor:
            cursor.execute("SELECT active, deadline, target_audience FROM surveys WHERE id = %s AND deleted_at IS NULL", (survey_id,))
            survey = cursor.fetchone()

            if not survey:
                return jsonify({'message': 'Survey not found'}), 404

            if not survey['active']:
                return jsonify({'message': 'This survey is no longer active'}), 400

            if survey.get('target_audience') == 'members':
                return jsonify({'message': 'This survey is restricted to registered members only'}), 403

            if survey['deadline']:
                from datetime import date
                if survey['deadline'] < date.today():
                    return jsonify({'message': 'The deadline for this survey has passed'}), 400

            # Deduplicate or insert guest response
            if guest_id:
                cursor.execute("""
                    SELECT id FROM survey_responses 
                    WHERE survey_id = %s AND guest_identifier = %s AND member_id IS NULL
                """, (survey_id, str(guest_id)))
                existing = cursor.fetchone()
                if existing:
                    cursor.execute("""
                        UPDATE survey_responses
                        SET answers = %s, guest_name = COALESCE(%s, guest_name), guest_email = COALESCE(%s, guest_email), submitted_at = CURRENT_TIMESTAMP
                        WHERE id = %s
                    """, (json.dumps(answers), guest_name, guest_email, existing['id']))
                else:
                    cursor.execute("""
                        INSERT INTO survey_responses (survey_id, member_id, answers, guest_identifier, guest_name, guest_email)
                        VALUES (%s, NULL, %s, %s, %s, %s)
                    """, (survey_id, json.dumps(answers), str(guest_id), guest_name, guest_email))
            else:
                cursor.execute("""
                    INSERT INTO survey_responses (survey_id, member_id, answers, guest_identifier, guest_name, guest_email)
                    VALUES (%s, NULL, %s, %s, %s, %s)
                """, (survey_id, json.dumps(answers), request.remote_addr, guest_name, guest_email))

            conn.commit()

            # Calculate updated tallies to return for instant live UI update
            cursor.execute("SELECT answers FROM survey_responses WHERE survey_id = %s", (survey_id,))
            all_resp = cursor.fetchall()
            tallies = {}
            total_votes = 0
            for r in all_resp:
                ans = {}
                try:
                    if isinstance(r.get('answers'), dict):
                        ans = r['answers']
                    elif r.get('answers'):
                        ans = json.loads(r['answers'])
                except Exception:
                    pass
                v = ans.get('vote')
                if v is not None:
                    total_votes += 1
                    tallies[str(v)] = tallies.get(str(v), 0) + 1

        # Emit real-time update to admin dashboard
        try:
            socketio.emit('survey_update', {'survey_id': survey_id}, room='admin_dashboard')
        except Exception as se:
            logger.warning(f'Socket emit failed: {se}')

        return jsonify({
            'message': 'Your response was submitted successfully! 🎉',
            'tallies': tallies,
            'total_votes': total_votes
        }), 200
    except Exception as e:
        logger.exception("Error in submit_public_guest_response: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@surveys_bp.route('/', methods=['GET'])
@jwt_required()
def get_surveys():
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT s.*, 
                       (CASE WHEN sr.survey_id IS NOT NULL THEN TRUE ELSE FALSE END) as has_responded,
                       sr.answers as my_response_raw,
                       (SELECT COUNT(*) FROM survey_responses WHERE survey_id = s.id) as total_responses
                FROM surveys s
                LEFT JOIN survey_responses sr ON s.id = sr.survey_id AND sr.member_id = %s
                WHERE s.deleted_at IS NULL
                  AND (s.target_audience IN ('both', 'members') OR s.target_audience IS NULL)
                ORDER BY s.created_at DESC
            """, (member_id,))
            data = cursor.fetchall()

            # Collect survey IDs to fetch tallies
            survey_ids = [s['id'] for s in data if s.get('id')]
            tallies_by_survey = {}
            stars_by_survey = {}

            if survey_ids:
                format_strings = ','.join(['%s'] * len(survey_ids))
                cursor.execute(f"""
                    SELECT survey_id, answers
                    FROM survey_responses
                    WHERE survey_id IN ({format_strings})
                """, tuple(survey_ids))
                resp_rows = cursor.fetchall()
                for r in resp_rows:
                    sid = r['survey_id']
                    if sid not in tallies_by_survey:
                        tallies_by_survey[sid] = {}
                        stars_by_survey[sid] = {'sum': 0, 'count': 0}
                    ans = r.get('answers')
                    if isinstance(ans, str):
                        try:
                            ans = json.loads(ans)
                        except Exception:
                            ans = {}
                    if isinstance(ans, dict):
                        v = ans.get('vote')
                        if v is not None:
                            v_str = str(v).strip()
                            tallies_by_survey[sid][v_str] = tallies_by_survey[sid].get(v_str, 0) + 1
                            try:
                                rating_val = int(v_str)
                                stars_by_survey[sid]['sum'] += rating_val
                                stars_by_survey[sid]['count'] += 1
                            except (ValueError, TypeError):
                                pass

            # Parse options JSON string into object and attach tallies
            for s in data:
                sid = s.get('id')
                s['tallies'] = tallies_by_survey.get(sid, {})
                star_data = stars_by_survey.get(sid, {'sum': 0, 'count': 0})
                s['average_rating'] = round(star_data['sum'] / star_data['count'], 1) if star_data['count'] > 0 else 0.0

                my_raw = s.pop('my_response_raw', None)
                my_vote = None
                if my_raw:
                    if isinstance(my_raw, str):
                        try:
                            my_raw = json.loads(my_raw)
                        except Exception:
                            my_raw = {}
                    if isinstance(my_raw, dict):
                        my_vote = my_raw.get('vote')
                s['my_vote'] = my_vote

                if isinstance(s.get('options'), str):
                    try:
                        s['options'] = json.loads(s['options'])
                    except (json.JSONDecodeError, ValueError):
                        s['options'] = []

                if hasattr(s.get('created_at'), 'isoformat'):
                    s['created_at'] = s['created_at'].isoformat()
                if hasattr(s.get('deadline'), 'isoformat'):
                    s['deadline'] = s['deadline'].isoformat()

        return jsonify({'items': data, 'total': len(data)}), 200
    finally:
        conn.close()

@surveys_bp.route('/', methods=['POST'])
@sub_admin_required('events')
def create_survey():
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    conn = get_db()
    try:
        import json as json_lib
        options_json = json_lib.dumps(data.get('options', []))
        target_audience = data.get('target_audience', 'both')
        if target_audience not in ('both', 'members', 'guests'):
            target_audience = 'both'

        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO surveys (title, description, type, deadline, options, cover_image, target_audience, active)
                VALUES (%s, %s, %s, %s, %s, %s, %s, TRUE)
            """, (data.get('title'), data.get('description'), data.get('type', 'survey'),
                  data.get('deadline') or None, options_json, data.get('cover_image'), target_audience))
            conn.commit()
        log_admin_action(admin_id, 'Created survey', 'survey', None, data.get('title'), f"Type: {data.get('type', 'survey')}, Target: {target_audience}")
        return jsonify({'message': 'Survey created'}), 201
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@surveys_bp.route('/<int:survey_id>', methods=['DELETE'])
@sub_admin_required('events')
def delete_survey(survey_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT title FROM surveys WHERE id = %s", (survey_id,))
            survey = cursor.fetchone()
            cursor.execute("UPDATE surveys SET deleted_at = CURRENT_TIMESTAMP WHERE id = %s", (survey_id,))
            conn.commit()
        title = survey['title'] if survey else f'#{survey_id}'
        log_admin_action(admin_id, 'Archived survey', 'survey', survey_id, title)
        return jsonify({'message': 'Survey archived'}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@surveys_bp.route('/<int:survey_id>/toggle-active', methods=['PUT'])
@sub_admin_required('events')
def toggle_survey_active(survey_id):
    """Toggle the active status of a survey (close or reopen)."""
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT title, active FROM surveys WHERE id = %s", (survey_id,))
            survey = cursor.fetchone()
            if not survey:
                return jsonify({'message': 'Survey not found'}), 404
            new_active = not survey['active']
            cursor.execute("UPDATE surveys SET active = %s WHERE id = %s", (new_active, survey_id))
            conn.commit()
        action = 'Reopened survey' if new_active else 'Closed survey'
        log_admin_action(admin_id, action, 'survey', survey_id, survey['title'])
        # Emit real-time update to admin room
        try:
            socketio.emit('survey_update', {'survey_id': survey_id, 'active': new_active}, room='admin_dashboard')
        except Exception as se:
            logger.warning(f'Socket emit failed: {se}')
        return jsonify({'message': action, 'active': new_active}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@surveys_bp.route('/admin/all', methods=['GET'])
@sub_admin_required('events')
def get_all_surveys_admin():
    try:
        page = max(1, int(request.args.get('page', 1)))
        per_page = int(request.args.get('per_page', 20))
        per_page = max(1, min(per_page, 200))
        offset = (page - 1) * per_page
        survey_status = request.args.get('status', 'all').lower()

        where_clause = "WHERE deleted_at IS NULL"
        if survey_status == 'active':
            where_clause += " AND active = TRUE AND (deadline IS NULL OR deadline >= CURRENT_DATE)"
        elif survey_status == 'history':
            where_clause += " AND (active = FALSE OR (deadline IS NOT NULL AND deadline < CURRENT_DATE))"

        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute(f"SELECT * FROM surveys {where_clause} ORDER BY created_at DESC LIMIT %s OFFSET %s", (per_page, offset))
            data = cursor.fetchall()
            cursor.execute(f"SELECT COUNT(*) as total FROM surveys {where_clause}")
            total = cursor.fetchone().get('total', 0)

            # Parse options JSON string into object and ensure date serialization
            for s in data:
                if isinstance(s.get('options'), str):
                    try:
                        s['options'] = json.loads(s['options'])
                    except (json.JSONDecodeError, ValueError):
                        s['options'] = []

                if hasattr(s.get('created_at'), 'isoformat'):
                    s['created_at'] = s['created_at'].isoformat()
                if hasattr(s.get('deadline'), 'isoformat'):
                    s['deadline'] = s['deadline'].isoformat()

        return jsonify({'data': data, 'page': page, 'per_page': per_page, 'total': total}), 200
    except Exception as e:
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@surveys_bp.route('/<int:survey_id>/participation', methods=['GET'])
@sub_admin_required('events')
def get_survey_participation(survey_id):
    """Returns lists of members and guests who have responded to a survey."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # Fetch survey metadata
            cursor.execute("SELECT id, title, target_audience FROM surveys WHERE id = %s", (survey_id,))
            survey_meta = cursor.fetchone()

            # All active members
            cursor.execute("""
                SELECT id, name, email, company, member_type
                FROM members WHERE status = 'active' ORDER BY name ASC
            """)
            all_members = cursor.fetchall()

            # Member responses
            cursor.execute("""
                SELECT member_id, submitted_at, answers
                FROM survey_responses WHERE survey_id = %s AND member_id IS NOT NULL
            """, (survey_id,))
            member_responses = cursor.fetchall()
            responded_ids = {r['member_id']: r for r in member_responses}

            # Guest responses
            cursor.execute("""
                SELECT id, guest_identifier, guest_name, guest_email, submitted_at, answers
                FROM survey_responses 
                WHERE survey_id = %s AND member_id IS NULL
                ORDER BY submitted_at DESC
            """, (survey_id,))
            guest_rows = cursor.fetchall()

        responded = []
        not_responded = []
        guest_responses = []
        
        tallies = {}
        total_stars = 0
        star_count = 0

        # Process member responses
        for m in all_members:
            if m['id'] in responded_ids:
                r_data = responded_ids[m['id']]
                ans = {}
                try:
                    if isinstance(r_data['answers'], dict):
                        ans = r_data['answers']
                    elif r_data['answers']:
                        ans = json.loads(r_data['answers'])
                except Exception as e:
                    logger.debug("Malformed survey answer for member %s: %s", m['id'], e)
                
                vote = ans.get('vote')
                if vote is not None:
                    try:
                        vote_int = int(vote)
                        total_stars += vote_int
                        star_count += 1
                    except (ValueError, TypeError):
                        pass
                    tallies[str(vote)] = tallies.get(str(vote), 0) + 1

                responded.append({**m, 'submitted_at': str(r_data['submitted_at']), 'vote': vote})
            else:
                not_responded.append(m)

        # Process guest responses
        for g in guest_rows:
            g_ans = {}
            try:
                if isinstance(g['answers'], dict):
                    g_ans = g['answers']
                elif g['answers']:
                    g_ans = json.loads(g['answers'])
            except Exception:
                pass
            g_vote = g_ans.get('vote')
            if g_vote is not None:
                try:
                    vote_int = int(g_vote)
                    total_stars += vote_int
                    star_count += 1
                except (ValueError, TypeError):
                    pass
                tallies[str(g_vote)] = tallies.get(str(g_vote), 0) + 1

            guest_responses.append({
                'id': g['id'],
                'guest_identifier': g.get('guest_identifier') or 'Guest Visitor',
                'name': g.get('guest_name') or 'Public Guest',
                'email': g.get('guest_email') or 'Anonymous',
                'vote': g_vote,
                'submitted_at': str(g['submitted_at'])
            })

        total_member_votes = len(responded)
        total_guest_votes = len(guest_responses)
        total_votes = total_member_votes + total_guest_votes

        return jsonify({
            'responded': responded,
            'not_responded': not_responded,
            'guest_responses': guest_responses,
            'member_votes_count': total_member_votes,
            'guest_votes_count': total_guest_votes,
            'total_votes': total_votes,
            'total_members': len(all_members),
            'response_rate': round(total_member_votes / len(all_members) * 100) if all_members else 0,
            'tallies': tallies,
            'average_stars': round(total_stars / star_count, 1) if star_count > 0 else 0,
            'target_audience': survey_meta.get('target_audience', 'both') if survey_meta else 'both'
        }), 200
    except Exception as e:
        logger.exception("Error in get_survey_participation: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@surveys_bp.route('/<int:survey_id>/respond', methods=['POST'])
@jwt_required()
def submit_response(survey_id):
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        data = request.get_json() or {}
        with conn.cursor() as cursor:
            cursor.execute("SELECT active, deadline, target_audience FROM surveys WHERE id = %s AND deleted_at IS NULL", (survey_id,))
            survey = cursor.fetchone()
            
            if not survey:
                return jsonify({'message': 'Survey not found'}), 404
                
            if not survey['active']:
                return jsonify({'message': 'This survey is no longer active'}), 400

            if survey.get('target_audience') == 'guests':
                return jsonify({'message': 'This survey is intended for public guests only'}), 403
                
            if survey['deadline']:
                from datetime import date
                if survey['deadline'] < date.today():
                    return jsonify({'message': 'The deadline for this survey has passed'}), 400
                    
            # Upsert — one response per member per survey
            cursor.execute("""
                INSERT INTO survey_responses (survey_id, member_id, answers)
                VALUES (%s, %s, %s)
                ON CONFLICT (survey_id, member_id) 
                DO UPDATE SET answers = EXCLUDED.answers, submitted_at = CURRENT_TIMESTAMP
            """, (survey_id, member_id, json.dumps(data.get('answers', {}))))
            conn.commit()

        # Emit real-time update to admin room
        try:
            socketio.emit('survey_update', {'survey_id': survey_id}, room='admin_dashboard')
        except Exception as se:
            logger.warning(f'Socket emit failed: {se}')

        return jsonify({'message': 'Response submitted'}), 200
    except Exception as e:
        logger.exception("Error in submit_response: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─────────────────────────────────────────────
#  ADMIN CTI SHORT COURSES CRUD
# ─────────────────────────────────────────────

@events_bp.route('/admin/courses', methods=['GET'])
@sub_admin_required('events')
def get_admin_courses():
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, title, start_date, duration, mode, fee, description, 
                       (is_active AND deleted_at IS NULL) as is_active,
                       (deleted_at IS NOT NULL OR NOT is_active) as is_archived,
                       deleted_at, created_at
                FROM cti_courses
                ORDER BY id ASC
            """)
            courses = cursor.fetchall()
            for c in courses:
                if hasattr(c.get('created_at'), 'isoformat'):
                    c['created_at'] = c['created_at'].isoformat()
                if hasattr(c.get('deleted_at'), 'isoformat'):
                    c['deleted_at'] = c['deleted_at'].isoformat()
        return jsonify({'items': courses, 'total': len(courses)}), 200
    except Exception as e:
        logger.exception("Error in get_admin_courses: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/courses', methods=['POST'])
@sub_admin_required('events')
def create_admin_course():
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    if not title:
        return jsonify({'message': 'Course title is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO cti_courses (title, start_date, duration, mode, fee, description, is_active)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id, title, start_date, duration, mode, fee, description, is_active
            """, (
                title,
                data.get('start_date', ''),
                data.get('duration', ''),
                data.get('mode', 'Hybrid'),
                data.get('fee', 'GHS 1,500'),
                data.get('description', ''),
                data.get('is_active', True)
            ))
            new_course = cursor.fetchone()

            notify_members = data.get('notify_members', True)
            if notify_members and new_course.get('is_active'):
                # 1. Create association announcement
                ann_title = f"🎓 New CTI Course: {title}"
                ann_body = f"The CUBAG Training Institute (CTI) has opened enrollment for '{title}'.\n\n🗓️ Start Date: {new_course['start_date']}\n⏱️ Duration: {new_course['duration']}\n📍 Mode: {new_course['mode']}\n💳 Tariff: {new_course['fee']}\n\nOverview:\n{new_course['description']}\n\nMembers can enrol directly in the CTI Courses tab in the CUBAG App."
                cursor.execute("""
                    INSERT INTO announcements (title, body, category, posted_by, created_at)
                    VALUES (%s, %s, 'Training', 'CUBAG Training Institute Secretariat', NOW())
                """, (ann_title, ann_body))

                # 2. In-app notifications and FCM push notifications
                cursor.execute("SELECT id, fcm_token FROM members WHERE status = 'active'")
                active_members = cursor.fetchall()
                notif_msg = f"Enrollment open for '{title}' starting {new_course['start_date']} ({new_course['duration']}, {new_course['fee']})."
                for m in active_members:
                    cursor.execute("""
                        INSERT INTO notifications (member_id, title, body, category, notification_type)
                        VALUES (%s, %s, %s, 'Training', 'announcement')
                    """, (m['id'], f"🎓 New Course: {title}", notif_msg))
                    if m.get('fcm_token'):
                        try:
                            send_push_notification(m['fcm_token'], f"🎓 New Course: {title}", notif_msg, data={'type': 'cti_new_course', 'course_id': str(new_course['id'])})
                        except Exception:
                            pass

            conn.commit()
        log_admin_action(admin_id, 'Created CTI Course', 'course', new_course['id'], title)
        try:
            socketio.emit('courses_updated', {'id': new_course['id']})
            socketio.emit('announcements_updated', {})
        except Exception:
            pass
        return jsonify({'message': 'Course created and announced successfully', 'course': new_course}), 201
    except Exception as e:
        conn.rollback()
        logger.exception("Error creating course: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/courses/<int:course_id>', methods=['PUT'])
@sub_admin_required('events')
def update_admin_course(course_id):
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            is_act = data.get('is_active')
            cursor.execute("""
                UPDATE cti_courses
                SET title = COALESCE(NULLIF(%s, ''), title),
                    start_date = COALESCE(%s, start_date),
                    duration = COALESCE(%s, duration),
                    mode = COALESCE(%s, mode),
                    fee = COALESCE(%s, fee),
                    description = COALESCE(%s, description),
                    is_active = COALESCE(%s, is_active),
                    deleted_at = CASE WHEN %s = TRUE THEN NULL ELSE deleted_at END
                WHERE id = %s
                RETURNING id, title, start_date, duration, mode, fee, description, is_active
            """, (
                data.get('title'),
                data.get('start_date'),
                data.get('duration'),
                data.get('mode'),
                data.get('fee'),
                data.get('description'),
                is_act,
                is_act,
                course_id
            ))
            updated = cursor.fetchone()
            if not updated:
                return jsonify({'message': 'Course not found'}), 404
            conn.commit()
        log_admin_action(admin_id, 'Updated CTI Course', 'course', course_id, updated['title'])
        try:
            socketio.emit('courses_updated', {'id': course_id})
        except Exception:
            pass
        return jsonify({'message': 'Course updated successfully', 'course': updated}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error updating course: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/courses/<int:course_id>', methods=['DELETE'])
@sub_admin_required('events')
def delete_admin_course(course_id):
    admin_id = get_jwt_identity()
    permanent = request.args.get('permanent', 'false').lower() == 'true'
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            if permanent:
                cursor.execute("DELETE FROM cti_courses WHERE id = %s RETURNING title", (course_id,))
            else:
                cursor.execute("UPDATE cti_courses SET is_active = FALSE, deleted_at = CURRENT_TIMESTAMP WHERE id = %s RETURNING title", (course_id,))
            res = cursor.fetchone()
            if not res:
                return jsonify({'message': 'Course not found'}), 404
            conn.commit()
        log_admin_action(admin_id, 'Permanently Deleted CTI Course' if permanent else 'Archived CTI Course', 'course', course_id, res['title'])
        try:
            socketio.emit('courses_updated', {'id': course_id, 'deleted': True})
        except Exception:
            pass
        return jsonify({'message': 'Course permanently deleted' if permanent else 'Course archived successfully'}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error deleting course: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/courses/<int:course_id>/restore', methods=['POST'])
@sub_admin_required('events')
def restore_admin_course(course_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE cti_courses 
                SET deleted_at = NULL, is_active = TRUE 
                WHERE id = %s 
                RETURNING id, title, start_date, duration, mode, fee, description, is_active
            """, (course_id,))
            res = cursor.fetchone()
            if not res:
                return jsonify({'message': 'Course not found'}), 404
            conn.commit()
        log_admin_action(admin_id, 'Restored CTI Course', 'course', course_id, res['title'])
        try:
            socketio.emit('courses_updated', {'id': course_id, 'restored': True})
        except Exception:
            pass
        return jsonify({'message': 'Course restored successfully', 'course': res}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error restoring course: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


# ─────────────────────────────────────────────
#  MEMBER CTI COURSE ENROLLMENT & TRACKING
# ─────────────────────────────────────────────

@events_bp.route('/courses', methods=['GET'])
@jwt_required(optional=True)
def get_member_courses():
    """Fetch all active CTI courses along with user's enrollment status if logged in."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, title, start_date, duration, mode, fee, description, is_active, created_at
                FROM cti_courses
                WHERE deleted_at IS NULL AND is_active = TRUE
                ORDER BY id ASC
            """)
            courses = cursor.fetchall()

            enrolled_map = {}
            if member_id:
                cursor.execute("""
                    SELECT course_id, id as enrollment_id, status, payment_ref, amount, payment_confirmed_at, created_at
                    FROM cti_course_enrollments
                    WHERE member_id = %s
                """, (member_id,))
                for row in cursor.fetchall():
                    enrolled_map[row['course_id']] = row

            result = []
            for c in courses:
                cid = c['id']
                en = enrolled_map.get(cid)
                c_data = dict(c)
                c_data['is_enrolled'] = en is not None
                c_data['enrollment_status'] = en['status'] if en else None
                c_data['enrollment_id'] = en['enrollment_id'] if en else None
                c_data['payment_ref'] = en['payment_ref'] if en else None
                if en and hasattr(en.get('payment_confirmed_at'), 'isoformat'):
                    c_data['payment_confirmed_at'] = en['payment_confirmed_at'].isoformat()
                result.append(c_data)

            return jsonify({'items': result, 'total': len(result)}), 200
    except Exception as e:
        logger.exception("Error in get_member_courses: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()


@events_bp.route('/courses/<int:course_id>/enroll', methods=['POST'])
@jwt_required()
def enroll_in_course(course_id):
    """Enroll logged-in member into a CTI course with payment."""
    member_id = get_jwt_identity()
    data = request.get_json() or {}
    payment_method = data.get('payment_method', 'momo')
    tx_ref = data.get('payment_ref') or f"CTI-PAY-{int(time.time())}-{member_id}"

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # 1. Verify course exists
            cursor.execute("SELECT id, title, fee, start_date, mode, duration FROM cti_courses WHERE id = %s AND deleted_at IS NULL AND is_active = TRUE", (course_id,))
            course = cursor.fetchone()
            if not course:
                return jsonify({'message': 'Course not found or inactive'}), 404

            # 2. Check if already enrolled
            cursor.execute("SELECT id, status FROM cti_course_enrollments WHERE course_id = %s AND member_id = %s", (course_id, member_id))
            existing = cursor.fetchone()
            if existing:
                return jsonify({'message': 'You are already enrolled in this course', 'enrollment_id': existing['id'], 'status': existing['status']}), 200

            # 3. Parse numeric fee
            fee_str = str(course.get('fee', '0')).replace('GHS', '').replace(',', '').strip()
            try:
                amount = float(fee_str)
            except ValueError:
                amount = 1500.0

            # 4. Insert enrollment
            cursor.execute("""
                INSERT INTO cti_course_enrollments (course_id, member_id, status, payment_method, payment_ref, amount, payment_confirmed_at)
                VALUES (%s, %s, 'enrolled', %s, %s, %s, NOW())
                RETURNING id, course_id, member_id, status, payment_ref, amount, created_at
            """, (course_id, member_id, payment_method, tx_ref, amount))
            enrollment = cursor.fetchone()

            # 5. Insert payment record
            cursor.execute("""
                INSERT INTO payments (member_id, amount, description, status, payment_ref, paid_at, created_at)
                VALUES (%s, %s, %s, 'paid', %s, NOW(), NOW())
            """, (member_id, amount, f"CTI Enrollment: {course['title']} ({course['duration']})", tx_ref))

            # 6. Fetch member name & send in-app notification
            cursor.execute("SELECT name, email, fcm_token FROM members WHERE id = %s", (member_id,))
            member = cursor.fetchone()
            m_name = member['name'] if member else 'Member'
            fcm_token = member['fcm_token'] if member else None

            notif_title = f"🎓 Enrolled: {course['title']}"
            notif_body = f"Congratulations {m_name}! You have successfully enrolled in '{course['title']}' starting on {course['start_date']}. Your syllabus and access details have been generated."

            cursor.execute("""
                INSERT INTO notifications (member_id, title, body, category, notification_type)
                VALUES (%s, %s, %s, 'Training', 'announcement')
            """, (member_id, notif_title, notif_body))

            conn.commit()

            # 7. Push notification
            if fcm_token:
                send_push_notification(fcm_token, notif_title, notif_body, data={'type': 'cti_enrolled', 'course_id': str(course_id)})

            # 8. Email Acknowledgement & Official Receipt
            try:
                from routes.payments import _send_receipt_email
                if member and member.get('email'):
                    schedule_msg = f"<p><strong>CTI Course Schedule:</strong> Starts on <strong>{course['start_date']}</strong> ({course['duration']}) • Mode: <strong>{course['mode']}</strong>.</p>"
                    _send_receipt_email(member['email'], m_name, amount, f"CTI Course: {course['title']} ({course['duration']})", enrollment['id'], schedule_msg)
            except Exception as mail_err:
                logger.warning(f"[CTI] Failed to send enrollment receipt email: {mail_err}")

            return jsonify({
                'message': 'Successfully enrolled in CTI course',
                'enrollment': dict(enrollment),
                'course': dict(course)
            }), 201

    except Exception as e:
        conn.rollback()
        logger.exception("Error in enroll_in_course: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()


@events_bp.route('/courses/my-enrollments', methods=['GET'])
@jwt_required()
def get_my_course_enrollments():
    """Fetch all CTI courses enrolled by the authenticated member."""
    member_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT e.id as enrollment_id, e.status as enrollment_status, e.payment_ref, e.amount,
                       e.payment_confirmed_at, e.created_at as enrolled_at,
                       c.id as course_id, c.title, c.start_date, c.duration, c.mode, c.fee, c.description
                FROM cti_course_enrollments e
                JOIN cti_courses c ON c.id = e.course_id
                WHERE e.member_id = %s AND c.deleted_at IS NULL
                ORDER BY e.id DESC
            """, (member_id,))
            rows = cursor.fetchall()
            items = []
            for r in rows:
                item = dict(r)
                if hasattr(item.get('enrolled_at'), 'isoformat'):
                    item['enrolled_at'] = item['enrolled_at'].isoformat()
                if hasattr(item.get('payment_confirmed_at'), 'isoformat'):
                    item['payment_confirmed_at'] = item['payment_confirmed_at'].isoformat()
                items.append(item)

            return jsonify({'items': items, 'total': len(items)}), 200
    except Exception as e:
        logger.exception("Error in get_my_course_enrollments: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()


@events_bp.route('/admin/courses/enrollments', methods=['GET'])
@sub_admin_required('events')
def get_admin_course_enrollments():
    """Admin endpoint to view all member enrollments in CTI courses."""
    course_id = request.args.get('course_id')
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            query = """
                SELECT e.id, e.status, e.payment_ref, e.amount, e.payment_confirmed_at, e.created_at,
                       c.id as course_id, c.title as course_title, c.start_date, c.mode,
                       m.id as member_id, m.name as member_name, m.company, m.email, m.phone, m.membership_number
                FROM cti_course_enrollments e
                JOIN cti_courses c ON c.id = e.course_id
                JOIN members m ON m.id = e.member_id
            """
            params = []
            if course_id:
                query += " WHERE c.id = %s"
                params.append(course_id)
            query += " ORDER BY e.id DESC"
            cursor.execute(query, tuple(params))
            rows = cursor.fetchall()
            items = []
            for r in rows:
                item = dict(r)
                if hasattr(item.get('created_at'), 'isoformat'):
                    item['created_at'] = item['created_at'].isoformat()
                items.append(item)
            return jsonify({'items': items, 'total': len(items)}), 200
    except Exception as e:
        logger.exception("Error in get_admin_course_enrollments: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()


@events_bp.route('/admin/courses/guest-enrollments', methods=['GET'])
@sub_admin_required('events')
def get_admin_guest_enrollments():
    """Admin endpoint to view all guest course enrollments and payments."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS guest_payments (
                    id SERIAL PRIMARY KEY,
                    reference_no VARCHAR(100) UNIQUE NOT NULL,
                    service_type VARCHAR(100),
                    name VARCHAR(255),
                    phone VARCHAR(50),
                    email VARCHAR(150),
                    course_name VARCHAR(255),
                    amount NUMERIC(12, 2),
                    network VARCHAR(50),
                    status VARCHAR(50) DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS guest_service_requests (
                    id SERIAL PRIMARY KEY,
                    reference_no VARCHAR(100) UNIQUE NOT NULL,
                    service_type VARCHAR(100),
                    name VARCHAR(255),
                    phone VARCHAR(50),
                    email VARCHAR(150),
                    company VARCHAR(255),
                    primary_port VARCHAR(150),
                    course_name VARCHAR(255),
                    details TEXT,
                    status VARCHAR(50) DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                SELECT 
                    COALESCE(gp.id, gr.id) as id,
                    COALESCE(gp.reference_no, gr.reference_no) as reference_no,
                    COALESCE(gp.name, gr.name) as guest_name,
                    COALESCE(gp.phone, gr.phone) as phone,
                    COALESCE(gp.email, gr.email) as email,
                    COALESCE(gr.company, 'Guest Student / Applicant') as company,
                    COALESCE(gp.course_name, gr.course_name, 'CTI Professional Course') as course_title,
                    COALESCE(gp.amount, 1500.0) as amount,
                    COALESCE(gp.network, 'Mobile Money') as payment_network,
                    COALESCE(gp.status, gr.status, 'paid') as status,
                    COALESCE(gp.created_at, gr.created_at) as created_at,
                    gr.details as notes
                FROM guest_service_requests gr
                FULL OUTER JOIN guest_payments gp ON gp.reference_no = gr.reference_no
                WHERE (gr.service_type = 'cti_training' OR gp.service_type = 'cti_training' OR gp.reference_no LIKE 'CTI-%' OR gr.course_name IS NOT NULL)
                ORDER BY COALESCE(gp.created_at, gr.created_at) DESC
            """)
            rows = cursor.fetchall()
            items = []
            for r in rows:
                item = dict(r)
                if hasattr(item.get('created_at'), 'isoformat'):
                    item['created_at'] = item['created_at'].isoformat()
                if item.get('amount') is not None:
                    item['amount'] = float(item['amount'])
                items.append(item)
            return jsonify({'items': items, 'total': len(items)}), 200
    except Exception as e:
        logger.exception("Error in get_admin_guest_enrollments: %s", e)
        return jsonify({'items': [], 'total': 0}), 200
    finally:
        conn.close()


@events_bp.route('/admin/courses/guest-enrollments/<string:ref>/mark-paid', methods=['POST'])
@sub_admin_required('events')
def mark_guest_enrollment_paid(ref):
    """Admin endpoint to manually confirm or mark a guest enrollment as paid."""
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("UPDATE guest_payments SET status = 'paid', updated_at = NOW() WHERE reference_no = %s", (ref,))
            cursor.execute("UPDATE guest_service_requests SET status = 'paid', updated_at = NOW() WHERE reference_no = %s", (ref,))
            conn.commit()
        return jsonify({'message': f'Enrollment {ref} marked as paid successfully'}), 200
    except Exception as e:
        logger.exception("Error in mark_guest_enrollment_paid: %s", e)
        return jsonify({'message': 'Failed to mark as paid'}), 500
    finally:
        conn.close()


# ─────────────────────────────────────────────
#  ADMIN GALLERY ITEMS CRUD
# ─────────────────────────────────────────────

@events_bp.route('/admin/gallery', methods=['GET'])
@sub_admin_required('events')
def get_admin_gallery():
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, title, category, image_url, grad_start, grad_end, is_active, created_at
                FROM gallery_items
                WHERE deleted_at IS NULL
                ORDER BY id DESC
            """)
            items = cursor.fetchall()
            for item in items:
                if hasattr(item.get('created_at'), 'isoformat'):
                    item['created_at'] = item['created_at'].isoformat()
        return jsonify({'items': items, 'total': len(items)}), 200
    except Exception as e:
        logger.exception("Error in get_admin_gallery: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/gallery', methods=['POST'])
@sub_admin_required('events')
def create_admin_gallery_item():
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    if not title:
        return jsonify({'message': 'Gallery title is required'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO gallery_items (title, category, image_url, grad_start, grad_end, is_active)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id, title, category, image_url, grad_start, grad_end, is_active
            """, (
                title,
                data.get('category', 'Conferences'),
                data.get('image_url', ''),
                data.get('grad_start', '#6B3E26'),
                data.get('grad_end', '#3E2418'),
                data.get('is_active', True)
            ))
            new_item = cursor.fetchone()
            conn.commit()
        log_admin_action(admin_id, 'Added Gallery Photo', 'gallery', new_item['id'], title)
        try:
            socketio.emit('gallery_updated', {'id': new_item['id']})
        except Exception:
            pass
        return jsonify({'message': 'Gallery item added successfully', 'item': new_item}), 201
    except Exception as e:
        conn.rollback()
        logger.exception("Error creating gallery item: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/gallery/<int:item_id>', methods=['PUT'])
@sub_admin_required('events')
def update_admin_gallery_item(item_id):
    admin_id = get_jwt_identity()
    data = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                UPDATE gallery_items
                SET title = COALESCE(NULLIF(%s, ''), title),
                    category = COALESCE(%s, category),
                    image_url = COALESCE(%s, image_url),
                    grad_start = COALESCE(%s, grad_start),
                    grad_end = COALESCE(%s, grad_end),
                    is_active = COALESCE(%s, is_active)
                WHERE id = %s AND deleted_at IS NULL
                RETURNING id, title, category, image_url, grad_start, grad_end, is_active
            """, (
                data.get('title'),
                data.get('category'),
                data.get('image_url'),
                data.get('grad_start'),
                data.get('grad_end'),
                data.get('is_active'),
                item_id
            ))
            updated = cursor.fetchone()
            if not updated:
                return jsonify({'message': 'Gallery item not found'}), 404
            conn.commit()
        log_admin_action(admin_id, 'Updated Gallery Photo', 'gallery', item_id, updated['title'])
        try:
            socketio.emit('gallery_updated', {'id': item_id})
        except Exception:
            pass
        return jsonify({'message': 'Gallery item updated successfully', 'item': updated}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error updating gallery item: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()

@events_bp.route('/admin/gallery/<int:item_id>', methods=['DELETE'])
@sub_admin_required('events')
def delete_admin_gallery_item(item_id):
    admin_id = get_jwt_identity()
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute("UPDATE gallery_items SET deleted_at = CURRENT_TIMESTAMP WHERE id = %s RETURNING title", (item_id,))
            res = cursor.fetchone()
            if not res:
                return jsonify({'message': 'Gallery item not found'}), 404
            conn.commit()
        log_admin_action(admin_id, 'Archived Gallery Photo', 'gallery', item_id, res['title'])
        try:
            socketio.emit('gallery_updated', {'id': item_id, 'deleted': True})
        except Exception:
            pass
        return jsonify({'message': 'Gallery item archived successfully'}), 200
    except Exception as e:
        conn.rollback()
        logger.exception("Error deleting gallery item: %s", e)
        return jsonify({'message': str(e)}), 500
    finally:
        conn.close()
