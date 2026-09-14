from flask_socketio import SocketIO

socketio = SocketIO(
    cors_allowed_origins="*",
    async_mode='threading',
    # Allow both WebSocket and HTTP long-polling fallback
    transports=['websocket', 'polling'],
    # Suppress verbose engine.io connection logs
    engineio_logger=False,
    logger=False,
)
