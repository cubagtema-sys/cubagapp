import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildDocPreview(String url, String viewKey) {
  return _MobileDocPreview(url: url, key: ValueKey(viewKey));
}

class _MobileDocPreview extends StatefulWidget {
  final String url;
  const _MobileDocPreview({required this.url, super.key});

  @override
  State<_MobileDocPreview> createState() => _MobileDocPreviewState();
}

class _MobileDocPreviewState extends State<_MobileDocPreview> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    String targetUrl = widget.url;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final clean = widget.url.toLowerCase().split('?').first;
      if (clean.endsWith('.pdf') || widget.url.contains('certificate')) {
        targetUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.url)}';
      }
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(targetUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF9E4A28)),
          ),
      ],
    );
  }
}
