"""
Gunicorn configuration for CUBAG Backend.

Local dev:  gunicorn -c gunicorn.conf.py server:app
Production: Procfile already references gunicorn — this file is auto-detected.
"""
import multiprocessing
import os

# ── Workers ────────────────────────────────────────────────────────────────────
# Rule of thumb: (2 × CPU cores) + 1 for I/O-bound apps (DB, HTTP calls)
workers = int(os.getenv('WEB_CONCURRENCY', multiprocessing.cpu_count() * 2 + 1))
worker_class = 'sync'   # Use 'gthread' if you add threading support
threads = 2             # Threads per worker (handles concurrent Socket.IO polls)

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
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s %(D)sµs'

# ── Process naming ─────────────────────────────────────────────────────────────
proc_name = 'cubag-backend'

# ── Hooks ─────────────────────────────────────────────────────────────────────
def on_starting(server):
    server.log.info("🚀 CUBAG Backend starting with %d workers on port %d", workers, port)

def worker_abort(worker):
    worker.log.error("⚠️  Worker %s aborted (timeout exceeded)", worker.pid)
