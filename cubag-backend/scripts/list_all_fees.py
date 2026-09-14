from config.db import get_db

conn = get_db()
with conn.cursor() as cur:
    cur.execute("SELECT id, label, amount, frequency, description, is_active FROM fee_schedules ORDER BY id")
    rows = cur.fetchall()
    print(f"Total fees in fee_schedules table: {len(rows)}\n")
    for r in rows:
        print(f"ID: {r['id']}")
        print(f"  Label:       {r['label']}")
        print(f"  Amount:      GHS {r['amount']}")
        print(f"  Frequency:   {r['frequency']}")
        print(f"  Description: {r['description']}")
        print(f"  Is Active:   {r['is_active']}")
        print("-" * 50)
conn.close()
