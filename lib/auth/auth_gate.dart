import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/premium_service.dart';
import '../navigation/main_navigation.dart';
import 'login_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
      await prefs.setString("firebase_id_token", idToken);

      // 🧠 Sync premium before entering app
      final premiumSynced =
          await PremiumService.syncFromFirestore(user.uid);

      debugPrint(
          "AUTH_GATE → premiumSynced=$premiumSynced uid=${user.uid}");

      // 🌍 Detect IP at login and set pricing mode
      try {
        final res = await http
            .get(Uri.parse("https://ipapi.co/json/"))
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final countryCode = data["country_code"];
          final ip = data["ip"];

          debugPrint("🌍 LOGIN IP DATA => $data");

          if (countryCode == "IN") {
            await prefs.setString("pricingMode", "INR");
            debugPrint("🇮🇳 PRICING MODE SET => INR");
          } else {
            await prefs.setString("pricingMode", "USD");
            debugPrint("🌎 PRICING MODE SET => USD");
          }

          debugPrint("🧠 USER IP => $ip | COUNTRY => $countryCode");
        }
      } catch (e) {
        debugPrint("❌ IP detection failed at login: $e");
        await prefs.setString("pricingMode", "USD");
        debugPrint("🌎 FALLBACK PRICING MODE SET => USD");
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