import json
from config.db import get_db

conn = get_db()
with conn.cursor() as cur:
    cur.execute("SELECT config_value FROM platform_settings WHERE config_key = 'cubag_fees_v2'")
    row = cur.fetchone()
    print("Current cubag_fees_v2 in DB:")
    if row:
        print(row['config_value'][:500] if row['config_value'] else "None")
    else:
        print("No cubag_fees_v2 row found.")
conn.close()
