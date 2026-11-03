// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'vessel_map_html.dart';

Widget buildIframe(
  String mmsi, {
  String? vesselName,
  double? lat,
  double? lon,
  String? destination,
  String? speed,
}) {
  final cleanMmsi = mmsi.trim().isEmpty ? '228394990' : mmsi.trim();
  final viewType = 'maritime-map-$cleanMmsi';
  final htmlContent = generateVesselMapHtml(
    mmsi: cleanMmsi,
    vesselName: vesselName,
    lat: lat,
    lon: lon,
    destination: destination,
    speed: speed,
  );

  try {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) => html.IFrameElement()
        ..srcdoc = htmlContent
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%',
    );
  } catch (_) {
    // Factory already registered — safe to ignore
  }

  return HtmlElementView(viewType: viewType);
}
