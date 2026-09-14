// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

Widget buildDocPreview(String url, String viewKey) {
  final viewType = 'doc-preview-$viewKey';
  try {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) => html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true,
    );
  } catch (_) {
    // Factory already registered — safe to ignore
  }
  return HtmlElementView(viewType: viewType);
}
