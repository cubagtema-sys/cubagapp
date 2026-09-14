import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async' show unawaited;
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';
import 'utils/session_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/socket_service.dart';

void main() async {
  // 1. Basic binding initialization
  WidgetsFlutterBinding.ensureInitialized();

  // Intercept uncaught async errors so browser console does not log Uncaught Error
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Intercepted uncaught async error: $error');
    return true;
  };

  // Allow GoogleFonts runtime fetching so font variants (Outfit, Inter) download dynamically when needed.
  GoogleFonts.config.allowRuntimeFetching = true;
  _preloadFonts();

  // 2. Silence logs in Production to boost speed
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // 3. Pre-warm local storage, theme service, and Hive cache concurrently before checking auth state
  await Future.wait([
    SessionStorage.instance.init().then((_) => ThemeService.instance.init()),
    if (!kIsWeb) _initHiveCache(),
  ]);

  // Auth check strictly runs AFTER SessionStorage.instance.init() completes
  await AuthService().checkAuthStatus();

  // 4. Start background non-critical services (Non-blocking)
  unawaited(_initAppServices());

  // 5. Launch App immediately with pre-warmed auth state and theme
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AuthService()),
        ChangeNotifierProvider.value(value: ThemeService.instance),
        ChangeNotifierProvider(create: (_) => NotificationService()),
      ],
      child: const CubagApp(),
    ),
  );
}

/// Initializes heavy services in the background to speed up startup.
Future<void> _initAppServices() async {
  if (kIsWeb) {
    _protectWebCollections();
  }

  // Socket, Firebase and Backend Heartbeat in parallel (Auth is already initialized)
  await Future.wait([
    SocketService().initSocket(),
    _initFirebase(),
    _backendHeartbeat(), // "Wake up" Render backend
  ]);

  // ── Silently pre-load deferred JS chunks in the background ──────────────
  _preloadDeferredLibraries();
}

/// Background pre-loader — fire and forget, never blocks the UI.
Future<void> _preloadDeferredLibraries() async {
  try {
    final role = await SessionStorage.instance.getString('cubag_role');
    if (role == null) return; // Not logged in — skip pre-loading

    // Always pre-load member pages (all roles see these)
    unawaited(preloadMemberLibraries());

    // Pre-load admin pages only for admin users
    if (role == 'admin' || role == 'sub_admin' || role == 'super_admin') {
      unawaited(preloadAdminLibraries());
    }
  } catch (_) {
    // Pre-loading is best-effort — silently ignore any errors
  }
}

Future<void> _initFirebase() async {
  if (kIsWeb) return;
  try {
    await Firebase.initializeApp();
    await PushNotificationService().initialize();
  } catch (e) {
    // Silent fail in production
  }
}

/// Pings the backend immediately on startup to wake it up from "Sleep" (Render.com free tier)
Future<void> _backendHeartbeat() async {
  try {
    // A simple GET to the health endpoint or base URL
    await ApiService().getPublic('health').timeout(const Duration(seconds: 5));
  } catch (_) {
    // We don't care if it fails, the goal is just to trigger the "Wake up"
  }
}

class CubagApp extends StatefulWidget {
  const CubagApp({super.key});

  @override
  State<CubagApp> createState() => _CubagAppState();
}

class _CubagAppState extends State<CubagApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Lifecycle] App resumed — re-validating real-time connection and fresh data');
      SocketService().reconnectIfNeeded();
      if (AuthService().isAuthenticated) {
        AuthService().refreshProfile();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return MaterialApp.router(
      title: 'CUBAG',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeService.themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return MediaQuery.withNoTextScaling(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

void _protectWebCollections() {
  final maps = <Map<String, dynamic>>[
    <String, String>{},
    const <String, String>{},
    const <String, String>{'a': 'b'},
    Map<String, String>.unmodifiable({'a': 'b'}),
    <String, dynamic>{'a': 'b'},
  ];
  for (final map in maps) {
    map.entries.where((e) => e.key == 'a').toList();
    map.keys.where((k) => k == 'a').toList();
    map.values.where((v) => v == 'b').toList();
  }
  final lists = <List<dynamic>>[
    [],
    ['a'],
    [1, 2, 3],
  ];
  for (final list in lists) {
    list.where((e) => e == 'a').toList();
    list.take(1).toList();
  }
}

void _preloadFonts() {
  GoogleFonts.pendingFonts([
    GoogleFonts.inter(fontWeight: FontWeight.w400),
    GoogleFonts.inter(fontWeight: FontWeight.w500),
    GoogleFonts.inter(fontWeight: FontWeight.w600),
    GoogleFonts.inter(fontWeight: FontWeight.w700),
    GoogleFonts.outfit(fontWeight: FontWeight.w400),
    GoogleFonts.outfit(fontWeight: FontWeight.w500),
    GoogleFonts.outfit(fontWeight: FontWeight.w600),
    GoogleFonts.outfit(fontWeight: FontWeight.w700),
    GoogleFonts.outfit(fontWeight: FontWeight.w800),
  ]);
}

Future<void> _initHiveCache() async {
  try {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen('api_cache')) {
      await Hive.openBox('api_cache');
    }
  } catch (e, st) {
    debugPrint('Hive cache initialization failed: $e');
    debugPrint('$st');
  }
}
