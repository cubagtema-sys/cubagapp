import 'package:flutter/material.dart';
import 'api_service.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  
  List<Map<String, dynamic>> _recentNotifications = [];
  List<Map<String, dynamic>> get recentNotifications => _recentNotifications;
  
  DateTime? _lastFetched;

  final ApiService _apiService = ApiService();

  void syncFromNotifications(List<dynamic> items) {
    final count = items.where((item) {
      if (item is Map) {
        final isRead = item['is_read'] == true ||
            item['read'] == true ||
            item['read_at'] != null;
        return !isRead;
      }
      return false;
    }).length;

    _unreadCount = count < 0 ? 0 : count;
    _lastFetched = DateTime.now();
    notifyListeners();
  }

  Future<void> fetchUnreadCount({bool force = false}) async {
    if (!force &&
        _lastFetched != null &&
        DateTime.now().difference(_lastFetched!).inSeconds < 10) {
      return;
    }

    try {
      final res = await _apiService.get('/notifications');
      if (res.statusCode == 200 && res.data != null) {
        final rawItems = (res.data is Map && res.data.containsKey('items'))
            ? res.data['items']
            : res.data;
        final data = ApiService.ensureList(rawItems);
        
        final list = data.map((a) {
          final Map<String, dynamic> item = (a is Map)
              ? Map<String, dynamic>.from(a)
              : {};
          return {
            'id': item['id'],
            'type': item['category']?.toString().toLowerCase() ?? 'announcement',
            'title': item['title']?.toString() ?? '',
            'message': item['body']?.toString() ?? item['content']?.toString() ?? '',
            'created_at': item['created_at']?.toString() ?? '',
            'read': item['read_at'] != null || item['is_read'] == true || item['read'] == true,
          };
        }).toList();
        
        _recentNotifications = List<Map<String, dynamic>>.from(list.take(5));
        
        final count = list.where((n) => n['read'] != true).length;
        setUnreadCount(count);
      }
    } catch (e) {
      debugPrint('Error fetching unread count: $e');
    }
  }

  void setUnreadCount(int count) {
    _unreadCount = count < 0 ? 0 : count;
    _lastFetched = DateTime.now();
    notifyListeners();
  }

  void decrementCount() {
    if (_unreadCount > 0) {
      _unreadCount--;
      _lastFetched = DateTime.now();
      notifyListeners();
    }
  }

  void clearCount() {
    _unreadCount = 0;
    _lastFetched = DateTime.now();
    notifyListeners();
  }
}
