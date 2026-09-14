import json
import os
import threading
import time
import websocket
import logging
from datetime import datetime, timezone
from socket_instance import socketio

logger = logging.getLogger(__name__)

AIS_API_KEY = os.getenv('AIS_API_KEY')
# Ghana Coastal Waters Bounding Box
GHANA_BBOX = [[[4.0, -4.0], [6.5, 2.0]]]

class AISStreamManager:
    def __init__(self):
        self.thread = None
        self.active_vessels = {}
        self.is_running = False
        self.tracked_mmsis = set()
        self.tracked_names = set()
        self.ws = None
        self.lock = threading.Lock()

    def start(self):
        if not AIS_API_KEY:
            logger.warning("[AIS] API Key missing. AIS stream will start in simulation mode.")
            self.is_running = True
            self.thread = threading.Thread(target=self._run_simulation, daemon=True, name="ais-sim-thread")
            self.thread.start()
            return

        if self.is_running:
            return

        self.is_running = True
        self.thread = threading.Thread(target=self._run_forever, daemon=True, name="ais-stream-thread")
        self.thread.start()
        logger.info("[AIS] Background stream thread started.")

    def add_track(self, query):
        if not query: return
        query_str = str(query).strip()

        try:
            if query_str.isdigit() and len(query_str) == 9:
                mmsi_int = int(query_str)
                with self.lock:
                    if mmsi_int in self.tracked_mmsis: return
                    self.tracked_mmsis.add(mmsi_int)
                logger.info(f"[AIS] Now tracking MMSI: {mmsi_int}")
            else:
                if len(query_str) < 3: return
                with self.lock:
                    if query_str.lower() in [n.lower() for n in self.tracked_names]: return
                    self.tracked_names.add(query_str)
                logger.info(f"[AIS] Now tracking Name: {query_str}")
        except Exception as e:
            logger.error(f"[AIS] add_track error: {e}")
            return

        if self.ws and self.ws.sock and self.ws.sock.connected:
            self._send_subscription(self.ws)

    def _run_forever(self):
        retry_delay = 15
        while self.is_running:
            try:
                logger.info("[AIS] Connecting to aisstream.io...")
                self.ws = websocket.WebSocketApp(
                    "wss://stream.aisstream.io/v0/stream",
                    on_open=self._on_open,
                    on_message=self._on_message,
                    on_error=self._on_error,
                    on_close=self._on_close
                )
                self.ws.run_forever(ping_interval=30, ping_timeout=10)
            except Exception as e:
                logger.error(f"[AIS] Manager error: {e}")

            logger.info(f"[AIS] Disconnected. Retrying in {retry_delay}s...")
            time.sleep(retry_delay)
            retry_delay = min(retry_delay * 2, 300)

    def _on_open(self, ws):
        logger.info("[AIS] WebSocket Connected.")
        self._send_subscription(ws)

    def _send_subscription(self, ws):
        subscribe_message = {
            "APIKey": AIS_API_KEY,
            "BoundingBoxes": GHANA_BBOX,
            "FilterMessageTypes": ["PositionReport", "ShipStaticData"]
        }

        with self.lock:
            mmsi_list = [int(m) for m in list(self.tracked_mmsis)[:50]]
            name_list = list(self.tracked_names)[:20]

        if mmsi_list or name_list:
            if mmsi_list: subscribe_message["FiltersShipMMSI"] = mmsi_list
            if name_list: subscribe_message["FiltersShipName"] = name_list
            # Expand to worldwide if we are tracking specific ships
            subscribe_message["BoundingBoxes"] = [[[-90, -180], [90, 180]]]

        try:
            ws.send(json.dumps(subscribe_message))
            logger.info(f"[AIS] Subscription sent (Ghana + {len(mmsi_list)} MMSI + {len(name_list)} Names)")
        except Exception as e:
            logger.error(f"[AIS] Failed to send subscription: {e}")

    def _on_message(self, ws, message_json):
        try:
            msg = json.loads(message_json)
            self._handle_ais_message(msg)
        except Exception as e:
            logger.debug(f"[AIS] Failed to parse WS message: {e}")

    def _on_error(self, ws, error):
        logger.warning(f"[AIS] WebSocket interrupted ({error}). Auto-reconnecting...")

    def _on_close(self, ws, code, msg):
        logger.info(f"[AIS] WebSocket Closed: {msg}")

    def _handle_ais_message(self, msg):
        try:
            metadata = msg.get("MetaData", {})
            mmsi = metadata.get("MMSI")
            if not mmsi: return

            msg_type = msg.get("MessageType")
            ship_name = metadata.get("ShipName", "Unknown").strip()
            now_str = datetime.now(timezone.utc).isoformat()

            with self.lock:
                vessel = self.active_vessels.get(mmsi, {
                    'mmsi': mmsi,
                    'name': ship_name,
                    'type': 'Unknown',
                    'status': 'Unknown',
                    'lat': metadata.get('latitude'),
                    'lng': metadata.get('longitude'),
                    'last_update': now_str,
                    'last_emit': 0,
                    'imo': '—',
                    'callsign': '—',
                    'flag': 'Unknown',
                    'destination': '—',
                    'eta': '—',
                    'region': 'Detecting...'
                })

                if msg_type == "PositionReport":
                    pos = msg['Message']['PositionReport']
                    vessel['lat'] = pos.get('Latitude')
                    vessel['lng'] = pos.get('Longitude')
                    vessel['speed'] = pos.get('Sog', 0)
                    vessel['status'] = self._decode_nav_status(pos.get('NavigationalStatus'))
                    vessel['region'] = self._estimate_region(vessel['lat'], vessel['lng'])
                    vessel['last_update'] = now_str

                elif msg_type == "ShipStaticData":
                    static = msg['Message']['ShipStaticData']
                    vessel['name'] = static.get('Name', vessel['name']).strip()
                    vessel['imo'] = static.get('Imo', '—')
                    vessel['callsign'] = static.get('CallSign', '—').strip()
                    vessel['type'] = self._decode_ship_type(static.get('Type'))
                    vessel['destination'] = static.get('Destination', '—').strip()
                    vessel['eta'] = self._format_eta(static.get('Eta'))
                    vessel['last_update'] = now_str

                self.active_vessels[mmsi] = vessel

                # Throttle socket emissions (max every 5s per vessel)
                curr_ts = time.time()
                if curr_ts - vessel.get('last_emit', 0) > 5:
                    vessel['last_emit'] = curr_ts
                    socketio.emit('vessel_update', vessel)
        except Exception as e:
            logger.debug(f"[AIS] Message handle error: {e}")

    def _estimate_region(self, lat, lng):
        if not lat or not lng: return "Global Network"
        if 4 <= lat <= 7 and -4 <= lng <= 2: return "Ghana Coastal Waters"
        return "International Waters"

    def _decode_ship_type(self, type_id):
        if not type_id: return "Unknown"
        if 70 <= type_id <= 79: return "Cargo Ship"
        if 80 <= type_id <= 89: return "Tanker"
        return f"Ship ({type_id})"

    def _decode_nav_status(self, status_id):
        statuses = {0: "Underway", 1: "At Anchor", 5: "Moored"}
        return statuses.get(status_id, "Unknown")

    def _format_eta(self, eta):
        if not eta: return "—"
        try:
            m, d, h = eta.get('Month', 0), eta.get('Day', 0), eta.get('Hour', 0)
            if m == 0: return "—"
            return f"2026-{m:02d}-{d:02d} {h:02d}:00 UTC"
        except Exception as e:
            logger.debug(f"[AIS] ETA format error: {e}")
            return "—"

    def _run_simulation(self):
        import random
        # Mock data for when API key is missing
        vessels = [
            {'mmsi': 563297800, 'name': 'Maersk Charleston', 'lat': 5.5, 'lng': -0.1, 'speed': 12},
            {'mmsi': 477174700, 'name': 'Maersk Cubango', 'lat': 5.6, 'lng': -0.2, 'speed': 14},
        ]
        while self.is_running:
            for v in vessels:
                v['lat'] += random.uniform(-0.01, 0.01)
                v['lng'] += random.uniform(-0.01, 0.01)
                v['last_update'] = datetime.now(timezone.utc).isoformat()
                socketio.emit('vessel_update', v)
            time.sleep(5)

ais_manager = AISStreamManager()
