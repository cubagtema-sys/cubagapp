import 'package:flutter/material.dart';
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
