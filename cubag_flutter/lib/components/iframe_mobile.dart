import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildIframe(String mmsi) {
  return MobileWebViewMap(mmsi: mmsi);
}

class MobileWebViewMap extends StatefulWidget {
  final String mmsi;
  const MobileWebViewMap({super.key, required this.mmsi});

  @override
  State<MobileWebViewMap> createState() => _MobileWebViewMapState();
}

class _MobileWebViewMapState extends State<MobileWebViewMap> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(
        Uri.parse(
          'https://www.marinetraffic.com/en/ais/embed/mmsi:${widget.mmsi}/zoom:8/maptype:1/show_vessels:true',
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
