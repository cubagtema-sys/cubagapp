import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';

const _kOrange = Color(0xFFFF5000);

class AdminQrScannerPage extends StatefulWidget {
  final Function(String memberId) onScan;
  const AdminQrScannerPage({super.key, required this.onScan});

  @override
  State<AdminQrScannerPage> createState() => _AdminQrScannerPageState();
}

class _AdminQrScannerPageState extends State<AdminQrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null) {
        setState(() {
          _isProcessing = true;
        });

        // Expected format: https://cubag-api-server.fly.dev/#/verify-member?id=CUBAG-2026-0001
        // Or /verify-member/123 or raw member number
        String memberId = '';
        if (code.contains('id=')) {
          final uri = Uri.tryParse(code);
          if (uri != null && uri.queryParameters['id'] != null) {
            memberId = uri.queryParameters['id']!;
          } else {
            memberId = code.split('id=').last.split('&').first;
          }
        } else if (code.contains('/verify-member/')) {
          memberId = code.split('/verify-member/').last.split('?').first;
        } else {
          memberId = code.trim();
        }

        // Call callback and pop
        widget.onScan(memberId);
        if (mounted) {
          context.pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Overlay UI
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _kOrange, width: 4),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'Position the QR code within the frame',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 20),
                if (_isProcessing)
                  const CircularProgressIndicator(color: _kOrange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

typedef QrScannerPage = AdminQrScannerPage;

