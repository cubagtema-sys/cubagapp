from config.db import get_db

conn = get_db()
with conn.cursor() as cur:
    # 1. Update course fee for Freight Forwarding Fundamentals
    cur.execute("""
        UPDATE cti_courses 
        SET fee = 'GHS 1,980' 
        WHERE title ILIKE '%Freight Forwarding Fundamentals%'
    """)

    # 2. Create cti_course_enrollments table
    cur.execute("""
        CREATE TABLE IF NOT EXISTS cti_course_enrollments (
            id SERIAL PRIMARY KEY,
            course_id INTEGER NOT NULL REFERENCES cti_courses(id) ON DELETE CASCADE,
            member_id INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
            status VARCHAR(30) DEFAULT 'enrolled',
            payment_method VARCHAR(50) DEFAULT 'momo',
            payment_ref VARCHAR(100),
            amount NUMERIC(10,2),
            payment_confirmed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT unique_member_course UNIQUE (course_id, member_id)
        );
    """)
    conn.commit()
    print("cti_course_enrollments table created and courses verified successfully.")

    cur.execute("SELECT id, title, start_date, duration, mode, fee FROM cti_courses ORDER BY id")
    for r in cur.fetchall():
        print(dict(r))
conn.close()
