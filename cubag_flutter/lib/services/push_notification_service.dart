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
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Tapped on a foreground local notification
          if (response.payload != null) {
            _handleDeepLink({'type': response.payload!});
          }
        },
      );

      // Create the Android notification channel
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      // ── Request FCM permissions ─────────────────────────────────────────────
      final currentSettings = await _messaging.getNotificationSettings();
      if (currentSettings.authorizationStatus ==
          AuthorizationStatus.notDetermined) {
        // Do not request permission yet, let the UI handle the soft prompt!
        debugPrint(
          'FCM permission not determined yet, skipping native prompt.',
        );
      } else {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('FCM permission: ${settings.authorizationStatus}');
      }

      // ── Background handler ──────────────────────────────────────────────────
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // ── Foreground handler — show as local notification ─────────────────────
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final android = message.notification?.android;
        if (notification != null && android != null) {
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

      // ── Register FCM token with backend ────────────────────────────────────
      final token = await _messaging.getToken();
      debugPrint('FCM Token: $token');
      if (token != null) {
        ApiService()
            .putData('auth/fcm-token', {'fcm_token': token})
            .catchError((e) => debugPrint('Failed to save FCM token: $e'));
      }

      // Refresh token when it rotates
      _messaging.onTokenRefresh.listen((newToken) {
        ApiService()
            .putData('auth/fcm-token', {'fcm_token': newToken})
            .catchError((e) => debugPrint('Failed to refresh FCM token: $e'));
      });
    } catch (e) {
      debugPrint('Push notification init failed (non-fatal): $e');
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
}
