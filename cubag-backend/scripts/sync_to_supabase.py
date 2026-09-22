import os
import mimetypes
import requests
import psycopg2
from psycopg2.extras import RealDictCursor

LOCAL_DSN = "host=localhost port=5432 dbname=CUBAG user=postgres password=Godlovesme1@"
SUPABASE_DSN = "postgresql://postgres.feanlatdsyhlghsnepxw:QqnRcWcYlKZf9quI@aws-1-eu-west-1.pooler.supabase.com:6543/postgres"

SUPABASE_URL = "https://feanlatdsyhlghsnepxw.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlYW5sYXRkc3lobGdoc25lcHh3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzgzMTk1OCwiZXhwIjoyMTAzNDA3OTU4fQ.eBQ3heAjIBThoqP4oDLpeDP35QEDnzjJ7E9uY3vyCNE"
BUCKET = "uploads"

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def upload_local_files_to_supabase():
    print("--- 1. Uploading local files to Supabase Storage ---")
    uploads_dir = os.path.join(BACKEND_DIR, 'uploads')
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
    }
    
    url_map = {}
    for root, _, files in os.walk(uploads_dir):
        for f in files:
            if f.startswith('.'):
                continue
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, uploads_dir)
            # e.g. compliance_docs/1/xyz.png
            cloud_path = rel_path.replace('\\', '/')
            mime_type, _ = mimetypes.guess_type(full_path)
            mime_type = mime_type or 'application/octet-stream'
            
            storage_url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{cloud_path}"
            public_url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{cloud_path}"
            
            with open(full_path, 'rb') as fp:
                file_bytes = fp.read()
            
            req_headers = {**headers, "Content-Type": mime_type, "x-upsert": "true"}
            r = requests.post(storage_url, headers=req_headers, data=file_bytes)
            if r.status_code in (200, 201):
                print(f" Uploaded: {cloud_path} -> {public_url}")
                url_map[f"/static/uploads/{cloud_path}"] = public_url
                url_map[f"/uploads/{cloud_path}"] = public_url
            else:
                print(f" Failed upload {cloud_path}: {r.status_code} {r.text}")
    return url_map


def sync_database(url_map):
    print("\n--- 2. Syncing Local PostgreSQL to Supabase PostgreSQL ---")
    c_local = psycopg2.connect(LOCAL_DSN, cursor_factory=RealDictCursor)
    c_supa = psycopg2.connect(SUPABASE_DSN, cursor_factory=RealDictCursor)
    
    cur_l = c_local.cursor()
    cur_s = c_supa.cursor()
    
    # Order of tables matters for foreign keys!
    tables_to_sync = [
        'members',
        'sub_admin_permissions',
        'document_requirements',
        'fee_schedules',
        'compliance_settings',
        'compliance_app_settings',
        'platform_settings',
        'ports_of_operation',
        'port_bulletins',
        'events',
        'event_attendance',
        'cti_courses',
        'cti_course_enrollments',
        'guest_payments',
        'license_history',
        'compliance_applications',
        'compliance_documents',
        'member_documents',
        'payments',
        'payment_ledger',
        'member_rating_history',
        'surveys',
        'survey_responses',
        'tasks',
        'task_submissions',
        'task_submission_files',
        'hardcopy_certificate_requests',
        'support_tickets',
        'ticket_replies',
        'messages',
        'notifications',
        'otp_codes',
        'gallery_items',
        'news_blog',
        'announcements',
        'announcement_reads',
        'audit_log',
        'admin_audit_logs',
        'schedules',
        'guest_service_requests',
    ]
    
    for tbl in tables_to_sync:
        try:
            # Check if table exists in local
            cur_l.execute(f"SELECT * FROM {tbl};")
            local_rows = cur_l.fetchall()
            if not local_rows:
                continue
            
            # Check columns in Supabase
            cur_s.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name = '{tbl}';")
            supa_cols = set(r['column_name'] for r in cur_s.fetchall())
            if not supa_cols:
                print(f"Table {tbl} does not exist in Supabase. Skipping.")
                continue
            
            # Fetch existing IDs from Supabase if id column exists
            has_id = 'id' in supa_cols
            existing_ids = set()
            if has_id:
                cur_s.execute(f"SELECT id FROM {tbl};")
                existing_ids = set(r['id'] for r in cur_s.fetchall())
            
            # Insert missing rows
            inserted = 0
            for row in local_rows:
                if has_id and row['id'] in existing_ids:
                    continue
                
                # Filter row columns to only those that exist in Supabase
                filtered = {k: v for k, v in row.items() if k in supa_cols}
                
                # Replace local URLs with Supabase URLs if matched
                for k, v in filtered.items():
                    if isinstance(v, str):
                        for old_url, new_url in url_map.items():
                            if old_url in v:
                                filtered[k] = v.replace(old_url, new_url)
                
                cols = list(filtered.keys())
                vals = [filtered[c] for c in cols]
                placeholders = ", ".join(["%s"] * len(cols))
                col_names = ", ".join([f'"{c}"' for c in cols])
                
                insert_query = f'INSERT INTO "{tbl}" ({col_names}) VALUES ({placeholders})'
                cur_s.execute(insert_query, vals)
                inserted += 1
            
            c_supa.commit()
            
            # Reset sequence if id column exists
            if has_id and inserted > 0:
                cur_s.execute(f"SELECT setval(pg_get_serial_sequence('\"{tbl}\"', 'id'), coalesce(max(id), 1)) FROM \"{tbl}\";")
                c_supa.commit()
            
            print(f"[{tbl}] Synced {inserted} new rows (Local total: {len(local_rows)}, Supabase total now: {len(existing_ids) + inserted})")
        except Exception as e:
            c_supa.rollback()
            print(f"Error syncing {tbl}: {e}")
            
    c_local.close()
    c_supa.close()
    print("Database sync complete!")

if __name__ == '__main__':
    url_map = upload_local_files_to_supabase()
    sync_database(url_map)
