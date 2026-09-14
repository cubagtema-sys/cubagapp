import 'package:flutter/material.dart';
import 'iframe_stub.dart'
    if (dart.library.html) 'iframe_web.dart'
    if (dart.library.io) 'iframe_mobile.dart'
    as platform_impl;

class IframeWidget extends StatelessWidget {
  final String mmsi;

  const IframeWidget({super.key, required this.mmsi});

  @override
  Widget build(BuildContext context) {
    return platform_impl.buildIframe(mmsi);
  }
}
