from config.db import get_db

conn = get_db()
with conn.cursor() as cur:
    cur.execute("""
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'fee_schedules'
    """)
    cols = cur.fetchall()
    print("Columns in fee_schedules:")
    for c in cols:
        print(f" - {c['column_name']} ({c['data_type']})")
    
    cur.execute("SELECT * FROM fee_schedules")
    rows = cur.fetchall()
    print(f"\nRows ({len(rows)}):")
    for r in rows:
        print(dict(r))
conn.close()
