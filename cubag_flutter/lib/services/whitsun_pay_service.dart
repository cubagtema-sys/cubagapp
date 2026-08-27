import 'package:dio/dio.dart';
import '../utils/app_logger.dart';

class WhitsunPayService {
  static final WhitsunPayService _instance = WhitsunPayService._internal();
  factory WhitsunPayService() => _instance;
  WhitsunPayService._internal();

  static const String defaultEndpoint =
      'https://developer.whitsun.dev/api/v1/payments';
  static const String clientId = '019e8ba678a27f00bc19c3757989ed0b';
  static const String apiKey =
      'wp_live_h7Q8bld7YqtjvTVF2wwfBrUjxl6LShWexviNLfy5lQU';
  static const String callbackUrl =
      'https://cubag-api-server.onrender.com/api/payments/webhook';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-client-id': clientId,
        'x-api-key': apiKey,
        'x-callback-url': callbackUrl,
        'User-Agent': 'CUBAG-Mobile/2.0 (Ghana Customs Platform)',
      },
    ),
  );

  /// Dispatches the MoMo authorization prompt directly from the mobile device to WhitsunPay.
  /// Because mobile devices run on mobile carrier IPs (MTN/Telecel/Wi-Fi), Cloudflare never blocks them.
  Future<bool> dispatchPrompt({
    required String txRef,
    required String phone,
    required String network,
    required double amount,
    required String description,
    Map<String, dynamic>? serverDispatchData,
  }) async {
    // Format to Ghana international format: 233XXXXXXXXX
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('233') && cleanPhone.length == 12) {
      // already in correct format
    } else if (cleanPhone.startsWith('0') && cleanPhone.length == 10) {
      cleanPhone = '233${cleanPhone.substring(1)}';
    } else if (cleanPhone.length == 9) {
      cleanPhone = '233$cleanPhone';
    }

    String provider = 'mtn';
    final netLower = network.toLowerCase();
    if (netLower.contains('voda') || netLower.contains('telecel')) {
      provider = 'vodafone';
    } else if (netLower.contains('airtel') ||
        netLower.contains('tigo') ||
        netLower.contains('at')) {
      provider = 'airteltigo';
    }

    final payload = (serverDispatchData != null &&
            serverDispatchData['payload'] is Map)
        ? Map<String, dynamic>.from(serverDispatchData['payload'] as Map)
        : {
            'transactionReference': txRef,
            'description': description.length > 40
                ? description.substring(0, 40)
                : description,
            'amount': amount,
            'debitParty': {
              'msisdn': cleanPhone,
              'provider': provider,
            },
          };

    final url = serverDispatchData?['url']?.toString() ?? defaultEndpoint;
    AppLogger.info('WhitsunPay', 'Direct mobile prompt dispatch to $url for $txRef ($cleanPhone)');

    try {
      final res = await _dio.post(url, data: payload);
      AppLogger.info('WhitsunPay', 'Prompt dispatch response: ${res.statusCode} ${res.data}');
      return res.statusCode != null && res.statusCode! < 400;
    } catch (e) {
      AppLogger.error('WhitsunPay', 'Direct dispatch failed: $e');
      return false;
    }
  }

  /// Checks the transaction status directly from the mobile device.
  /// Returns a Map with { 'isPaid': bool, 'status': String, 'txId': String }
  Future<Map<String, dynamic>> checkStatus(String txRef) async {
    if (txRef.isEmpty) return {'isPaid': false, 'status': 'unknown'};
    final url = 'https://developer.whitsun.dev/api/v1/$txRef/status';
    try {
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data is Map) {
        final st = (res.data['status']?.toString() ?? '').toUpperCase();
        final txId = res.data['transactionId']?.toString() ?? '';
        final isPaid = st == 'SUCCESSFUL' ||
            st == 'SUCCESS' ||
            st == 'COMPLETED' ||
            st == 'PAID';
        return {
          'isPaid': isPaid,
          'status': st.toLowerCase(),
          'txId': txId,
          'raw': res.data,
        };
      }
    } catch (e) {
      AppLogger.error('WhitsunPay', 'Direct status check error: $e');
    }
    return {'isPaid': false, 'status': 'pending'};
  }
}
