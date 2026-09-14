import os
import sys
from dotenv import load_dotenv
from werkzeug.security import generate_password_hash

# Ensure root backend dir is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from config.db import get_db, init_db
from scripts.seed_official_fees import seed as seed_fees

load_dotenv()

def reset_fresh_database():
    print("==================================================")
    print("  RESETTING CUBAG DATABASE TO FRESH STATE")
    print("==================================================")

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            # First ensure all tables and migrations are initialized
            init_db()

            # Find all public tables
            cursor.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                  AND table_type = 'BASE TABLE';
            """)
            tables = [r['table_name'] for r in cursor.fetchall()]
            print(f"Found {len(tables)} tables in database: {', '.join(tables)}")

            # Exclude nothing except if needed, but we want a complete fresh clean slate!
            # Truncate all tables with CASCADE and RESTART IDENTITY
            if tables:
                truncate_statement = f"TRUNCATE TABLE {', '.join(tables)} RESTART IDENTITY CASCADE;"
                print(f"Executing: {truncate_statement}")
                cursor.execute(truncate_statement)
                conn.commit()
                print("✓ All tables truncated successfully and IDs reset to 1.")

            # Create Super Administrator Account
            admin_email = "admin@cubag.com"
            admin_password = "Admin123!"
            password_hash = generate_password_hash(admin_password, method='pbkdf2:sha256')

            cursor.execute("""
                INSERT INTO members (
                    name, 
                    email, 
                    phone, 
                    company, 
                    license_number, 
                    agency_code, 
                    port_of_operation, 
                    member_type, 
                    role, 
                    password_hash, 
                    status, 
                    email_verified, 
                    compliance_score, 
                    star_rating,
                    manual_review_score
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                ) RETURNING id;
            """, (
                "Super Administrator",
                admin_email,
                "+233240000001",
                "CUBAG Executive Secretariat",
                None,
                None,
                "National Secretariat",
                "Executive Secretariat",
                "super_admin",
                password_hash,
                "active",
                True,
                None,
                None,
                None
            ))
            admin_id = cursor.fetchone()['id']
            conn.commit()
            print(f"✓ Super Admin created (ID: {admin_id}, Email: {admin_email}, Role: super_admin)")

        # Re-seed official fees and document rules
        print("Re-seeding official system fees...")
        seed_fees()

        print("==================================================")
        print("  FRESH DATABASE READY!")
        print(f"  Super Admin Login: {admin_email}")
        print(f"  Password:          {admin_password}")
        print("==================================================")

    except Exception as e:
        conn.rollback()
        print(f"❌ Error during database reset: {e}")
        raise e
    finally:
        conn.close()

if __name__ == '__main__':
    reset_fresh_database()
