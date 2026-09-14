import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../utils/session_storage.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'cache_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  socket_io.Socket? _socket;
  socket_io.Socket? get socket => _socket;
  bool _connecting = false;

  /// Global notifier that emits the event name whenever any live data update arrives.
  /// Pages can listen to this ValueNotifier or add event-specific callbacks.
  final ValueNotifier<String?> dataUpdateNotifier = ValueNotifier<String?>(null);

  final Map<String, List<void Function(dynamic)>> _customListeners = {};

  static String get _socketUrl {
    try {
      final uri = Uri.parse(ApiService.baseUrl);
      final portStr = uri.hasPort ? ':${uri.port}' : '';
      final host = uri.host.isNotEmpty ? uri.host : 'localhost';
      return '${uri.scheme}://$host$portStr';
    } catch (_) {
      return ApiService.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
    }
  }

  Future<void> initSocket() async {
    // Prevent duplicate connections and concurrent init attempts
    if (_connecting) return;
    if (_socket != null && _socket!.connected) {
      debugPrint('[Socket] Already connected — skipping init');
      return;
    }

    // Dispose any dead socket before creating a new one
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    _connecting = true;

    // Small delay so the app finishes initial rendering
    await Future.delayed(const Duration(seconds: 1));

    final token = await SessionStorage.instance.getString('cubag_token');
    final url = _socketUrl;

    debugPrint('[Socket] Connecting to $url');

    final socketOptions = socket_io.OptionBuilder()
        .setTransports(kIsWeb ? ['polling'] : ['websocket', 'polling'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(999)
        .setReconnectionDelay(1500)
        .setReconnectionDelayMax(5000)
        .setTimeout(10000);

    if (token != null && token.isNotEmpty) {
      socketOptions.setAuth({'token': token});
      socketOptions.setQuery({'token': token});
      if (!kIsWeb) {
        socketOptions.setExtraHeaders({'Authorization': 'Bearer $token'});
      }
    }

    try {
      _socket = socket_io.io(url, socketOptions.build());
      _socket!.connect();

      _socket!.onConnect((_) {
        _connecting = false;
        debugPrint('[Socket] Connected ✓ ($url)');
        _attachGlobalSyncListeners();
      });

      _socket!.onConnectError((err) {
        _connecting = false;
        debugPrint('[Socket] Connect error: $err');
      });

      _socket!.onError((err) {
        _connecting = false;
        debugPrint('[Socket] Error: $err');
      });

      _socket!.onDisconnect((_) {
        _connecting = false;
        debugPrint('[Socket] Disconnected — waiting for auto-reconnect');
      });

      _socket!.on('notification', (data) {
        debugPrint('[Socket] Notification: $data');
      });
    } catch (e) {
      _connecting = false;
      _socket = null;
    }
  }

  void _attachGlobalSyncListeners() {
    if (_socket == null) return;

    final eventsToPurge = <String, List<String>>{
      'announcements_updated': ['announcements'],
      'news_updated': ['news', 'blog'],
      'bulletins_updated': ['bulletin', 'public_bulletins'],
      'courses_updated': ['courses', 'public_courses'],
      'events_updated': ['events', 'public_events'],
      'gallery_updated': ['gallery', 'public_gallery'],
      'schedules_updated': ['schedules', 'vessels'],
      'complaints_updated': ['complaints'],
      'compliance_updated': ['compliance'],
      'documents_updated': ['documents', 'requirements', 'member', 'auth/me', 'tasks'],
      'member_documents_updated': ['documents', 'requirements', 'member', 'auth/me', 'tasks'],
      'document_rules_updated': ['documents', 'requirements'],
      'fees_updated': ['fees', 'settings', 'tasks'],
      'tasks_updated': ['tasks', 'documents', 'auth/me'],
      'member_updated': ['member', 'auth/me', 'tasks', 'documents', 'requirements'],
      'member_approved': ['member', 'auth/me', 'tasks', 'documents', 'requirements'],
      'payment_approved': ['payments', 'member', 'auth/me', 'fees', 'tasks', 'documents'],
    };

    eventsToPurge.forEach((eventName, cachePatterns) {
      _socket!.off(eventName);
      _socket!.on(eventName, (data) {
        debugPrint('[Socket] Realtime sync triggered: $eventName ($data)');
        for (final pattern in cachePatterns) {
          CacheService().invalidatePattern(pattern);
          ApiService.deleteCacheKeysMatching(pattern);
        }
        dataUpdateNotifier.value = '$eventName:${DateTime.now().millisecondsSinceEpoch}';

        // Auto-refresh session info when membership/approval/payment status changes
        if (eventName == 'member_updated' ||
            eventName == 'member_approved' ||
            eventName == 'payment_approved') {
          ApiService().get('/auth/me').then((res) {
            if (res.data != null && res.data is Map) {
              final d = (res.data['member'] ?? res.data) as Map;
              final st = d['status']?.toString();
              if (st != null) SessionStorage.instance.setString('cubag_status', st);
              final exp = d['license_expiry_date']?.toString();
              if (exp != null) SessionStorage.instance.setString('cubag_expiry', exp);
              final lic = d['license_number']?.toString();
              if (lic != null) SessionStorage.instance.setString('cubag_license_number', lic);
              final name = d['name']?.toString();
              if (name != null) SessionStorage.instance.setString('cubag_name', name);
            }
          }).catchError((_) {});
        }

        // Notify custom registered listeners
        if (_customListeners.containsKey(eventName)) {
          for (final listener in List.from(_customListeners[eventName]!)) {
            try {
              listener(data);
            } catch (e) {
              debugPrint('[Socket] Error in listener for $eventName: $e');
            }
          }
        }
      });
    });
  }

  /// Register a custom callback for a specific socket event
  void on(String event, void Function(dynamic) callback) {
    _customListeners.putIfAbsent(event, () => []).add(callback);
    _socket?.on(event, callback);
  }

  /// Unregister a custom callback
  void off(String event, [void Function(dynamic)? callback]) {
    if (callback != null) {
      _customListeners[event]?.remove(callback);
      _socket?.off(event, callback);
    } else {
      _customListeners.remove(event);
      _socket?.off(event);
    }
  }

  /// Reconnect if socket connection was dropped
  Future<void> reconnectIfNeeded() async {
    if (_socket == null || !_socket!.connected) {
      await initSocket();
    }
  }

  /// Update the auth token after login without full reconnect.
  Future<void> refreshToken() async {
    if (_socket == null) return;
    final token = await SessionStorage.instance.getString('cubag_token');
    if (token != null && !kIsWeb) {
      _socket!.io.options?['extraHeaders'] = {'Authorization': 'Bearer $token'};
    }
  }

  void dispose() {
    _connecting = false;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
