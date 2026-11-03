import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'vessel_map_html.dart';

Widget buildIframe(
  String mmsi, {
  String? vesselName,
  double? lat,
  double? lon,
  String? destination,
  String? speed,
}) {
  return MobileWebViewMap(
    mmsi: mmsi,
    vesselName: vesselName,
    lat: lat,
    lon: lon,
    destination: destination,
    speed: speed,
  );
}

class MobileWebViewMap extends StatefulWidget {
  final String mmsi;
  final String? vesselName;
  final double? lat;
  final double? lon;
  final String? destination;
  final String? speed;

  const MobileWebViewMap({
    super.key,
    required this.mmsi,
    this.vesselName,
    this.lat,
    this.lon,
    this.destination,
    this.speed,
  });

  @override
  State<MobileWebViewMap> createState() => _MobileWebViewMapState();
}

class _MobileWebViewMapState extends State<MobileWebViewMap> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final htmlContent = generateVesselMapHtml(
      mmsi: widget.mmsi,
      vesselName: widget.vesselName,
      lat: widget.lat,
      lon: widget.lon,
      destination: widget.destination,
      speed: widget.speed,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..loadHtmlString(htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
