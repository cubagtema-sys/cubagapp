import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../components/app_logo.dart';

const _kOrange = Color(0xFFFF5000);
const _kOrangeDark = Color(0xFFe06920);

class VerifyEmailPage extends StatefulWidget {
  final String? token;
  const VerifyEmailPage({super.key, this.token});
  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  String _status = 'verifying'; // verifying, success, error
  String _message = 'Verifying your email address...';

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    if (widget.token == null) {
      setState(() {
        _status = 'error';
        _message = 'Invalid or missing verification token.';
      });
      return;
    }
    try {
      final res = await ApiService().post(
        '/auth/verify-email',
        data: {'token': widget.token},
      );
      if (res.statusCode == 200) {
        setState(() {
          _status = 'success';
          _message =
              'Your email has been verified! You can now log in to the portal.';
        });
      } else {
        setState(() {
          _status = 'error';
          _message =
              res.data['message'] ??
              'Verification failed. The link may have expired.';
        });
      }
    } catch (_) {
      setState(() {
        _status = 'error';
        _message = 'Network error while verifying email.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(body: isWide ? _buildWideLayout() : _buildMobileLayout());
  }

  Widget _buildWideLayout() => Row(
    children: [
      Expanded(flex: 4, child: _buildSidebar()),
      Expanded(flex: 6, child: _buildFormPanel()),
    ],
  );

  Widget _buildMobileLayout() => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _buildFormContent(isMobile: true),
          ),
        ),
      ),
    ),
  );

  Widget _buildSidebar() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_kOrange, _kOrangeDark],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -80,
          right: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -60,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(12),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'CUBAG',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enterprise Mobility Platform',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 48),
              _sidebarFeature(
                Icons.email_outlined,
                'Secure Email Verification',
              ),
              const SizedBox(height: 20),
              _sidebarFeature(
                Icons.verified_outlined,
                'Official Account Activation',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sidebarFeature(IconData icon, String label) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      const SizedBox(width: 14),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ],
  );

  Widget _buildFormPanel() => Container(
    color: Colors.white,
    child: Center(
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(48),
          constraints: const BoxConstraints(maxWidth: 480),
          child: _buildFormContent(isMobile: false),
        ),
      ),
    ),
  );

  Widget _buildFormContent({bool isMobile = false}) {
    return Column(
      crossAxisAlignment: isMobile
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: isMobile ? Alignment.centerLeft : Alignment.center,
          child: const AppLogo(size: 60, borderRadius: 12, showShadow: true),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: isMobile ? Alignment.centerLeft : Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_status == 'verifying')
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: _kOrange,
                    strokeWidth: 3,
                  ),
                ),
              if (_status == 'success')
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Color(0x1910b981),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF10b981),
                    size: 32,
                  ),
                ),
              if (_status == 'error')
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Color(0x19ef4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error,
                    color: Color(0xFFef4444),
                    size: 32,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Email Verification',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A0F0A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _message,
          textAlign: isMobile ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        if (_status != 'verifying') ...[
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Go to Login',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
