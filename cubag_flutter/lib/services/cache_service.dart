import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../utils/app_logger.dart';

/// Simple offline cache for announcements, schedules, and public materials.
/// Caches API responses in SharedPreferences with TTL.
/// Falls back to cached data when the network request fails.
class _CacheEntry {
  final dynamic data;
  final int timestamp;
  _CacheEntry(this.data, this.timestamp);
}

class CacheService {
  static const _prefix = 'cache_';
  static const _ttlMinutes = 5; // Reduced default TTL to 5 minutes for freshness

  static final Map<String, _CacheEntry> _memCache = {};
  final ApiService _api = ApiService();

  /// Fetch with Stale-While-Revalidate strategy:
  /// 1. If cached data (memory or disk) exists, returns it immediately (0ms).
  /// 2. Asynchronously fetches fresh data from network, caches it, and calls [onFreshData] if provided.
  /// 3. If no cache exists, fetches from network synchronously.
  Future<List<dynamic>> fetchCached(
    String endpoint, {
    int ttl = _ttlMinutes,
    bool forceRefresh = false,
    void Function(List<dynamic> freshData)? onFreshData,
  }) async {
    final key = '$_prefix${endpoint.replaceAll('/', '_')}';
    final tsKey = '${key}_ts';
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!forceRefresh) {
      // Tier 1: In-memory cache
      if (_memCache.containsKey(key)) {
        final entry = _memCache[key]!;
        final isFresh = (now - entry.timestamp) < ttl * 60 * 1000;
        final list = ApiService.ensureList(entry.data);
        if (isFresh) {
          // Fresh memory hit — return immediately
          return list;
        } else {
          // Stale memory hit — return stale list and revalidate in background
          _revalidateListInBackground(endpoint, key, tsKey, onFreshData);
          return list;
        }
      }

      // Tier 2: Disk cache
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            final list = List<dynamic>.from(decoded);
            final lastFetch = prefs.getInt(tsKey) ?? 0;
            _memCache[key] = _CacheEntry(list, lastFetch);
            final isFresh = (now - lastFetch) < ttl * 60 * 1000;
            if (isFresh) {
              return list;
            } else {
              _revalidateListInBackground(endpoint, key, tsKey, onFreshData);
              return list;
            }
          }
        } catch (e, st) {
          AppLogger.error('cache_service', e, st);
        }
      }
    }

    // No cache or force refresh — fetch synchronously
    try {
      final res = await _api.get(endpoint);
      if (res.statusCode == 200 && res.data != null) {
        final data = ApiService.ensureList(res.data);
        _memCache[key] = _CacheEntry(data, now);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, jsonEncode(data));
        await prefs.setInt(tsKey, now);
        return data;
      }
    } catch (e) {
      debugPrint('[Cache] Network fetch failed for $endpoint: $e');
    }

    // Fallback if available
    if (_memCache.containsKey(key)) {
      return ApiService.ensureList(_memCache[key]!.data);
    }
    return [];
  }

  void _revalidateListInBackground(
    String endpoint,
    String key,
    String tsKey,
    void Function(List<dynamic> freshData)? onFreshData,
  ) {
    Future.microtask(() async {
      try {
        final res = await _api.get(endpoint);
        if (res.statusCode == 200 && res.data != null) {
          final data = ApiService.ensureList(res.data);
          final now = DateTime.now().millisecondsSinceEpoch;
          _memCache[key] = _CacheEntry(data, now);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, jsonEncode(data));
          await prefs.setInt(tsKey, now);
          if (onFreshData != null) {
            onFreshData(data);
          }
        }
      } catch (e) {
        debugPrint('[Cache] Background revalidation failed for $endpoint: $e');
      }
    });
  }

  /// Fetch a map-shaped response with Stale-While-Revalidate cache.
  Future<Map<String, dynamic>> fetchCachedMap(
    String endpoint, {
    int ttl = _ttlMinutes,
    bool forceRefresh = false,
    void Function(Map<String, dynamic> freshData)? onFreshData,
  }) async {
    final key = '$_prefix${endpoint.replaceAll('/', '_')}';
    final tsKey = '${key}_ts';
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!forceRefresh) {
      // Tier 1: Memory hit
      if (_memCache.containsKey(key)) {
        final entry = _memCache[key]!;
        if (entry.data is Map) {
          final map = Map<String, dynamic>.from(entry.data as Map);
          final isFresh = (now - entry.timestamp) < ttl * 60 * 1000;
          if (isFresh) {
            return map;
          } else {
            _revalidateMapInBackground(endpoint, key, tsKey, onFreshData);
            return map;
          }
        }
      }

      // Tier 2: Disk cache
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = Map<String, dynamic>.from(decoded);
            final lastFetch = prefs.getInt(tsKey) ?? 0;
            _memCache[key] = _CacheEntry(map, lastFetch);
            final isFresh = (now - lastFetch) < ttl * 60 * 1000;
            if (isFresh) {
              return map;
            } else {
              _revalidateMapInBackground(endpoint, key, tsKey, onFreshData);
              return map;
            }
          }
        } catch (e, st) {
          AppLogger.error('cache_service', e, st);
        }
      }
    }

    try {
      final res = await _api.get(endpoint);
      if (res.statusCode == 200 && res.data != null) {
        final Map<String, dynamic> data = (res.data is Map)
            ? Map<String, dynamic>.from(res.data as Map)
            : {'items': ApiService.ensureList(res.data)};
        _memCache[key] = _CacheEntry(data, now);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, jsonEncode(data));
        await prefs.setInt(tsKey, now);
        return data;
      }
    } catch (e, st) {
      AppLogger.error('cache_service', e, st);
    }

    if (_memCache.containsKey(key) && _memCache[key]!.data is Map) {
      return Map<String, dynamic>.from(_memCache[key]!.data as Map);
    }

    return {};
  }

  void _revalidateMapInBackground(
    String endpoint,
    String key,
    String tsKey,
    void Function(Map<String, dynamic> freshData)? onFreshData,
  ) {
    Future.microtask(() async {
      try {
        final res = await _api.get(endpoint);
        if (res.statusCode == 200 && res.data != null) {
          final Map<String, dynamic> data = (res.data is Map)
              ? Map<String, dynamic>.from(res.data as Map)
              : {'items': ApiService.ensureList(res.data)};
          final now = DateTime.now().millisecondsSinceEpoch;
          _memCache[key] = _CacheEntry(data, now);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, jsonEncode(data));
          await prefs.setInt(tsKey, now);
          if (onFreshData != null) {
            onFreshData(data);
          }
        }
      } catch (e) {
        debugPrint('[Cache] Background map revalidation failed for $endpoint: $e');
      }
    });
  }

  /// Clear all cached data (Tier 1 memory + Tier 2 disk).
  Future<void> clearAll() async {
    _memCache.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
    debugPrint('[Cache] All memory & disk caches cleared');
  }

  /// Clear a specific endpoint cache.
  Future<void> invalidate(String endpoint) async {
    final key = '$_prefix${endpoint.replaceAll('/', '_')}';
    _memCache.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await prefs.remove('${key}_ts');
  }

  /// Clear any cache keys matching a pattern (e.g. 'announcements', 'courses', 'schedules', 'news').
  Future<void> invalidatePattern(String pattern) async {
    final cleanPattern = pattern.replaceAll('/', '_');
    _memCache.removeWhere((k, _) => k.contains(cleanPattern));
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix) && k.contains(cleanPattern)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    debugPrint('[Cache] Invalidated keys matching: $pattern ($keys)');
  }
}
