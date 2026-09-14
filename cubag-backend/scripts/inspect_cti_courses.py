from config.db import get_db

conn = get_db()
with conn.cursor() as cur:
    cur.execute("SELECT * FROM cti_courses")
    rows = cur.fetchall()
    print(f"Total courses: {len(rows)}")
    for r in rows:
        print(dict(r))
conn.close()
