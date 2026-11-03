// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

Widget buildDocPreview(String url, String viewKey) {
  final resolvedUrl = ApiService.resolveImageUrl(url);
  final isImage = resolvedUrl.toLowerCase().contains('.png') ||
      resolvedUrl.toLowerCase().contains('.jpg') ||
      resolvedUrl.toLowerCase().contains('.jpeg') ||
      resolvedUrl.toLowerCase().contains('.webp') ||
      resolvedUrl.toLowerCase().contains('.gif');

  final viewType = 'doc-frame-${viewKey.hashCode}_${resolvedUrl.hashCode}';

  try {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) {
        if (isImage) {
          final img = html.ImageElement()
            ..src = resolvedUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain';
          img.onError.listen((_) {
            final serverBase = ApiService.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
            img.src = '$serverBase/uploads/doc_placeholder.png';
          });
          return img;
        }

        final iframe = html.IFrameElement()
          ..src = resolvedUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;
        return iframe;
      },
    );
  } catch (_) {
    // Factory already registered — safe to ignore
  }

  return Stack(
    children: [
      HtmlElementView(viewType: viewType),
      Positioned(
        bottom: 8,
        right: 8,
        child: Material(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              final uri = Uri.tryParse(resolvedUrl);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Open in Tab',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
