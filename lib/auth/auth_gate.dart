import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/premium_service.dart';
import '../services/pricing_location_service.dart';
import '../navigation/main_navigation.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _checked;
  String userId = "Player";

  @override
  void initState() {
    super.initState();
    checkAuth();
  }

  Future<void> checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // 🔐 Force refresh Firebase ID token
      final idToken = await user.getIdToken(true);
      if (idToken != null && idToken.isNotEmpty) {
        await prefs.setString("firebase_id_token", idToken);
      }

      // 🧠 Sync premium before entering app
      await PremiumService.syncFromFirestore(user.uid);

      debugPrint("AUTH_GATE → premium synced uid=${user.uid}");

      // 🌍 Detect IP at login and set pricing mode
      try {
        final region = await PricingLocationService.refreshPricingRegion(
          timeout: const Duration(seconds: 2),
        );
        debugPrint(
          region == PricingRegion.india
              ? "🇮🇳 LOGIN PRICING MODE => INR"
              : "🌎 LOGIN PRICING MODE => USD",
        );
      } catch (e) {
        debugPrint("❌ IP detection failed at login: $e");
      }

      userId = prefs.getString("userName") ?? "Player";
    }

    setState(() {
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checked == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      return MainNavigation(userName: userId);
    }

    return const LoginScreen();
  }
}
