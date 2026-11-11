import 'dart:async' show unawaited;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import '../core/router.dart';

// ── Local notification channel (Android) ─────────────────────────────────────
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'cubag_high_importance', // id
  'CUBAG Notifications', // name
  description: 'CUBAG platform alerts and announcements',
  importance: Importance.high,
  playSound: true,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Handling a background message: ${message.messageId}');
}

class PushNotificationService {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      // ── Set up local notifications (for foreground display) ────────────────
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // BUG-07: never prompt at cold start. Permission is requested
          // after sign-in via requestPermissionsAndSyncToken().
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Tapped on a foreground local notification
          if (response.payload != null) {
            _handleDeepLink({'type': response.payload!});
          }
        },
      );

      // Create the Android notification channel and request Android 13+ permissions
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_channel);

      // Enable foreground banners and sound on iOS
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // ── Background handler ──────────────────────────────────────────────────
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // ── Foreground handler — show as local notification ─────────────────────
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _channel.id,
                _channel.name,
                channelDescription: _channel.description,
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
                color: Color(0xFFFF5000), // CUBAG orange
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            payload: message.data['type']?.toString(),
          );
        }
      });

      // ── Notification tap: background → foreground ───────────────────────────
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleDeepLink(message.data);
      });

      // ── Notification tap: app was terminated ───────────────────────────────
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _handleDeepLink(initialMessage.data);
        });
      }

      unawaited(syncFcmToken());

      // Refresh token when it rotates or when APNs token arrives
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: $newToken');
        ApiService()
            .putData('auth/fcm-token', {'fcm_token': newToken})
            .catchError((e) => debugPrint('Failed to refresh FCM token: $e'));
      });
    } catch (e) {
      debugPrint('Push notification init failed (non-fatal): $e');
    }
  }

  /// Explicitly prompts the user for push notification permissions on iOS and Android
  /// and synchronizes the FCM token with the backend.
  Future<void> requestPermissionsAndSyncToken() async {
    if (kIsWeb) return;
    // Design-preview debug runs: no system prompt over the screens under review.
    if (kDebugMode && const String.fromEnvironment('DESIGN_LOGIN_EMAIL').isNotEmpty) return;
    try {
      // 1. Request Darwin (iOS) notifications permission
      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 2. Request Android 13+ runtime notification permissions
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.requestNotificationsPermission();

      // 3. Request Firebase Messaging permissions
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint('Explicit FCM permission status: ${settings.authorizationStatus}');

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Sync FCM token with backend
      await syncFcmToken();
    } catch (e) {
      debugPrint('Push notification permission request error: $e');
    }
  }

  /// Registers or refreshes the FCM device token with the CUBAG backend
  Future<void> syncFcmToken() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apns = await _messaging.getAPNSToken();
        int attempts = 0;
        while (apns == null && attempts < 4) {
          debugPrint('Waiting for iOS APNs token from Apple ($attempts)...');
          await Future.delayed(const Duration(seconds: 1));
          apns = await _messaging.getAPNSToken();
          attempts++;
        }
        if (apns == null) {
          debugPrint('APNs token not yet available. Token will sync via onTokenRefresh.');
        }
      }

      final token = await _messaging.getToken();
      debugPrint('FCM Token: $token');
      if (token != null && token.isNotEmpty) {
        await ApiService()
            .putData('auth/fcm-token', {'fcm_token': token})
            .catchError((e) => debugPrint('Failed to save FCM token: $e'));
      }
    } catch (e) {
      debugPrint('FCM token acquisition deferred: $e');
    }
  }

  void _handleDeepLink(Map<String, dynamic> data) async {
    final route = data['route']?.toString().trim();
    final type = data['type']?.toString().trim();

    if (route != null && route.isNotEmpty) {
      if (route.startsWith('http://') || route.startsWith('https://')) {
        final uri = Uri.tryParse(route);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } else if (route.startsWith('/')) {
        try {
          appRouter.go(route);
          return;
        } catch (_) {
          appRouter.go('/notifications');
          return;
        }
      }
    }

    switch (type) {
      case 'announcement':
        appRouter.go('/announcements');
        break;
      case 'task':
        appRouter.go('/tasks');
        break;
      case 'payment':
        appRouter.go('/payments');
        break;
      case 'schedule':
        appRouter.go('/cargo-schedules');
        break;
      case 'ticket':
        appRouter.go('/engagement');
        break;
      case 'message':
        final senderId = data['id']?.toString();
        final name = data['name']?.toString();
        if (senderId != null && senderId.isNotEmpty) {
          appRouter.go(
            '/messaging?id=$senderId${name != null ? '&name=${Uri.encodeComponent(name)}' : ''}',
          );
        } else {
          appRouter.go('/messaging');
        }
        break;
      case 'license':
        appRouter.go('/license-renewal');
        break;
      default:
        appRouter.go('/notifications');
    }
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFFF5000),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
