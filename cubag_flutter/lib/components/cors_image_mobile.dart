import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  final int targetWidth = (width != null && width.isFinite && width > 0)
      ? (width * 2).toInt()
      : 1000;
  final int targetHeight = (height != null && height.isFinite && height > 0)
      ? (height * 2).toInt()
      : 1000;
  return CachedNetworkImage(
    imageUrl: resolvedUrl,
    width: width,
    height: height,
    fit: fit,
    memCacheWidth: targetWidth,
    memCacheHeight: targetHeight,
    placeholder: placeholder != null ? (context, url) => placeholder : null,
    errorWidget: errorWidget != null
        ? (context, url, error) => errorWidget
        : null,
  );
}
