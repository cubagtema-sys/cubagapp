import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'cors_image_stub.dart'
    if (dart.library.html) 'cors_image_web.dart'
    if (dart.library.io) 'cors_image_mobile.dart'
    as platform_impl;

class CorsImageWidget extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CorsImageWidget({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    // SEC-04: sensitive documents need a short-lived signed URL.
    if (ApiService.isSensitiveDocumentUrl(url)) {
      return FutureBuilder<String>(
        future: ApiService.signedDocumentUrl(url),
        builder: (context, snap) {
          if (!snap.hasData) {
            return placeholder ?? SizedBox(width: width, height: height);
          }
          return platform_impl.buildCorsImage(
            snap.data!,
            width: width,
            height: height,
            fit: fit,
            placeholder: placeholder,
            errorWidget: errorWidget,
          );
        },
      );
    }
    return platform_impl.buildCorsImage(
      url,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }
}
