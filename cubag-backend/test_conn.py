import os
from dotenv import load_dotenv
import psycopg2
import logging

logging.basicConfig(level=logging.INFO)
load_dotenv()

try:
    host = os.getenv('DB_HOST')
    port = os.getenv('DB_PORT', 5432)
    user = os.getenv('DB_USER')
    password = os.getenv('DB_PASSWORD')
    dbname = os.getenv('DB_NAME')

    print(f"Connecting to {host}:{port}...")
    conn = psycopg2.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        dbname=dbname,
        sslmode='require',
        connect_timeout=5
    )
    print("Connected successfully!")
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
        print("Query executed!")
    conn.close()
except Exception as e:
    print(f"Connection failed: {e}")
