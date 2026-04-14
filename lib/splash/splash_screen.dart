import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/login_screen.dart';
import '../navigation/main_navigation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'intro_animation_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _controller.forward();

    _startFlow();
  }

  Future<void> _startFlow() async {
    await Future.delayed(const Duration(milliseconds: 250));

    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName ?? "Player";
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool("is_first_launch") ?? true;

    // 🔐 Stabilize Firebase ID token (do NOT force refresh)
    if (user != null) {
      await user.getIdToken();
    }

    if (!mounted) return;

    if (user != null) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, animation, secondaryAnimation) =>
              MainNavigation(userName: userName),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, animation, secondaryAnimation) => isFirstLaunch
              ? const IntroAnimationScreen()
              : const LoginScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const SizedBox.expand(),
    );
  }
}
