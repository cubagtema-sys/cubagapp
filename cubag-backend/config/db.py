import os
import logging
import socket
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

load_dotenv()

# Connection pool instance
_pool = None


def _db_kwargs():
    """Resolve the DB config while respecting explicit .env values.

    Local development should prefer localhost, while a remote configured host
    should only be used when it is actually resolvable. If the configured host
    is unreachable from this machine, fail over to the local Postgres instance
    instead of crashing the API startup path.
    """
    database_url = os.getenv('DATABASE_URL', '').strip()
    if database_url:
        return {'dsn': database_url}

    host = os.getenv('DB_HOST', '').strip() or 'localhost'
    if host not in {'localhost', '127.0.0.1', '0.0.0.0', '::1'}:
        try:
            socket.getaddrinfo(host, None)
        except socket.gaierror:
            logger.warning(
                "[DB] DB_HOST '%s' is not resolvable from this machine; falling back to localhost.",
                host,
            )
            host = 'localhost'

    return {
        'host': host,
        'port': int(os.getenv('DB_PORT', 5432)),
        'user': os.getenv('DB_USER', 'postgres'),
        'password': os.getenv('DB_PASSWORD', ''),
        'dbname': os.getenv('DB_NAME', 'postgres'),
        'sslmode': 'disable' if host in {'localhost', '127.0.0.1', '0.0.0.0', '::1'} else 'require',
    }


class PooledConnection:
    """A simple wrapper to return connections to the pool when close() is called."""
    def __init__(self, conn, pool):
        self._conn = conn
        self._pool = pool

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def close(self):
        if self._pool:
            try:
                self._pool.putconn(self._conn)
            except Exception as e:
                logger.warning(f"Error returning connection to pool: {e}")
        else:
            self._conn.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

def get_db():
    """Get a database connection from the pool."""
    global _pool
    if _pool is None:
        kwargs = _db_kwargs()
        if 'dsn' in kwargs:
            _pool = ThreadedConnectionPool(5, 50, kwargs['dsn'], cursor_factory=RealDictCursor)
        else:
            _pool = ThreadedConnectionPool(5, 50, cursor_factory=RealDictCursor, **kwargs)

    try:
        conn = _pool.getconn()
        if conn.closed:
            try:
                _pool.putconn(conn, close=True)
            except Exception:
                pass
            conn = _pool.getconn()

        # Ping connection to ensure it's not closed by remote server
        try:
            with conn.cursor() as ping_cur:
                ping_cur.execute("SELECT 1")
        except Exception:
            try:
                _pool.putconn(conn, close=True)
            except Exception:
                pass
            conn = _pool.getconn()

        return PooledConnection(conn, _pool)
    except Exception as e:
        logger.warning(f"Connection pool getconn failed, creating fallback connection: {e}")
        kwargs = _db_kwargs()
        if 'dsn' in kwargs:
            fallback_conn = psycopg2.connect(kwargs['dsn'], cursor_factory=RealDictCursor)
        else:
            fallback_conn = psycopg2.connect(cursor_factory=RealDictCursor, **kwargs)
        return PooledConnection(fallback_conn, None)


