import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/login_screen.dart';
import '../navigation/main_navigation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'intro_animation_screen.dart';
import '../security/vpn_guard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _vpnBlocked = false;
  bool _checkingVpn = false;

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
    if (_checkingVpn) return;
    setState(() {
      _checkingVpn = true;
    });

    final vpnActive = await VpnGuard.isVpnActive();
    if (!mounted) return;
    if (vpnActive) {
      setState(() {
        _vpnBlocked = true;
        _checkingVpn = false;
      });
      return;
    }

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

    if (!mounted) return;
    setState(() {
      _checkingVpn = false;
    });
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
      body: Center(
        child: AnimatedOpacity(
          opacity: _vpnBlocked ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: _vpnBlocked
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Disable VPN to Continue",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "For security reasons CrickNova AI does not work over VPN. Turn off VPN and retry.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _checkingVpn
                              ? null
                              : () async {
                                  setState(() {
                                    _vpnBlocked = false;
                                  });
                                  await _startFlow();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _checkingVpn ? "Checking..." : "Retry",
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
