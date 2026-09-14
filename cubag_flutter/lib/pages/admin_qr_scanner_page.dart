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

        // Expected format: https://winningedgeinvestment.com/#/verify-member/123
        // Or if the backend URL is scanned: https://winningedgeinvestment.com/api/verify-member/123
        String memberId = '';
        if (code.contains('/verify-member/')) {
          memberId = code.split('/verify-member/').last;
        } else {
          // Fallback if they scan just an ID
          memberId = code;
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
