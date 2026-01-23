import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/premium_service.dart';
import '../navigation/main_navigation.dart';
import 'login_screen.dart';
import 'package:flutter/foundation.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? isLoggedIn;
  String userId = "Player";

  @override
  void initState() {
    super.initState();
    checkAuth();
  }

  Future<void> checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();

    final loggedIn = prefs.getBool("isLoggedIn") ?? false;
    final storedUserName = prefs.getString("userName") ?? "Player";

    if (loggedIn) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 🔐 Force refresh Firebase ID token
        final idToken = await user.getIdToken(true);

        // 💾 Store token globally for API usage
        await prefs.setString("firebase_id_token", idToken);

        // 🧠 IMPORTANT: wait for premium sync BEFORE entering app
        final premiumSynced =
            await PremiumService.syncFromFirestore(user.uid);

        debugPrint(
            "AUTH_GATE → premiumSynced=$premiumSynced uid=${user.uid}");
      }
    }

    setState(() {
      isLoggedIn = loggedIn;
      userId = storedUserName;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (isLoggedIn!) {
      return MainNavigation(userName: userId);
    }

    return const LoginScreen();
  }
}