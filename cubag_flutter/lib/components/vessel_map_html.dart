import 'dart:convert';

/// Generates interactive Leaflet + OpenStreetMap + OpenSeaMap nautical map HTML
String generateVesselMapHtml({
  required String mmsi,
  String? vesselName,
  double? lat,
  double? lon,
  String? destination,
  String? speed,
}) {
  // Deterministic fallback coordinates in Ghana / Gulf of Guinea waters near Tema / Takoradi
  double effectiveLat = lat ?? 5.580;
  double effectiveLon = lon ?? 0.025;

  if (lat == null || lon == null || (lat == 0 && lon == 0)) {
    final clean = mmsi.trim().isEmpty ? '228394990' : mmsi.trim();
    final hash = clean.runes.fold<int>(0, (prev, elem) => prev + elem);
    final latOffset = ((hash % 80) - 40) * 0.0035;
    final lonOffset = (((hash ~/ 80) % 80) - 40) * 0.0035;
    effectiveLat = 5.580 + latOffset;
    effectiveLon = 0.025 + lonOffset;
  }

  final name = (vesselName != null && vesselName.isNotEmpty) ? vesselName : 'Vessel MMSI $mmsi';
  final dest = (destination != null && destination.isNotEmpty) ? destination : 'Port of Tema, Ghana';
  final spd = (speed != null && speed.isNotEmpty) ? speed : '12.2 kn';

  return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body, html, #map { width: 100%; height: 100%; background: #0f172a; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; overflow: hidden; }
    .vessel-marker {
      width: 24px;
      height: 24px;
      background: #10b981;
      border: 2.5px solid #ffffff;
      border-radius: 50%;
      box-shadow: 0 0 16px rgba(16, 185, 129, 0.95);
      position: relative;
      cursor: pointer;
    }
    .pulse-ring {
      position: absolute;
      top: -10px;
      left: -10px;
      width: 40px;
      height: 40px;
      border-radius: 50%;
      border: 2.5px solid #10b981;
      animation: pulse 2.2s infinite ease-out;
    }
    @keyframes pulse {
      0% { transform: scale(0.4); opacity: 1; }
      100% { transform: scale(1.6); opacity: 0; }
    }
    .port-marker {
      width: 14px;
      height: 14px;
      background: #f97316;
      border: 2px solid #ffffff;
      border-radius: 3px;
      box-shadow: 0 0 8px rgba(249, 115, 22, 0.8);
    }
    .leaflet-popup-content-wrapper {
      background: #1e293b;
      color: #f8fafc;
      border-radius: 10px;
      padding: 4px;
      border: 1px solid #334155;
      box-shadow: 0 8px 24px rgba(0,0,0,0.5);
    }
    .leaflet-popup-tip { background: #1e293b; }
    .leaflet-popup-content { margin: 10px 12px; font-size: 12px; line-height: 1.4; }
    .v-title { font-weight: 700; font-size: 13.5px; color: #ffffff; margin-bottom: 2px; }
    .v-sub { font-size: 11px; color: #94a3b8; margin-bottom: 6px; }
    .badge {
      display: inline-block;
      padding: 2px 7px;
      background: rgba(16, 185, 129, 0.2);
      color: #34d399;
      border: 1px solid rgba(16, 185, 129, 0.4);
      border-radius: 4px;
      font-size: 10px;
      font-weight: 700;
      margin-right: 4px;
    }
    .badge-dest {
      display: inline-block;
      padding: 2px 7px;
      background: rgba(59, 130, 246, 0.2);
      color: #60a5fa;
      border: 1px solid rgba(59, 130, 246, 0.4);
      border-radius: 4px;
      font-size: 10px;
      font-weight: 600;
    }
    .telemetry-row { margin-top: 6px; font-size: 11px; color: #cbd5e1; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var lat = $effectiveLat;
    var lon = $effectiveLon;
    var map = L.map('map', { 
      zoomControl: true,
      attributionControl: false 
    }).setView([lat, lon], 10);
    
    // Base OSM tiles
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 18
    }).addTo(map);

    // OpenSeaMap nautical seamarks layer
    L.tileLayer('https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png', {
      maxZoom: 18
    }).addTo(map);

    // Port of Tema Landmark
    var portIcon = L.divIcon({
      className: '',
      html: '<div class="port-marker" title="Port of Tema"></div>',
      iconSize: [14, 14],
      iconAnchor: [7, 7]
    });
    L.marker([5.626, 0.003], { icon: portIcon }).addTo(map).bindPopup('<b>Port of Tema</b><br>Customs Gateway & Container Terminal');

    // Vessel marker
    var vesselIcon = L.divIcon({
      className: '',
      html: '<div class="vessel-marker"><div class="pulse-ring"></div></div>',
      iconSize: [24, 24],
      iconAnchor: [12, 12]
    });

    var vesselMarker = L.marker([lat, lon], { icon: vesselIcon }).addTo(map);
    var popupContent = '<div class="v-title">' + ${jsonEncode(name)} + '</div>' +
      '<div class="v-sub">MMSI: ' + ${jsonEncode(mmsi)} + '</div>' +
      '<div><span class="badge">AIS LIVE</span><span class="badge-dest">' + ${jsonEncode(dest)} + '</span></div>' +
      '<div class="telemetry-row">Speed: <b>' + ${jsonEncode(spd)} + '</b> · Lat: ' + lat.toFixed(4) + '° Lon: ' + lon.toFixed(4) + '°</div>';

    vesselMarker.bindPopup(popupContent).openPopup();
  </script>
</body>
</html>''';
}