def init_db():
    """Initialize the database tables if they don't exist.

    On local development setups without a reachable PostgreSQL instance,
    we keep the API alive and log a clear warning instead of crashing.
    """
    try:
        conn = get_db()
    except Exception as e:
        logger.warning("[DB] Database unavailable during startup. API will continue in degraded mode until a reachable PostgreSQL instance is available: %s", e)
        return

    try:
        with conn.cursor() as cursor:
            # Members / Users table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS members (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(150) NOT NULL,
                    email VARCHAR(150) UNIQUE NOT NULL,
                    phone VARCHAR(30),
                    company VARCHAR(200),
                    license_number VARCHAR(100),
                    agency_code VARCHAR(100),
                    port_of_operation VARCHAR(100) DEFAULT 'Tema Port',
                    member_type VARCHAR(50) DEFAULT 'Licentiate',
                    password_hash TEXT NOT NULL,
                    status VARCHAR(20) DEFAULT 'pending',
                    email_verified BOOLEAN DEFAULT FALSE,
                    verification_token VARCHAR(255),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Ensure columns exist if table was already created
            cursor.execute("""
                ALTER TABLE members 
                ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT FALSE,
                ADD COLUMN IF NOT EXISTS verification_token VARCHAR(255),
                ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(255),
                ADD COLUMN IF NOT EXISTS license_expiry_date DATE,
                ADD COLUMN IF NOT EXISTS location TEXT,
                ADD COLUMN IF NOT EXISTS digital_address VARCHAR(100),
                ADD COLUMN IF NOT EXISTS tin VARCHAR(100),
                ADD COLUMN IF NOT EXISTS registration_fee_paid BOOLEAN DEFAULT FALSE,
                ADD COLUMN IF NOT EXISTS application_fee_paid BOOLEAN DEFAULT FALSE,
                ADD COLUMN IF NOT EXISTS package_fee_paid BOOLEAN DEFAULT FALSE,
                ADD COLUMN IF NOT EXISTS good_standing BOOLEAN DEFAULT TRUE;
            """)

            # OTP Codes table for pre-registration verification
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS otp_codes (
                    email VARCHAR(150) NOT NULL,
                    code VARCHAR(10) NOT NULL,
                    type VARCHAR(50) DEFAULT 'email_verification',
                    attempts INT DEFAULT 0,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (email, type)
                )
            """)

            cursor.execute("""
                ALTER TABLE otp_codes 
                ADD COLUMN IF NOT EXISTS type VARCHAR(50) DEFAULT 'email_verification',
                ADD COLUMN IF NOT EXISTS attempts INT DEFAULT 0;
            """)

            cursor.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS idx_otp_codes_email_type ON otp_codes(email, type);
            """)

            # Announcements (broadcast messages)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS announcements (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    body TEXT,
                    category VARCHAR(100) DEFAULT 'General',
                    posted_by VARCHAR(150),
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("""
                ALTER TABLE announcements ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;
            """)

            # Purge legacy system-generated notifications improperly stored as announcements
            try:
                cursor.execute("""
                    DO $$
                    BEGIN
                        IF EXISTS (
                            SELECT 1 FROM information_schema.columns 
                            WHERE table_name='announcements' AND column_name='member_id'
                        ) THEN
                            DELETE FROM announcements WHERE posted_by = 'System Alert' OR member_id IS NOT NULL;
                        ELSE
                            DELETE FROM announcements WHERE posted_by = 'System Alert';
                        END IF;
                    END $$;
                """)
            except Exception as purge_err:
                logger.debug("Announcements purge skipped: %s", purge_err)

            # User notifications (personal alerts)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS notifications (
                    id SERIAL PRIMARY KEY,
                    member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    title VARCHAR(255) NOT NULL,
                    body TEXT,
                    category VARCHAR(100) DEFAULT 'System',
                    notification_type VARCHAR(50) DEFAULT 'notification',
                    deleted_at TIMESTAMP DEFAULT NULL,
                    read_at TIMESTAMP NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Tasks / Compliance
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS tasks (
                    id SERIAL PRIMARY KEY,
                    member_id INT,
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    due_date DATE,
                    done BOOLEAN DEFAULT FALSE,
                    priority VARCHAR(20) DEFAULT 'medium',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (member_id) REFERENCES members(id)
                )
            """)

            # Events
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS events (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    date DATE,
                    time VARCHAR(50),
                    location VARCHAR(255),
                    capacity INT,
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            cursor.execute("""
                ALTER TABLE events ADD COLUMN IF NOT EXISTS capacity INT;
            """)
            cursor.execute("""
                ALTER TABLE events ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;
            """)

            # Event Attendance
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS event_attendance (
                    event_id INT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
                    member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    checked_in_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (event_id, member_id)
                )
            """)

            # Payments / Dues
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS payments (
                    id SERIAL PRIMARY KEY,
                    member_id INT,
                    amount DECIMAL(10,2),
                    description VARCHAR(255),
                    status VARCHAR(20) DEFAULT 'pending',
                    payment_ref VARCHAR(255),
                    due_date DATE,
                    paid_at TIMESTAMP NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (member_id) REFERENCES members(id)
                )
            """)

            # Ensure payment_ref column exists on older databases
            cursor.execute("""
                ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_ref VARCHAR(255);
            """)

            # Surveys
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS surveys (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    type VARCHAR(20) DEFAULT 'Survey',
                    expiry DATE,
                    active BOOLEAN DEFAULT TRUE,
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("""
                ALTER TABLE surveys
                ADD COLUMN IF NOT EXISTS deadline DATE,
                ADD COLUMN IF NOT EXISTS options TEXT,
                ADD COLUMN IF NOT EXISTS cover_image TEXT,
                ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL,
                ADD COLUMN IF NOT EXISTS target_audience VARCHAR(30) DEFAULT 'both';
            """)

            # Survey Responses
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS survey_responses (
                    id SERIAL PRIMARY KEY,
                    survey_id INT NOT NULL,
                    member_id INT,
                    answers TEXT,
                    guest_identifier VARCHAR(150),
                    guest_name VARCHAR(150),
                    guest_email VARCHAR(150),
                    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (survey_id) REFERENCES surveys(id) ON DELETE CASCADE,
                    FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE SET NULL
                )
            """)

            cursor.execute("""
                ALTER TABLE survey_responses
                ALTER COLUMN member_id DROP NOT NULL,
                ADD COLUMN IF NOT EXISTS guest_identifier VARCHAR(150),
                ADD COLUMN IF NOT EXISTS guest_name VARCHAR(150),
                ADD COLUMN IF NOT EXISTS guest_email VARCHAR(150);
            """)

            # Schedules
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS schedules (
                    id SERIAL PRIMARY KEY,
                    type VARCHAR(50) NOT NULL,
                    container VARCHAR(100),
                    vessel VARCHAR(150),
                    cargo VARCHAR(150),
                    date VARCHAR(100),
                    port VARCHAR(150),
                    status VARCHAR(50) DEFAULT 'Scheduled',
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Compliance Centre Tables
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS compliance_applications (
                    id                      SERIAL PRIMARY KEY,
                    member_id               INTEGER NOT NULL,
                    type                    VARCHAR(30) NOT NULL,
                    status                  VARCHAR(30) NOT NULL DEFAULT 'draft',
                    payment_ref             TEXT,
                    payment_amount          NUMERIC(10,2),
                    payment_confirmed_at    TIMESTAMP,
                    admin_note              TEXT,
                    reviewed_by             INTEGER,
                    reviewed_at             TIMESTAMP,
                    created_at              TIMESTAMP DEFAULT NOW(),
                    updated_at              TIMESTAMP DEFAULT NOW()
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS compliance_documents (
                    id              SERIAL PRIMARY KEY,
                    application_id  INTEGER NOT NULL,
                    requirement     VARCHAR(100) NOT NULL,
                    label           TEXT NOT NULL,
                    file_url        TEXT,
                    file_name       TEXT,
                    file_size       INTEGER,
                    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
                    auto_filled     BOOLEAN NOT NULL DEFAULT FALSE,
                    source_uploaded_at TIMESTAMP,
                    admin_note      TEXT,
                    uploaded_at     TIMESTAMP DEFAULT NOW(),
                    reviewed_at     TIMESTAMP,
                    reviewed_by     INTEGER
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS document_requirements (
                    id           SERIAL PRIMARY KEY,
                    key          VARCHAR(100) UNIQUE NOT NULL,
                    label        TEXT NOT NULL,
                    description  TEXT,
                    is_required  BOOLEAN DEFAULT TRUE,
                    display_order INTEGER DEFAULT 0,
                    is_active    BOOLEAN DEFAULT TRUE,
                    deleted_at   TIMESTAMP DEFAULT NULL,
                    created_at   TIMESTAMP DEFAULT NOW()
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS member_documents (
                    id           SERIAL PRIMARY KEY,
                    member_id    INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    requirement  VARCHAR(100) NOT NULL,
                    label        TEXT NOT NULL,
                    file_url     TEXT,
                    file_name    TEXT,
                    file_size    INTEGER,
                    status       VARCHAR(20) NOT NULL DEFAULT 'pending',
                    admin_note   TEXT,
                    uploaded_at  TIMESTAMP DEFAULT NOW(),
                    reviewed_at  TIMESTAMP,
                    reviewed_by  INTEGER
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS compliance_app_settings (
                    key VARCHAR(50) PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at TIMESTAMP DEFAULT NOW()
                )
            """)

            # Add transaction info, role, profile photo, license, membership number and good_standing to members if not exists
            cursor.execute("""
                ALTER TABLE members 
                ADD COLUMN IF NOT EXISTS payment_ref VARCHAR(255),
                ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'member',
                ADD COLUMN IF NOT EXISTS profile_photo TEXT,
                ADD COLUMN IF NOT EXISTS fcm_token TEXT,
                ADD COLUMN IF NOT EXISTS compliance_score INT DEFAULT 100,
                ADD COLUMN IF NOT EXISTS star_rating DECIMAL(3,2) DEFAULT 5.0,
                ADD COLUMN IF NOT EXISTS manual_review_score INT DEFAULT 10,
                ADD COLUMN IF NOT EXISTS good_standing BOOLEAN DEFAULT FALSE,
                ADD COLUMN IF NOT EXISTS license_number VARCHAR(100),
                ADD COLUMN IF NOT EXISTS membership_number VARCHAR(100),
                ADD COLUMN IF NOT EXISTS primary_port VARCHAR(100) DEFAULT 'Tema',
                ADD COLUMN IF NOT EXISTS member_scale VARCHAR(50) DEFAULT 'sme',
                ADD COLUMN IF NOT EXISTS fee_category VARCHAR(100) DEFAULT 'cf_only',
                ADD COLUMN IF NOT EXISTS consolidation_scope VARCHAR(50) DEFAULT 'without_consolidation';
            """)

            cursor.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS idx_members_membership_number ON members (membership_number) WHERE membership_number IS NOT NULL AND membership_number != '' AND membership_number != 'PENDING';
                CREATE UNIQUE INDEX IF NOT EXISTS idx_members_license_number ON members (license_number) WHERE license_number IS NOT NULL AND license_number != '' AND license_number != 'PENDING';
            """)

            # Configurable fee schedules
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS fee_schedules (
                    id SERIAL PRIMARY KEY,
                    fee_type VARCHAR(50) NOT NULL,
                    key VARCHAR(100) UNIQUE NOT NULL,
                    name VARCHAR(255) NOT NULL,
                    scale VARCHAR(50),
                    scope VARCHAR(50),
                    amount NUMERIC(10,2) NOT NULL,
                    version VARCHAR(20) DEFAULT '2026.1',
                    effective_from DATE DEFAULT '2026-01-01',
                    effective_to DATE DEFAULT '2026-12-31',
                    description TEXT,
                    is_active BOOLEAN DEFAULT TRUE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                ALTER TABLE fee_schedules
                ADD COLUMN IF NOT EXISTS version VARCHAR(20) DEFAULT '2026.1',
                ADD COLUMN IF NOT EXISTS effective_from DATE DEFAULT '2026-01-01',
                ADD COLUMN IF NOT EXISTS effective_to DATE DEFAULT '2026-12-31';
            """)

            # Hardcopy Certificate Requests
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS hardcopy_certificate_requests (
                    id SERIAL PRIMARY KEY,
                    member_id INT REFERENCES members(id) ON DELETE CASCADE,
                    certificate_type VARCHAR(100) DEFAULT 'membership_license',
                    request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    fee_amount NUMERIC(10,2) DEFAULT 0.00,
                    payment_status VARCHAR(50) DEFAULT 'unpaid',
                    processing_status VARCHAR(50) DEFAULT 'pending',
                    delivery_method VARCHAR(50) DEFAULT 'courier',
                    delivery_address TEXT,
                    contact_phone VARCHAR(50),
                    collection_status VARCHAR(50) DEFAULT 'pending',
                    completed_at TIMESTAMP,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("""
                ALTER TABLE hardcopy_certificate_requests
                ADD COLUMN IF NOT EXISTS certificate_type VARCHAR(100) DEFAULT 'membership_license',
                ADD COLUMN IF NOT EXISTS request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                ADD COLUMN IF NOT EXISTS fee_amount NUMERIC(10,2) DEFAULT 0.00,
                ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) DEFAULT 'unpaid',
                ADD COLUMN IF NOT EXISTS processing_status VARCHAR(50) DEFAULT 'pending',
                ADD COLUMN IF NOT EXISTS delivery_method VARCHAR(50) DEFAULT 'courier',
                ADD COLUMN IF NOT EXISTS collection_status VARCHAR(50) DEFAULT 'pending',
                ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP,
                ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
            """)

            # Payment ledger for itemized fee tracking
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS payment_ledger (
                    id SERIAL PRIMARY KEY,
                    member_id INT REFERENCES members(id) ON DELETE CASCADE,
                    fee_key VARCHAR(100) NOT NULL,
                    fee_name VARCHAR(255) NOT NULL,
                    amount NUMERIC(10,2) NOT NULL,
                    status VARCHAR(50) DEFAULT 'unpaid',
                    payment_ref VARCHAR(255),
                    paid_at TIMESTAMP,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Guest service requests
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS guest_service_requests (
                    id SERIAL PRIMARY KEY,
                    reference_no VARCHAR(100) UNIQUE NOT NULL,
                    service_type VARCHAR(100) NOT NULL,
                    name VARCHAR(255),
                    phone VARCHAR(50),
                    email VARCHAR(150),
                    company VARCHAR(255),
                    primary_port VARCHAR(150),
                    course_name VARCHAR(255),
                    details TEXT,
                    status VARCHAR(50) DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("""
                ALTER TABLE guest_service_requests
                    ADD COLUMN IF NOT EXISTS primary_port VARCHAR(150),
                    ADD COLUMN IF NOT EXISTS course_name VARCHAR(255);
            """)

            # Dynamic Ports of Operation table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS ports_of_operation (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(150) UNIQUE NOT NULL,
                    code VARCHAR(50),
                    is_active BOOLEAN DEFAULT TRUE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Seed default Ghanaian ports if empty
            cursor.execute("SELECT COUNT(*) as total FROM ports_of_operation")
            if cursor.fetchone()['total'] == 0:
                default_ports = [
                    ('Tema Port', 'TMA'),
                    ('Takoradi Port', 'TKD'),
                    ('Kotoka International Airport (KIA)', 'ACC'),
                    ('Elubo Border Port', 'ELB'),
                    ('Aflao Border Port', 'AFL'),
                    ('Paga Border Port', 'PAG')
                ]
                for p_name, p_code in default_ports:
                    cursor.execute("INSERT INTO ports_of_operation (name, code) VALUES (%s, %s) ON CONFLICT DO NOTHING", (p_name, p_code))

            # CTI Short Courses table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS cti_courses (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    start_date VARCHAR(100),
                    duration VARCHAR(100),
                    mode VARCHAR(50) DEFAULT 'Hybrid',
                    fee VARCHAR(50) DEFAULT 'GHS 1,500',
                    description TEXT,
                    is_active BOOLEAN DEFAULT TRUE,
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("SELECT COUNT(*) as total FROM cti_courses WHERE deleted_at IS NULL")
            if cursor.fetchone()['total'] == 0:
                default_courses = [
                    ('Freight Forwarding Fundamentals', '25 Aug 2026', '4 Weeks', 'Hybrid', 'GHS 1,800', 'Foundational customs clearance and brokerage procedures.'),
                    ('Customs Declarations & ICUMS 2.0', '15 Sep 2026', '3 Weeks', 'In-Person', 'GHS 1,500', 'Hands-on declaration classification, valuation, and ICUMS workflow.'),
                    ('Port Operations & Logistics Management', '10 Oct 2026', '6 Weeks', 'Online', 'GHS 2,200', 'Advanced multimodal logistics, terminal management, and maritime law.')
                ]
                for c_title, c_date, c_dur, c_mode, c_fee, c_desc in default_courses:
                    cursor.execute("""
                        INSERT INTO cti_courses (title, start_date, duration, mode, fee, description)
                        VALUES (%s, %s, %s, %s, %s, %s)
                    """, (c_title, c_date, c_dur, c_mode, c_fee, c_desc))

            # Gallery Media Items table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS gallery_items (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    category VARCHAR(100) DEFAULT 'Conferences',
                    image_url TEXT,
                    grad_start VARCHAR(20) DEFAULT '#6B3E26',
                    grad_end VARCHAR(20) DEFAULT '#3E2418',
                    is_active BOOLEAN DEFAULT TRUE,
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("SELECT COUNT(*) as total FROM gallery_items WHERE deleted_at IS NULL")
            if cursor.fetchone()['total'] == 0:
                default_gallery = [
                    ('CUBAG Annual General Meeting 2026', 'Conferences', '', '#6B3E26', '#3E2418'),
                    ('Tema MPS Terminal Port Inspection', 'Port Operations', '', '#1A3A5C', '#0D2137'),
                    ('CTI Training Cohort Graduation', 'Education', '', '#1B5E20', '#0A3012'),
                    ('National Trade Summit — Accra', 'Leadership', '', '#4A1A42', '#2B0A28')
                ]
                for g_title, g_cat, g_url, g_g0, g_g1 in default_gallery:
                    cursor.execute("""
                        INSERT INTO gallery_items (title, category, image_url, grad_start, grad_end)
                        VALUES (%s, %s, %s, %s, %s)
                    """, (g_title, g_cat, g_url, g_g0, g_g1))

            # Port Operational Bulletins table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS port_bulletins (
                    id SERIAL PRIMARY KEY,
                    port_name VARCHAR(150) NOT NULL,
                    code VARCHAR(50),
                    status VARCHAR(50) DEFAULT 'Operational',
                    notice TEXT,
                    status_color VARCHAR(20) DEFAULT '#2E7D32',
                    is_active BOOLEAN DEFAULT TRUE,
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("SELECT COUNT(*) as total FROM port_bulletins WHERE deleted_at IS NULL")
            if cursor.fetchone()['total'] == 0:
                default_bulletins = [
                    ('Tema Port Terminal', 'TMP', 'Operational', 'Berth 3 & MPS Terminal 3 fully operational. Digital gate clearance active.', '#2E7D32'),
                    ('Takoradi Port Terminal', 'TKD', 'Operational', 'Dry bulk terminal expansion active. Expedited cocoa export loading in effect.', '#2E7D32'),
                    ('Kotoka Int. Airport', 'KIA', 'Operational', 'Air cargo terminal customs desk operating 24/7. New scanner equipment deployed.', '#2E7D32'),
                    ('Buipe Inland Port', 'BUP', 'Normal', 'Volta lake transport barge operations running on schedule.', '#2E7D32')
                ]
                for b_port, b_code, b_status, b_notice, b_color in default_bulletins:
                    cursor.execute("""
                        INSERT INTO port_bulletins (port_name, code, status, notice, status_color)
                        VALUES (%s, %s, %s, %s, %s)
                    """, (b_port, b_code, b_status, b_notice, b_color))

            # Seed default events if empty
            cursor.execute("SELECT COUNT(*) as total FROM events WHERE deleted_at IS NULL")
            if cursor.fetchone()['total'] == 0:
                default_events = [
                    ('CUBAG Annual General Meeting & Trade Summit 2026', 'Annual gathering of accredited customs brokers, forwarders and logistics executives.', '2026-08-24', '10:00 AM', 'Accra International Conference Centre', 500),
                    ('Customs Brokerage CTI Short Course — Batch 4', 'Comprehensive training covering ICUMS procedures and documentation.', '2026-10-15', '09:00 AM', 'CUBAG Training Hall, Tema', 120),
                    ('GRA Customs ICUMS Integration Workshop', 'Interactive technical session on digital customs clearance and cargo manifest submission.', '2026-11-10', '02:00 PM', 'Takoradi Port Auditorium', 200),
                    ('CUBAG Executive Board Monthly Meeting', 'Closed-door policy review and operational coordination with port authorities.', '2026-08-28', '03:00 PM', 'CUBAG Head Office, Accra', 30),
                    ('Port Operations Coordination Meeting — Tema', 'Stakeholder alignment with GPHA, MPS, and shipping lines on terminal throughput.', '2026-09-05', '10:00 AM', 'GPHA Boardroom, Tema Port', 50)
                ]
                for e_title, e_desc, e_date, e_time, e_loc, e_cap in default_events:
                    cursor.execute("""
                        INSERT INTO events (title, description, date, time, location, capacity)
                        VALUES (%s, %s, %s, %s, %s, %s)
                    """, (e_title, e_desc, e_date, e_time, e_loc, e_cap))

            # Admin audit logs with old_value, new_value, target_id, ip_address
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS admin_audit_logs (
                    id SERIAL PRIMARY KEY,
                    admin_id INT,
                    admin_name VARCHAR(150),
                    admin_email VARCHAR(150),
                    action VARCHAR(100) NOT NULL,
                    target_type VARCHAR(100),
                    target_id INT,
                    target_name VARCHAR(255),
                    old_value JSONB,
                    new_value JSONB,
                    details TEXT,
                    ip_address VARCHAR(100),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("""
                ALTER TABLE admin_audit_logs
                ADD COLUMN IF NOT EXISTS target_id INT,
                ADD COLUMN IF NOT EXISTS old_value JSONB,
                ADD COLUMN IF NOT EXISTS new_value JSONB,
                ADD COLUMN IF NOT EXISTS ip_address VARCHAR(100);
            """)

            # Add movement-specific columns to schedules if not exists
            cursor.execute("""
                ALTER TABLE schedules
                ADD COLUMN IF NOT EXISTS origin VARCHAR(150),
                ADD COLUMN IF NOT EXISTS destination VARCHAR(150),
                ADD COLUMN IF NOT EXISTS progress INT DEFAULT 0;
            """)

            # Support tickets table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS support_tickets (
                    id VARCHAR(50) PRIMARY KEY,
                    member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    subject VARCHAR(255) NOT NULL,
                    message TEXT,
                    status VARCHAR(50) DEFAULT 'open',
                    priority VARCHAR(50) DEFAULT 'medium',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    deleted_at TIMESTAMP NULL
                )
            """)

            # Ticket replies table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS ticket_replies (
                    id SERIAL PRIMARY KEY,
                    ticket_id VARCHAR(50) NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
                    author VARCHAR(150) NOT NULL,
                    message TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # License renewal/expiry history tracking
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS license_history (
                    id SERIAL PRIMARY KEY,
                    member_id INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    license_number VARCHAR(100),
                    start_date DATE,
                    expiry_date DATE,
                    duration_label VARCHAR(50),
                    archived_at TIMESTAMP DEFAULT NOW()
                )
            """)

            # Add soft-delete to support tickets (table may not exist yet)
            try:
                cursor.execute("""
                    ALTER TABLE support_tickets
                    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
                    ADD COLUMN IF NOT EXISTS priority VARCHAR(50) DEFAULT 'medium';
                """)
            except Exception as e:
                logger.exception("Failed to alter support_tickets: %s", e)
                conn.rollback()  # rollback just this failed ALTER

            # Seed official CUBAG fee schedules if empty
            cursor.execute("SELECT COUNT(*) as cnt FROM fee_schedules")
            res_cnt = cursor.fetchone()
            if res_cnt and res_cnt['cnt'] == 0:
                cursor.execute("""
                    INSERT INTO fee_schedules (fee_type, key, name, scale, scope, amount, description) VALUES
                    ('new_membership', 'new_cf_only', 'Clearing & Forwarding Only', 'all', 'cf_only', 1620.00, 'Subscription (120), Vetting (750), District (250), Clearing & Forwarding (500)'),
                    ('new_membership', 'new_consolidation', 'Consolidation Only', 'all', 'consolidation', 1720.00, 'Subscription (120), Vetting (750), District (250), Consolidation (600)'),
                    ('new_membership', 'new_cf_consolidation', 'Consolidation, Clearing & Forwarding', 'all', 'cf_consolidation', 2220.00, 'Subscription (120), Vetting (750), District (250), Consolidation (600), Clearing & Forwarding (500)'),
                    ('renewal', 'renewal_sme_without_consolidation', 'SMEs (Without Consolidation)', 'sme', 'without_consolidation', 2170.00, 'Subscription (120), Welfare (300), Admin (200), Legal/Audit (100), AGM (500), Customs Bond (350), CTI (600)'),
                    ('renewal', 'renewal_large_corporate_without_consolidation', 'Large Corporate (Without Consolidation)', 'large_corporate', 'without_consolidation', 4795.00, 'Subscription (1545), Welfare (400), Admin (300), Legal/Audit (500), AGM (500), Customs Bond (350), CTI (1200)'),
                    ('renewal', 'renewal_sme_with_consolidation', 'SMEs (With Consolidation)', 'sme', 'with_consolidation', 3456.00, 'Base SME (2170) + Consolidation (1286)'),
                    ('renewal', 'renewal_large_corporate_with_consolidation', 'Large Corporate (With Consolidation)', 'large_corporate', 'with_consolidation', 6081.00, 'Base Corporate (4795) + Consolidation (1286)');
                """)

            cursor.execute("""
                CREATE TABLE IF NOT EXISTS task_submission_files (
                    id SERIAL PRIMARY KEY,
                    submission_id INT NOT NULL,
                    filename VARCHAR(255),
                    original_name VARCHAR(255),
                    file_type VARCHAR(100),
                    file_size INT,
                    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (submission_id) REFERENCES task_submissions(id)
                )
            """)

            # News / Blog
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS news_blog (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    category VARCHAR(100) DEFAULT 'General',
                    content TEXT,
                    image_url TEXT,
                    author VARCHAR(100) DEFAULT 'CUBAG Admin',
                    deleted_at TIMESTAMP DEFAULT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("""
                ALTER TABLE news_blog ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;
            """)

            # Tracking which user has read which announcement (Cross-device sync)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS announcement_reads (
                    member_id INT NOT NULL,
                    announcement_id INT NOT NULL,
                    read_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (member_id, announcement_id),
                    FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
                    FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE CASCADE
                )
            """)

            # Rating history tracking table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS member_rating_history (
                    id SERIAL PRIMARY KEY,
                    member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    compliance_score INT NOT NULL,
                    star_rating DECIMAL(3,2) NOT NULL,
                    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Audit log for tracking admin actions (Make admin_id nullable to avoid FK issues on deletion)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS audit_log (
                    id SERIAL PRIMARY KEY,
                    admin_id INT REFERENCES members(id) ON DELETE SET NULL,
                    action VARCHAR(100) NOT NULL,
                    target_type VARCHAR(50),
                    target_id INT,
                    target_name VARCHAR(255),
                    details TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Ensure it's nullable if already exists (safe DDL execution)
            try:
                cursor.execute("ALTER TABLE audit_log ALTER COLUMN admin_id DROP NOT NULL")
            except Exception as ddl_err:
                logger.debug("ALTER TABLE audit_log admin_id DROP NOT NULL skipped: %s", ddl_err)
                conn.rollback()

            try:
                cursor.execute("ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS ip_address VARCHAR(100) DEFAULT '127.0.0.1'")
            except Exception as ddl_err:
                logger.debug("ALTER TABLE audit_log add ip_address skipped: %s", ddl_err)
                conn.rollback()

            # Platform-wide configuration (fees, bank accounts, payment settings, etc.)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS platform_settings (
                    id SERIAL PRIMARY KEY,
                    config_key VARCHAR(100) UNIQUE NOT NULL,
                    config_value JSONB,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Sub-admin permissions — one row per (sub_admin, module) pair
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS sub_admin_permissions (
                    id SERIAL PRIMARY KEY,
                    sub_admin_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    permission_key VARCHAR(60) NOT NULL,
                    granted BOOLEAN DEFAULT TRUE,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE (sub_admin_id, permission_key)
                )
            """)

            # Messaging table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS messages (
                    id SERIAL PRIMARY KEY,
                    sender_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    receiver_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
                    message TEXT NOT NULL,
                    read_at TIMESTAMP,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_at TIMESTAMP")

            # Initialise default platform fees settings if absent
            cursor.execute("SELECT COUNT(*) FROM platform_settings WHERE config_key = 'fees_settings'")
            if cursor.fetchone()['count'] == 0:
                import json
                default_fees = json.dumps({
                    "corporate": {"annual_fee": 1500, "registration_fee": 500, "late_fine_per_month": 100},
                    "individual": {"annual_fee": 600, "registration_fee": 200, "late_fine_per_month": 50},
                    "bank_accounts": []
                })
                cursor.execute(
                    "INSERT INTO platform_settings (config_key, config_value) VALUES ('fees_settings', %s::jsonb)",
                    (default_fees,)
                )

            # Compliance Settings
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS compliance_settings (
                    id SERIAL PRIMARY KEY,
                    licensing_weight INT DEFAULT 40,
                    financial_weight INT DEFAULT 30,
                    attendance_weight INT DEFAULT 20,
                    manual_weight INT DEFAULT 10,
                    payment_punctual INT DEFAULT 25,
                    payment_history INT DEFAULT 15,
                    license_active INT DEFAULT 15,
                    license_inactive INT DEFAULT 5,
                    task_completion INT DEFAULT 15,
                    survey_completion INT DEFAULT 10,
                    agm_active INT DEFAULT 10,
                    agm_inactive INT DEFAULT 5,
                    renewal_fee NUMERIC(10,2) DEFAULT 500.00,
                    customs_licence_fee NUMERIC(10,2) DEFAULT 750.00,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS payment_punctual INT DEFAULT 25")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS payment_history INT DEFAULT 15")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS license_active INT DEFAULT 15")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS license_inactive INT DEFAULT 5")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS task_completion INT DEFAULT 15")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS survey_completion INT DEFAULT 10")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS agm_active INT DEFAULT 10")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS agm_inactive INT DEFAULT 5")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS renewal_fee NUMERIC(10,2) DEFAULT 500.00")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS customs_licence_fee NUMERIC(10,2) DEFAULT 750.00")
            cursor.execute("ALTER TABLE compliance_settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            
            # Insert default if empty
            cursor.execute("SELECT COUNT(*) FROM compliance_settings")
            if cursor.fetchone()['count'] == 0:
                cursor.execute("INSERT INTO compliance_settings DEFAULT VALUES")

            # ── Performance Indexes ──────────────────────────────────────────
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_members_status ON members(status)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_members_role ON members(role)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_payments_member_id ON payments(member_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at DESC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_announcements_deleted_at ON announcements(deleted_at) WHERE deleted_at IS NULL")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_notifications_member_id ON notifications(member_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_notifications_read_at ON notifications(read_at)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_notifications_deleted_at ON notifications(deleted_at) WHERE deleted_at IS NULL")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(sender_id, receiver_id, created_at DESC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_messages_unread ON messages(receiver_id, read_at) WHERE read_at IS NULL")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_member_rating_history_member_id ON member_rating_history(member_id, recorded_at DESC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_event_attendance_member_id ON event_attendance(member_id)")
            # ── Additional performance indexes for slow endpoints ─────────────
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_events_date ON events(date ASC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_schedules_type ON schedules(type)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_schedules_created_at ON schedules(created_at DESC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_schedules_status ON schedules(status)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_tasks_member_id ON tasks(member_id, due_date ASC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_task_submissions_member_task ON task_submissions(member_id, task_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_platform_settings_key ON platform_settings(config_key)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_announcements_created_at ON announcements(created_at DESC) WHERE deleted_at IS NULL")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_license_history_member_id ON license_history(member_id, archived_at DESC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_members_email ON members(email)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_member_documents_member_status ON member_documents(member_id, status)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status, updated_at DESC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_support_tickets_member_id ON support_tickets(member_id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_ticket_replies_ticket_id ON ticket_replies(ticket_id, created_at ASC)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_sub_admin_permissions_sub_admin ON sub_admin_permissions(sub_admin_id, permission_key)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_target_type ON audit_log(target_type)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_admin_id ON audit_log(admin_id)")

        conn.commit()
        logger.info("[OK] Database tables initialised successfully.")
    except Exception as e:
        logger.exception("[ERROR] DB init error: %s", e)
    finally:
        conn.close()
