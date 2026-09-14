from config.db import get_db

conn = get_db()
with conn.cursor() as cur:
    cur.execute("SELECT id, name, email, role, status FROM members WHERE role LIKE '%admin%'")
    admins = cur.fetchall()
    print("Admins in members table:")
    for a in admins:
        print(dict(a))
conn.close()
