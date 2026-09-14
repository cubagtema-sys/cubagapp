#!/bin/bash
# Kill any process currently occupying port 5005
PORT=5005
PID=$(lsof -ti:$PORT)

if [ -n "$PID" ]; then
  echo "[Info] Killing process(es) on port $PORT (PID: $PID)..."
  kill -9 $PID 2>/dev/null
  sleep 1
else
  echo "[Info] Port $PORT is clean."
fi

echo "[Info] Starting CUBAG Backend Server..."
python3 server.py
