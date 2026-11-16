"""
Gunicorn configuration for CUBAG Backend.

Local dev:  gunicorn -c gunicorn.conf.py server:app
Production: Procfile already references gunicorn — this file is auto-detected.
"""
import os

# ── Workers ────────────────────────────────────────────────────────────────────
# Single worker is REQUIRED: Flask-SocketIO keeps room state in-process and
# APScheduler runs in-process, so extra workers would split rooms and fire
# scheduled jobs more than once. Scale with threads, not workers.
workers = int(os.getenv('WEB_CONCURRENCY', 1))
worker_class = 'sync'   # gunicorn switches to gthread automatically when threads > 1
threads = int(os.getenv('GUNICORN_THREADS', 32))

# ── Binding ────────────────────────────────────────────────────────────────────
port = int(os.getenv('PORT', 5005))
bind = f'0.0.0.0:{port}'

# ── Timeouts ──────────────────────────────────────────────────────────────────
timeout = 120           # Kill worker if request takes longer than 120s
graceful_timeout = 30   # Wait 30s for in-flight requests on SIGTERM
keepalive = 5           # Reuse HTTP connections for 5s

# ── Logging ───────────────────────────────────────────────────────────────────
accesslog = '-'         # Stdout
errorlog  = '-'         # Stderr
loglevel  = os.getenv('LOG_LEVEL', 'info')
# Path only (no query string): the socket client used to put the JWT in ?token=.
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(m)s %(U)s %(H)s" %(s)s %(b)s %(D)sµs'

# ── Process naming ─────────────────────────────────────────────────────────────
proc_name = 'cubag-backend'

# ── Hooks ─────────────────────────────────────────────────────────────────────
def on_starting(server):
    server.log.info("🚀 CUBAG Backend starting with %d workers on port %d", workers, port)

def worker_abort(worker):
    worker.log.error("⚠️  Worker %s aborted (timeout exceeded)", worker.pid)
