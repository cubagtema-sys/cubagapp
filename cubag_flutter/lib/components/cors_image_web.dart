// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../services/api_service.dart';

Widget buildCorsImage(
  String url, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget? placeholder,
  Widget? errorWidget,
}) {
  final resolvedUrl = ApiService.resolveImageUrl(url);
  final viewType = 'cors-image-${resolvedUrl.hashCode}_${fit.name}';

  try {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = resolvedUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';

      img.onError.listen((_) {
        final serverBase = ApiService.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
        final fallbackUrl = '$serverBase/uploads/doc_placeholder.png';
        if (img.src != fallbackUrl) {
          img.src = fallbackUrl;
        }
      });

      if (fit == BoxFit.cover) {
        img.style.objectFit = 'cover';
      } else if (fit == BoxFit.contain) {
        img.style.objectFit = 'contain';
      } else if (fit == BoxFit.fill) {
        img.style.objectFit = 'fill';
      }
      return img;
    });
  } catch (_) {
    // Factory already registered — safe to ignore
  }

  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(viewType: viewType),
  );
}
