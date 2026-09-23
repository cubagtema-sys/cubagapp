FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

# psycopg2-binary, gevent and eventlet all ship manylinux wheels, so no
# compiler toolchain is needed. Install deps first for layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# App code + the prebuilt Flutter web bundle in static/ (see .dockerignore
# for what is deliberately excluded: venv, .env, uploads, dist, tests).
COPY . .

EXPOSE 8080

# Single worker is REQUIRED: flask-socketio runs in 'threading' async_mode with
# in-process room state, and APScheduler (jobs.py) runs in-process. More than
# one worker would split socket rooms and fire scheduled jobs multiple times.
# gunicorn auto-selects the gthread worker when --threads > 1.
CMD gunicorn -w 1 --threads 8 -b 0.0.0.0:${PORT} server:app
