import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api_service.dart';
import '../utils/session_storage.dart';
import 'cors_image_widget.dart';

const Color _kPrimary = Color(0xFF9E4A28);

/// High-performance In-App Document Viewer for CUBAG.
/// Supports in-app viewing of PDFs, uploaded compliance documents, certificates, and images
/// on iOS, Android, and Web without forcing the user out of the application.
class InAppDocumentViewer extends StatefulWidget {
  final String url;
  final String title;
  final String? subtitle;

  const InAppDocumentViewer({
    super.key,
    required this.url,
    required this.title,
    this.subtitle,
  });

  /// Static helper to open the In-App Document Viewer as a full-screen modal route.
  static Future<void> show(
    BuildContext context, {
    required String url,
    String? title,
    String? subtitle,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    // Resolve relative URL to full backend URL using ApiService.resolveImageUrl
    String resolvedUrl = ApiService.resolveImageUrl(cleanUrl);

    // Attach auth token if hitting protected backend endpoints (not static files)
    if (!resolvedUrl.contains('/static/') && (resolvedUrl.contains('/api/') || resolvedUrl.contains('/members/'))) {
      try {
        final token = await SessionStorage.instance.getString('cubag_token');
        if (token != null && token.isNotEmpty && !resolvedUrl.contains('token=')) {
          final separator = resolvedUrl.contains('?') ? '&' : '?';
          resolvedUrl = '$resolvedUrl${separator}token=${Uri.encodeComponent(token)}';
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => InAppDocumentViewer(
          url: resolvedUrl,
          title: title ?? 'Document Viewer',
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  State<InAppDocumentViewer> createState() => _InAppDocumentViewerState();
}

class _InAppDocumentViewerState extends State<InAppDocumentViewer> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  String? _errorMessage;
  bool _isImage = false;

  @override
  void initState() {
    super.initState();
    _checkFileType();
    if (!_isImage && !kIsWeb) {
      _initWebView();
    }
  }

  void _checkFileType() {
    final lower = widget.url.toLowerCase().split('?').first;
    _isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }

  void _initWebView() {
    String targetUrl = widget.url;

    // On Android, WebViews do not have built-in native PDF rendering like iOS WKWebView does.
    // If the file is a PDF on Android, load it via Google Docs Viewer for seamless in-app preview.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final clean = widget.url.toLowerCase().split('?').first;
      if (clean.endsWith('.pdf') || widget.url.contains('certificate')) {
        targetUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.url)}';
      }
    }

    try {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() {
                  _loadingProgress = progress / 100.0;
                  if (progress >= 100) {
                    _isLoading = false;
                  }
                });
              }
            },
            onPageStarted: (String url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
              }
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (error.errorCode == -999 || error.description.contains('cancelled')) return;
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = error.description;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(targetUrl));
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
    }
  }

  Future<void> _shareDocument() async {
    try {
      await Share.share(
        widget.url,
        subject: widget.title,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share document: $e')),
        );
      }
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF141213) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF221F20) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1F1A1C);
    final textMuted = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        iconTheme: IconThemeData(color: textPrimary),
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                widget.subtitle!,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            tooltip: 'Share Document Link',
            onPressed: _shareDocument,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            tooltip: 'Open in Browser',
            onPressed: _openExternal,
          ),
          if (!_isImage && _webViewController != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Reload',
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _webViewController?.reload();
              },
            ),
          const SizedBox(width: 4),
        ],
        bottom: _isLoading && !_isImage
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2.5),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(_kPrimary),
                  minHeight: 2.5,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: _buildBody(cardBg, textPrimary, textMuted),
      ),
    );
  }

  Widget _buildBody(Color cardBg, Color textPrimary, Color textMuted) {
    if (_isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: CorsImageWidget(
            url: widget.url,
            fit: BoxFit.contain,
            placeholder: const Center(
              child: CircularProgressIndicator(color: _kPrimary),
            ),
            errorWidget: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load image preview.',
                    style: GoogleFonts.inter(color: textMuted),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open Externally'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Could not display document',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: textMuted),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _errorMessage = null;
                      });
                      _webViewController?.reload();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open External'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_webViewController != null) {
      return Stack(
        children: [
          WebViewWidget(controller: _webViewController!),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: _kPrimary),
            ),
        ],
      );
    }

    // Web fallback or unsupported preview
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.picture_as_pdf_rounded, size: 56, color: _kPrimary),
          const SizedBox(height: 14),
          Text(
            widget.title,
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('View / Download Document'),
          ),
        ],
      ),
    );
  }
}
