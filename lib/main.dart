import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:CrickNova_Ai/splash/splash_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:CrickNova_Ai/config/api_config.dart';
import 'package:CrickNova_Ai/services/premium_service.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<_MyAppState>();
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  void setTheme(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.idTokenChanges().listen((user) async {
      if (user == null) {
        debugPrint("🔐 AUTH: user signed out / null");
      } else {
        debugPrint("🔐 AUTH: idToken changed for uid=${user.uid}");
        await PremiumService.restoreOnLaunch();
      }
    });
    _initAppLinks();
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

    if (uri.scheme == 'cricknova' && uri.host == 'paypal-success') {
      debugPrint("✅ PayPal success detected");
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await PremiumService.syncFromBackend(user.uid);
      }
    }

    if (uri.scheme == 'cricknova' && uri.host == 'paypal-cancel') {
      debugPrint("❌ PayPal cancelled by user");
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    );
  }
}