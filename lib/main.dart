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
import 'package:CrickNova_Ai/app_router.dart';
import 'package:CrickNova_Ai/models/pending_video.dart';
import 'package:CrickNova_Ai/services/background_analysis_service.dart';
import 'package:CrickNova_Ai/services/backend_warmup_service.dart';
import 'package:CrickNova_Ai/services/app_analytics.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using currentPlatform options so that all services
  // (like FirebaseAuth in _initializeCriticalStorage) can safely run immediately.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (error) {
    // macOS development builds may not include a Firebase plist. Keep the
    // local app usable instead of blocking forever on the splash screen.
    debugPrint('Firebase startup unavailable: $error');
  }

  // Fire immediately on app icon tap so Render can wake while splash/onboarding
  // routing is still preparing.
  unawaited(BackendWarmupService.instance.wake(force: true));

  // Hive is required by several first-frame screens. Finish its lightweight
  // initialization before runApp so no widget can access a box too early.
  await _initializeCriticalStorage();

  final startupFuture = _initializeStartup();

  runApp(MyApp(startupFuture: startupFuture));

  // Warm up non-critical services after first frame to reduce cold-start jank.
  unawaited(startupFuture.then((_) => _warmStartup()));
}

Future<void> _initializeStartup() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (error) {
    // macOS development builds may not include a Firebase plist. Keep the
    // local app usable instead of blocking forever on the splash screen.
    debugPrint('Firebase startup unavailable: $error');
  }

  if (Firebase.apps.isNotEmpty) {
    FirebaseMessaging.onBackgroundMessage(
      crickNovaFirebaseMessagingBackgroundHandler,
    );
  }

  await PricingLocationService.primeFromCache();
}

Future<void> _initializeCriticalStorage() async {
  try {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(42)) {
      Hive.registerAdapter(PendingVideoAdapter());
    }
    if (!Hive.isBoxOpen('pending_videos')) {
      await Hive.openBox<PendingVideo>('pending_videos');
    }
    if (!Hive.isBoxOpen('analysis_cache')) {
      await Hive.openBox('analysis_cache');
    }
    if (!Hive.isBoxOpen('quick_stats_cache')) {
      await Hive.openBox('quick_stats_cache');
    }
    if (!Hive.isBoxOpen('speedBox')) {
      await Hive.openBox('speedBox');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && !Hive.isBoxOpen('local_stats_$uid')) {
      await Hive.openBox('local_stats_$uid');
    }
    await PremiumService.restoreCachedState();
    debugPrint("HIVE BOXES INITIALIZED (pending_videos, analysis_cache)");
  } catch (error, stackTrace) {
    // Keep startup alive if an optional cached box is damaged. Screens can
    // still recreate/open their user-specific boxes after launch.
    debugPrint("HIVE CRITICAL INIT ERROR: $error");
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> _warmStartup() async {
  unawaited(BackendWarmupService.instance.wake());

  try {
    await CrickNovaNotificationService.instance.initialize();
  } catch (_) {}
  try {
    await CrickNovaMarketingNotificationService.instance.initialize();
  } catch (_) {}

  if (Firebase.apps.isNotEmpty) {
    // Start background analysis checker only when its Firebase dependency is ready.
    BackgroundAnalysisService.instance.start();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.startupFuture});

  final Future<void> startupFuture;

  static State<MyApp>? of(BuildContext context) {
    return context.findAncestorStateOfType<_MyAppState>();
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapNonCriticalStartup());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(BackendWarmupService.instance.wake());
    unawaited(
      PricingLocationService.refreshPricingRegion(
        timeout: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _bootstrapNonCriticalStartup() async {
    await widget.startupFuture;

    unawaited(
      PricingLocationService.bootstrap(timeout: const Duration(seconds: 5)),
    );

    if (Firebase.apps.isNotEmpty) {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user == null) {
          debugPrint("⚠️ AUTH: transient null ignored");
          return;
        }

        debugPrint("🔐 AUTH: stable user uid=${user.uid}");
        try {
          unawaited(AppAnalytics.ensureUserTrackingDefaults());
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
    }

    if (Firebase.apps.isNotEmpty) {
      unawaited(PlayBillingService.instance.initialize());
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SubscriptionProvider>(
      create: (_) => SubscriptionProvider(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [FirestoreScreenObserver()],
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
            foregroundColor: Colors.white,
            iconTheme: IconThemeData(color: Colors.white),
            actionsIconTheme: IconThemeData(color: Colors.white),
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
            iconTheme: IconThemeData(color: Colors.white),
            actionsIconTheme: IconThemeData(color: Colors.white),
          ),
        ),
        home: SplashScreen(startupFuture: widget.startupFuture),
      ),
    );
  }
}
