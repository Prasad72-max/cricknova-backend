import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:CrickNova_Ai/splash/splash_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:CrickNova_Ai/services/play_billing_service.dart';
import 'package:CrickNova_Ai/services/cricknova_marketing_notification_service.dart';
import 'package:CrickNova_Ai/services/cricknova_notification_service.dart';
import 'package:CrickNova_Ai/services/premium_service.dart';
import 'package:CrickNova_Ai/services/pricing_location_service.dart';
import 'package:CrickNova_Ai/services/subscription_provider.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  FirebaseMessaging.onBackgroundMessage(
    crickNovaFirebaseMessagingBackgroundHandler,
  );

  // Keep Hive ready before any screen tries to open chat/session boxes.
  await Hive.initFlutter();
  await PricingLocationService.primeFromCache();

  runApp(const MyApp());

  // Warm up non-critical services after first frame to reduce cold-start jank.
  unawaited(_warmStartup());
}

Future<void> _warmStartup() async {
  try {
    await CrickNovaNotificationService.instance.initialize();
  } catch (_) {}
  try {
    await CrickNovaMarketingNotificationService.instance.initialize();
  } catch (_) {}
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static State<MyApp>? of(BuildContext context) {
    return context.findAncestorStateOfType<_MyAppState>();
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<User?>? _authSub;

  void setTheme(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapNonCriticalStartup());
    });
  }

  Future<void> _bootstrapNonCriticalStartup() async {
    unawaited(
      PricingLocationService.bootstrap(timeout: const Duration(seconds: 5)),
    );

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        debugPrint("⚠️ AUTH: transient null ignored");
        return;
      }

      debugPrint("🔐 AUTH: stable user uid=${user.uid}");
      try {
        if (!PremiumService.isLoaded) {
          await PremiumService.restoreOnLaunch();
        } else {
          unawaited(PremiumService.refresh());
        }
        unawaited(
          PlayBillingService.instance.syncEntitlementToPremiumService(),
        );
      } catch (e) {
        debugPrint("❌ Premium refresh failed: $e");
      }
    });

    await Future<void>.delayed(const Duration(milliseconds: 600));
    unawaited(PlayBillingService.instance.initialize());
    unawaited(_initAppLinks());
  }

  Future<void> _initAppLinks() async {
    _appLinks = AppLinks();

    // Cold start
    final Uri? initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      await _handleDeepLink(initialUri);
    }

    // Warm start
    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      await _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    debugPrint("🔥 Deep link received: $uri");
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SubscriptionProvider>(
      create: (_) => SubscriptionProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,

        // 🌞 LIGHT THEME
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: Colors.grey[100],
          cardColor: Colors.white,
          dividerColor: Colors.black12,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.black),
            bodyMedium: TextStyle(color: Colors.black),
            bodySmall: TextStyle(color: Colors.black87),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),

        // 🌙 DARK THEME (GLOBAL)
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF050505),
          cardColor: const Color(0xFF111111),
          dividerColor: Colors.white12,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white),
            bodySmall: TextStyle(color: Colors.white70),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF050505),
            foregroundColor: Colors.white,
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
