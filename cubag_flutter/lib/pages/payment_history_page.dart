import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../components/app_layout.dart';
import '../components/app_logo.dart';
import '../components/in_app_document_viewer.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/app_logger.dart';

// Balanced CUBAG Brand Palette
const _kBrown = Color(0xFF6B3E26); // Primary Brown
const _kOrange = Color(0xFFFF5000); // Primary Orange CTA
const _kDarkBrown = Color(0xFF3E2418); // Deep Dark Contrast
const _kCream = Color(0xFFF8F4F0); // Light Background Cream
const _kWhite = Color(0xFFFFFFFF); // White Surfaces
const _kText = Color(0xFF2B211D); // Deep Body Text
const _kMuted = Color(0xFF6F625B); // Secondary Muted Text
const _kBorder = Color(0xFFE8DED6); // Soft Warm Border

class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});
  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  bool _loading = true;
  List<dynamic> _payments = [];
  String _filter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  int _page = 1;
  static const int _pageSize = 8;
  dynamic _verifyingId;

  final Map<String, Map<String, dynamic>> _statusConfigs = {
    'paid': {
      'label': 'PAID & VERIFIED',
      'color': Color(0xFF059669),
      'bg': Color(0xFFECFDF5),
      'border': Color(0xFFA7F3D0),
      'icon': Icons.check_circle_rounded,
    },
    'pending': {
      'label': 'PENDING APPROVAL',
      'color': Color(0xFFD97706),
      'bg': Color(0xFFFFFBEB),
      'border': Color(0xFFFDE68A),
      'icon': Icons.hourglass_top_rounded,
    },
    'failed': {
      'label': 'FAILED',
      'color': Color(0xFFDC2626),
      'bg': Color(0xFFFEF2F2),
      'border': Color(0xFFFECACA),
      'icon': Icons.cancel_rounded,
    },
    'overdue': {
      'label': 'OVERDUE',
      'color': Color(0xFFDC2626),
      'bg': Color(0xFFFEF2F2),
      'border': Color(0xFFFECACA),
      'icon': Icons.warning_amber_rounded,
    },
  };

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = v;
          _page = 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!_loading) setState(() => _loading = true);
    await ApiService().fetchDataWithCache('/payments', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        setState(() {
          _payments = ApiService.ensureList(data);
          _loading = false;
        });
      }
    });
  }

  String _fmt(double n) => n.toStringAsFixed(2);

  Future<Uint8List> _generateQrCodeImage(String data) async {
    try {
      final qrPainter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );
      final image = await qrPainter.toImage(200);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } catch (e) {
      AppLogger.error('payment_history_page', e, null);
      rethrow;
    }
  }

  Future<void> _generateAndDownloadPdfReceipt(
    Map<String, dynamic> payment,
    String ref,
    double amount,
    String dateStr,
    String desc,
    String configLabel,
    String? paymentMethod,
    String? payerPhone,
    String? momoTxId,
    String? adminNote,
    String verifyUrl,
    String userName,
    String userCompany,
    String licenseNumber,
  ) async {
    // Generate QR code image first
    final qrImageBytes = await _generateQrCodeImage(verifyUrl);

    // Embed Inter as the PDF font. The pdf package's default base-14 Helvetica
    // has no glyph for the cedi sign (₵, U+20B5), so "GH₵" rendered as a tofu box.
    final interRegular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-400.ttf'));
    final interBold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-700.ttf'));

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: interRegular, bold: interBold),
    );

    final memberName = payment['member_name']?.toString() ?? userName;
    final finalMemberName = memberName.isNotEmpty ? memberName : 'Registered Broker';

    final memberCompany = payment['member_company']?.toString() ?? userCompany;
    final license = payment['license_number']?.toString() ?? licenseNumber;

    // Generate PDF receipt
    pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'CUBAG',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF6B3E26),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Customs Brokers Association of Ghana',
                          style: pw.TextStyle(
                            fontSize: 12,
                            color: PdfColor.fromInt(0xFF6F625B),
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFECFDF5),
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(
                          color: PdfColor.fromInt(0xFFA7F3D0),
                          width: 1,
                        ),
                      ),
                      child: pw.Text(
                        'OFFICIAL RECEIPT',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF059669),
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),

                // Receipt Title
                pw.Center(
                  child: pw.Text(
                    'PAYMENT RECEIPT',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF6B3E26),
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),

                // Amount Display (cedi sign renders via the embedded Inter font)
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(20),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF8F4F0),
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(
                      color: PdfColor.fromInt(0xFFE8DED6),
                      width: 1,
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'TOTAL AMOUNT PAID',
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: PdfColor.fromInt(0xFF6F625B),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'GH₵ ${_fmt(amount)}',
                        style: pw.TextStyle(
                          fontSize: 32,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF6B3E26),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),

                // Receipt Details Table
                _buildPdfTableRow('Transaction Reference', ref),
                _buildPdfTableRow('Date & Time', dateStr),
                _buildPdfTableRow('Status', configLabel),
                _buildPdfTableRow('Payment Purpose', desc),
                _buildPdfTableRow('Payment Method', paymentMethod?.toUpperCase() ?? 'N/A'),
                _buildPdfTableRow('Payment Gateway', 'WhitsunPay / CUBAG Secure Portal'),
                pw.SizedBox(height: 8),
                _buildPdfTableRow('Member Name', finalMemberName),
                if (memberCompany.isNotEmpty) _buildPdfTableRow('Agency / Company', memberCompany),
                if (license.isNotEmpty) _buildPdfTableRow('Member ID / License', license),
                if (payerPhone != null && payerPhone.isNotEmpty) _buildPdfTableRow('Payer Phone / Acct', payerPhone),
                if (momoTxId != null && momoTxId.isNotEmpty) _buildPdfTableRow('MoMo / Txn ID', momoTxId),
                if (adminNote != null && adminNote.isNotEmpty) _buildPdfTableRow('Admin Notes', adminNote),

                pw.SizedBox(height: 24),

                // Verification Section with QR Code
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF8F4F0),
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(
                      color: PdfColor.fromInt(0xFFE8DED6),
                      width: 1,
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'Digital Verification',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF2B211D),
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      pw.Container(
                        width: 100,
                        height: 100,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Image(
                          pw.MemoryImage(qrImageBytes),
                          width: 100,
                          height: 100,
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      pw.Text(
                        'Scan to verify authenticity',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColor.fromInt(0xFF6F625B),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        verifyUrl,
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromInt(0xFF6B3E26),
                          decoration: pw.TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 32),

                // Footer
                pw.Divider(color: PdfColor.fromInt(0xFFE8DED6)),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    'This is an official CUBAG Treasury Services receipt.',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColor.fromInt(0xFF6F625B),
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'Generated: ${DateTime.now().toLocal().toString()}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColor.fromInt(0xFF6F625B),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

    // Save and share the PDF
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'CUBAG_Receipt_$ref.pdf',
    );
  }

  pw.Widget _buildPdfTableRow(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColor.fromInt(0xFFF1F5F9),
            width: 1,
          ),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColor.fromInt(0xFF6F625B),
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColor.fromInt(0xFF2B211D),
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic rawDate) {
    if (rawDate == null) return '—';
    final dt = DateTime.tryParse(rawDate.toString())?.toLocal();
    if (dt == null) return rawDate.toString();

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year} • $hour:$min $period';
  }

  void _showReceiptDialog(BuildContext context, Map<String, dynamic> payment) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final status = (payment['status']?.toString().toLowerCase()) ?? 'pending';
    final config = _statusConfigs[status] ?? _statusConfigs['pending']!;
    final amount = double.tryParse(payment['amount']?.toString() ?? '0') ?? 0.0;
    final ref =
        payment['payment_ref']?.toString() ?? 'TXN-${payment['id'] ?? '0000'}';
    final dateStr = _formatDateTime(payment['created_at']);
    final desc =
        payment['description']?.toString() ?? 'General Membership Dues';
    final verifyUrl = 'https://cubag.org/api/payments/public/verify-receipt?ref=$ref&amount=${_fmt(amount)}';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF281710) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF1A0F0A) : _kCream;
    final borderCol = isDark ? const Color(0xFF4D2D20) : _kBorder;
    final titleCol = isDark ? Colors.white : _kBrown;
    final mutedCol = isDark ? Colors.white70 : _kMuted;

    final receiptUrl = payment['receipt_url']?.toString();
    final momoTxId = payment['momo_tx_id']?.toString();
    final paymentMethod = payment['payment_method']?.toString() ??
        payment['channel']?.toString() ??
        payment['network']?.toString();
    final payerPhone = payment['phone']?.toString() ?? payment['payer_phone']?.toString();
    final adminNote = payment['admin_note']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: dialogBg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header with Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const AppLogo(size: 42, borderRadius: 10),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CUBAG',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: titleCol,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Customs Brokers Association of Ghana',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: mutedCol,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: mutedCol,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(color: borderCol, thickness: 1),
                const SizedBox(height: 16),

                // Receipt Title & Badge
                Text(
                  'OFFICIAL PAYMENT RECEIPT',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: titleCol,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: config['bg'] as Color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: config['border'] as Color),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        config['icon'] as IconData,
                        size: 14,
                        color: config['color'] as Color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        config['label'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: config['color'] as Color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Amount Display Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: surfaceBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'TOTAL AMOUNT PAID',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: mutedCol,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'GH₵ ${_fmt(amount)}',
                          style: GoogleFonts.outfit(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: isDark ? _kOrange : _kBrown,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Receipt Metadata Table
                _receiptRow(
                  'Transaction Ref',
                  ref,
                  isMono: true,
                  canCopy: true,
                  context: context,
                  isDark: isDark,
                ),
                if (momoTxId != null && momoTxId.isNotEmpty)
                  _receiptRow(
                    'MoMo / Txn ID',
                    momoTxId,
                    isMono: true,
                    canCopy: true,
                    context: context,
                    isDark: isDark,
                  ),
                _receiptRow('Date & Time', dateStr, isDark: isDark),
                _receiptRow('Payment Purpose', desc, isDark: isDark),
                _receiptRow(
                  'Member Name',
                  payment['member_name']?.toString() ?? auth.userName ?? 'Registered Broker',
                  isDark: isDark,
                ),
                if ((payment['member_company']?.toString() ?? auth.userCompany)?.isNotEmpty ?? false)
                  _receiptRow(
                    'Agency / Company',
                    payment['member_company']?.toString() ?? auth.userCompany!,
                    isDark: isDark,
                  ),
                if ((payment['license_number']?.toString() ?? auth.licenseNumber)?.isNotEmpty ?? false)
                  _receiptRow(
                    'Member ID / License',
                    payment['license_number']?.toString() ?? auth.licenseNumber!,
                    isDark: isDark,
                  ),
                if (paymentMethod != null && paymentMethod.isNotEmpty)
                  _receiptRow(
                    'Payment Method',
                    paymentMethod.toUpperCase(),
                    isDark: isDark,
                  ),
                if (payerPhone != null && payerPhone.isNotEmpty)
                  _receiptRow(
                    'Payer Phone / Acct',
                    payerPhone,
                    isDark: isDark,
                  ),
                _receiptRow(
                  'Payment Gateway',
                  'WhitsunPay / CUBAG Secure Portal',
                  isDark: isDark,
                ),
                if (adminNote != null && adminNote.isNotEmpty)
                  _receiptRow(
                    'Admin Notes',
                    adminNote,
                    isDark: isDark,
                  ),

                if (receiptUrl != null && receiptUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        InAppDocumentViewer.show(
                          context,
                          url: receiptUrl,
                          title: 'Payment Proof / Bank Slip',
                          subtitle: 'Ref: $ref',
                        );
                      },
                      icon: const Icon(Icons.attachment_rounded, size: 16),
                      label: const Text('View Attached Receipt Proof'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? _kOrange : _kBrown,
                        side: BorderSide(
                          color: isDark ? _kOrange : _kBrown,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Divider(color: borderCol, thickness: 1),
                const SizedBox(height: 16),

                // QR Code Verification
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderCol),
                      ),
                      child: QrImageView(
                        data: verifyUrl,
                        version: QrVersions.auto,
                        size: 80.0,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Digital Verification Token',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : _kText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Scan QR code to verify validity with CUBAG Treasury Services.',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: isDark ? Colors.white60 : _kMuted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Actions
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(
                                  text:
                                      'CUBAG Receipt Ref: $ref | Amount: GH₵ ${_fmt(amount)} | Date: $dateStr',
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Receipt details copied to clipboard',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: const Text('Copy Details'),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? _kOrange : _kBrown,
                              side: BorderSide(
                                color: isDark ? _kOrange : _kBrown,
                                width: 1.5,
                              ),
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await _generateAndDownloadPdfReceipt(
                                payment,
                                ref,
                                amount,
                                dateStr,
                                desc,
                                config['label'] as String,
                                paymentMethod,
                                payerPhone,
                                momoTxId,
                                adminNote,
                                verifyUrl,
                                auth.userName ?? '',
                                auth.userCompany ?? '',
                                auth.licenseNumber ?? '',
                              );
                            },
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: const Text('Download PDF'),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? _kOrange : _kBrown,
                              side: BorderSide(
                                color: isDark ? _kOrange : _kBrown,
                                width: 1.5,
                              ),
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(
    String label,
    String value, {
    bool isMono = false,
    bool canCopy = false,
    BuildContext? context,
    bool isDark = false,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF382218) : const Color(0xFFF1F5F9),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white70 : _kMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : _kText,
                      fontFeatures: isMono
                          ? [const FontFeature.tabularFigures()]
                          : null,
                    ),
                  ),
                ),
                if (canCopy && context != null)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $value'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, top: 1),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: isDark ? _kOrange : _kBrown,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;
    final isTablet = size.width > 600 && size.width <= 900;

    // Filter and search
    var list = _payments;
    if (_filter != 'all') {
      list = list
          .where((p) => p['status']?.toString().toLowerCase() == _filter)
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((p) {
        final desc = p['description']?.toString().toLowerCase() ?? '';
        final ref = p['payment_ref']?.toString().toLowerCase() ?? '';
        final id = p['id']?.toString() ?? '';
        final date = p['created_at']?.toString().toLowerCase() ?? '';
        return desc.contains(q) ||
            ref.contains(q) ||
            id.contains(q) ||
            date.contains(q);
      }).toList();
    }

    final totalPages = (list.length / _pageSize).ceil().clamp(1, 999);
    final paginated = list
        .skip((_page - 1) * _pageSize)
        .take(_pageSize)
        .toList();

    // Summary calculations
    final paidTotal = _payments
        .where((p) => p['status']?.toString().toLowerCase() == 'paid')
        .fold(
          0.0,
          (s, p) => s + (double.tryParse(p['amount'].toString()) ?? 0),
        );
    final pendingTotal = _payments
        .where((p) => p['status']?.toString().toLowerCase() == 'pending')
        .fold(
          0.0,
          (s, p) => s + (double.tryParse(p['amount'].toString()) ?? 0),
        );
    final failedTotal = _payments
        .where(
          (p) => [
            'failed',
            'overdue',
          ].contains(p['status']?.toString().toLowerCase()),
        )
        .fold(
          0.0,
          (s, p) => s + (double.tryParse(p['amount'].toString()) ?? 0),
        );
    final totalCount = _payments.length;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF1A0F0A) : _kCream;
    final borderCol = isDark ? const Color(0xFF4D2D20) : _kBorder;
    final textCol = isDark ? Colors.white : _kText;
    final mutedCol = isDark ? Colors.white70 : _kMuted;
    final titleCol = isDark ? _kOrange : _kBrown;

    return AppLayout(
      title: 'Payment History & Ledger',
      hideSearch: false,
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Financial Ledger Banner ──────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kBrown, _kDarkBrown],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _kDarkBrown.withAlpha(50),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _kOrange.withAlpha(30),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _kOrange.withAlpha(60),
                                  ),
                                ),
                                child: Text(
                                  'OFFICIAL FINANCIAL STATEMENT',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Member Dues & Payment Ledger',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: isDesktop ? 28 : 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Track your verified association dues, practice license renewals, and official receipts.',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withAlpha(200),
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _fetch,
                          tooltip: 'Refresh Statement',
                          icon: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh_rounded,
                                  color: Colors.white,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => context.go('/payments'),
                          icon: const Icon(Icons.payment_rounded, size: 16),
                          label: const Text('Make a Payment / Settle Dues'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/membership-services'),
                          icon: const Icon(Icons.badge_outlined, size: 16),
                          label: const Text('View Digital License Card'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withAlpha(150),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── 2. KPI Summary Grid ─────────────────────────────────────────
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isDesktop ? 4 : (isTablet ? 2 : 2),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: isDesktop ? 1.9 : (isTablet ? 1.6 : 1.35),
                children: [
                  _kpiCard(
                    icon: Icons.verified_rounded,
                    color: const Color(0xFF059669),
                    bg: isDark
                        ? const Color(0xFF059669).withAlpha(35)
                        : const Color(0xFFECFDF5),
                    label: 'PAID',
                    value: 'GH₵ ${_fmt(paidTotal)}',
                    isDark: isDark,
                  ),
                  _kpiCard(
                    icon: Icons.hourglass_top_rounded,
                    color: _kOrange,
                    bg: _kOrange.withAlpha(isDark ? 35 : 20),
                    label: 'PENDING',
                    value: 'GH₵ ${_fmt(pendingTotal)}',
                    isDark: isDark,
                  ),
                  _kpiCard(
                    icon: Icons.cancel_rounded,
                    color: const Color(0xFFDC2626),
                    bg: isDark
                        ? const Color(0xFFDC2626).withAlpha(35)
                        : const Color(0xFFFEF2F2),
                    label: 'FAILED',
                    value: 'GH₵ ${_fmt(failedTotal)}',
                    isDark: isDark,
                  ),
                  _kpiCard(
                    icon: Icons.receipt_long_rounded,
                    color: isDark ? _kOrange : _kBrown,
                    bg: isDark ? _kOrange.withAlpha(35) : _kCream,
                    label: 'TRANSACTION',
                    value: '$totalCount Txns',
                    isDark: isDark,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── 3. Search and Category Filter Toolbar ──────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderCol),
                ),
                child: isDesktop
                    ? Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _searchCtrl,
                              onChanged: _onSearchChanged,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: textCol,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Search by reference, fee description, or date...',
                                hintStyle: TextStyle(
                                  color: mutedCol.withAlpha(160),
                                  fontSize: 15,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: titleCol,
                                  size: 20,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.clear_rounded,
                                          size: 18,
                                          color: mutedCol,
                                        ),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() {
                                            _searchQuery = '';
                                            _page = 1;
                                          });
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: surfaceBg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderCol),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderCol),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _kOrange,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: _buildDropdownFilter(isDark),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          TextFormField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: textCol,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search transactions...',
                              hintStyle: TextStyle(
                                color: mutedCol.withAlpha(160),
                                fontSize: 13,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: titleCol,
                                size: 20,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear_rounded,
                                        size: 18,
                                        color: mutedCol,
                                      ),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _page = 1;
                                        });
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: surfaceBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderCol),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderCol),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: _kOrange,
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDropdownFilter(isDark),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // ── 4. Transaction Ledger List ──────────────────────────────────
              if (_loading && paginated.isEmpty)
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => const ShimmerListTile(),
                )
              else if (paginated.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 60,
                    horizontal: 24,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: surfaceBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          size: 36,
                          color: titleCol,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No transactions match "$_searchQuery"'
                            : (_filter == 'all'
                                  ? 'Your payment ledger is currently empty.'
                                  : 'No $_filter transactions found.'),
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textCol,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'When you settle association dues or service invoices, receipts will appear here automatically.',
                        style: GoogleFonts.inter(fontSize: 15, color: mutedCol),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () => context.go('/payments'),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Make a Payment'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: paginated.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final pay = paginated[i] as Map<String, dynamic>;
                    final status =
                        (pay['status']?.toString().toLowerCase()) ?? 'pending';
                    final config =
                        _statusConfigs[status] ?? _statusConfigs['pending']!;
                    final amount =
                        double.tryParse(pay['amount']?.toString() ?? '0') ??
                        0.0;
                    final ref =
                        pay['payment_ref']?.toString() ??
                        'TXN-${pay['id'] ?? '0000'}';
                    final dateStr = _formatDateTime(pay['created_at']);
                    final desc =
                        pay['description']?.toString() ??
                        'General Association Dues';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderCol),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Icon + Details + Amount
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: config['bg'] as Color,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: config['border'] as Color,
                                  ),
                                ),
                                child: Icon(
                                  config['icon'] as IconData,
                                  color: config['color'] as Color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            desc,
                                            style: GoogleFonts.outfit(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: textCol,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'GH₵ ${_fmt(amount)}',
                                          style: GoogleFonts.outfit(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: titleCol,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: config['bg'] as Color,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: config['border'] as Color,
                                            ),
                                          ),
                                          child: Text(
                                            config['label'] as String,
                                            style: GoogleFonts.outfit(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: config['color'] as Color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Ref: $ref',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: mutedCol,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          Divider(color: borderCol.withAlpha(120), height: 1),
                          const SizedBox(height: 10),

                          // Footer: Date on left, and actions on right or wrapped below
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: mutedCol,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dateStr,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: mutedCol,
                                    ),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (status == 'pending')
                                    InkWell(
                                      onTap: _verifyingId == pay['id']
                                          ? null
                                          : () async {
                                              setState(
                                                () => _verifyingId = pay['id'],
                                              );
                                              try {
                                                final res = await ApiService().get(
                                                  '/payments/verify/${pay['payment_ref']}',
                                                );
                                                if (res.data['status'] ==
                                                    'success') {
                                                  _fetch();
                                                }
                                              } catch (e, st) {
                                                AppLogger.error(
                                                  'payment_history_page',
                                                  e,
                                                  st,
                                                );
                                              }
                                              setState(
                                                () => _verifyingId = null,
                                              );
                                            },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _kOrange.withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: _kOrange.withAlpha(60),
                                          ),
                                        ),
                                        child: _verifyingId == pay['id']
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: _kOrange,
                                                    ),
                                              )
                                            : Text(
                                                'Verify Status',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kOrange,
                                                ),
                                              ),
                                      ),
                                    ),
                                  InkWell(
                                    onTap: () =>
                                        _showReceiptDialog(context, pay),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: surfaceBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: borderCol),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.receipt_rounded,
                                            size: 13,
                                            color: titleCol,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'View Receipt',
                                            style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: titleCol,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      final status = (pay['status']?.toString().toLowerCase()) ?? 'pending';
                                      final config = _statusConfigs[status] ?? _statusConfigs['pending']!;
                                      final amount = double.tryParse(pay['amount']?.toString() ?? '0') ?? 0.0;
                                      final ref = pay['payment_ref']?.toString() ?? 'TXN-${pay['id'] ?? '0000'}';
                                      final dateStr = _formatDateTime(pay['created_at']);
                                      final desc = pay['description']?.toString() ?? 'General Association Dues';
                                      final momoTxId = pay['momo_tx_id']?.toString();
                                      final paymentMethod = pay['payment_method']?.toString() ?? pay['channel']?.toString() ?? pay['network']?.toString();
                                      final payerPhone = pay['phone']?.toString() ?? pay['payer_phone']?.toString();
                                      final adminNote = pay['admin_note']?.toString();
                                      final verifyUrl = 'https://cubag.org/api/payments/public/verify-receipt?ref=$ref&amount=${_fmt(amount)}';
                                      final auth = Provider.of<AuthService>(context, listen: false);

                                      await _generateAndDownloadPdfReceipt(
                                        pay,
                                        ref,
                                        amount,
                                        dateStr,
                                        desc,
                                        config['label'] as String,
                                        paymentMethod,
                                        payerPhone,
                                        momoTxId,
                                        adminNote,
                                        verifyUrl,
                                        auth.userName ?? '',
                                        auth.userCompany ?? '',
                                        auth.licenseNumber ?? '',
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: surfaceBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: borderCol),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.download_rounded,
                                            size: 13,
                                            color: titleCol,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Download PDF',
                                            style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: titleCol,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // ── 5. Pagination Controls ─────────────────────────────────────
              if (totalPages > 1) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left_rounded, color: titleCol),
                      onPressed: _page > 1
                          ? () => setState(() => _page--)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    ...List.generate(totalPages, (i) => i + 1).map((n) {
                      final isCurrent = _page == n;
                      return GestureDetector(
                        onTap: () => setState(() => _page = n),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCurrent ? _kOrange : cardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent ? _kOrange : borderCol,
                            ),
                          ),
                          child: Text(
                            '$n',
                            style: GoogleFonts.outfit(
                              color: isCurrent ? Colors.white : textCol,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.chevron_right_rounded, color: titleCol),
                      onPressed: _page < totalPages
                          ? () => setState(() => _page++)
                          : null,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required Color color,
    required Color bg,
    required String label,
    required String value,
    bool isDark = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF281710) : _kWhite,
        border: Border.all(color: isDark ? const Color(0xFF4D2D20) : _kBorder),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withAlpha(40), width: 1),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : _kText,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter(bool isDark) {
    final totalCount = _payments.length;
    final settledCount = _payments
        .where((p) => p['status']?.toString().toLowerCase() == 'paid')
        .length;
    final pendingCount = _payments
        .where((p) => p['status']?.toString().toLowerCase() == 'pending')
        .length;
    final failedCount = _payments
        .where(
          (p) => [
            'failed',
            'overdue',
          ].contains(p['status']?.toString().toLowerCase()),
        )
        .length;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0F0A) : _kCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF4D2D20) : _kBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filter,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isDark ? _kOrange : _kBrown,
            size: 22,
          ),
          dropdownColor: isDark ? const Color(0xFF281710) : _kWhite,
          borderRadius: BorderRadius.circular(14),
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : _kText,
          ),
          onChanged: (String? val) {
            if (val != null) {
              setState(() {
                _filter = val;
                _page = 1;
              });
            }
          },
          items: [
            DropdownMenuItem(
              value: 'all',
              child: Row(
                children: [
                  Icon(
                    Icons.list_alt_rounded,
                    size: 16,
                    color: isDark ? _kOrange : _kBrown,
                  ),
                  const SizedBox(width: 8),
                  Text('All Transactions ($totalCount)'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'paid',
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: Color(0xFF059669),
                  ),
                  const SizedBox(width: 8),
                  Text('Settled ($settledCount)'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'pending',
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_top_rounded,
                    size: 16,
                    color: _kOrange,
                  ),
                  const SizedBox(width: 8),
                  Text('Pending ($pendingCount)'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'failed',
              child: Row(
                children: [
                  const Icon(
                    Icons.cancel_rounded,
                    size: 16,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 8),
                  Text('Failed ($failedCount)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
