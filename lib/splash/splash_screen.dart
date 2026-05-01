import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen.dart';
import '../navigation/main_navigation.dart';
import '../onboarding/cricknova_paywall_screen.dart';
import '../onboarding/cricknova_onboarding_screen.dart';
import '../onboarding/onboarding_ui_tokens.dart';
import '../services/premium_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _onboardingSeenKey = 'cricknova_onboarding_seen_once';
  bool _fadeOut = false;

  final String _taglineFull = 'TRAIN LIKE A PRO. POWERED BY AI.';
  String _taglineTyped = '';
  bool _cursorOn = true;

  Timer? _typingTimer;
  Timer? _cursorTimer;
  Timer? _advanceTimer;

  @override
  void initState() {
    super.initState();
    _startTaglineTyping();
    _advanceTimer = Timer(const Duration(milliseconds: 3200), _advance);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache immersive visuals for paywall/pre-paywall screens
    precacheImage(
      const NetworkImage(
        'https://images.unsplash.com/photo-1509042239860-f550ce710b93?q=80&w=800&h=800&fit=crop',
      ),
      context,
    );
    precacheImage(
      const NetworkImage(
        'https://images.unsplash.com/photo-1595769816263-9b910be24d5f?q=80&w=800&h=800&fit=crop',
      ),
      context,
    );
  }

  void _startTaglineTyping() {
    _cursorTimer?.cancel();
    _typingTimer?.cancel();
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _cursorOn = !_cursorOn);
    });

    int i = 0;
    _typingTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _typingTimer = Timer.periodic(const Duration(milliseconds: 22), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (i >= _taglineFull.length) {
          t.cancel();
          return;
        }
        i++;
        setState(() {
          _taglineTyped = _taglineFull.substring(0, i);
        });
      });
    });
  }

  Future<void> _advance() async {
    if (!mounted) return;
    if (_fadeOut) return;
    setState(() => _fadeOut = true);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName ?? 'Player';
    final onboardingSeen = prefs.getBool(_onboardingSeenKey) ?? false;

    late final Widget destination;
    if (user != null) {
      destination = PremiumService.isPremiumActive
          ? MainNavigation(userName: userName)
          : CricknovaPaywallScreen(userName: userName);
    } else if (!onboardingSeen) {
      await prefs.setBool(_onboardingSeenKey, true);
      destination = const CricknovaOnboardingScreen(
        userName: 'Player',
        skipGetStarted: false,
      );
    } else {
      destination = const LoginScreen(
        postLoginTarget: LoginPostLoginTarget.getStarted,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) => destination,
      ),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _cursorTimer?.cancel();
    _advanceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingColors.bgBase,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _buildSplash(),
        ),
      ),
    );
  }

  Widget _buildSplash() {
    final cursor = _cursorOn ? '|' : '';
    final tagline = '$_taglineTyped$cursor';
    return AnimatedOpacity(
      key: const ValueKey('splash'),
      opacity: _fadeOut ? 0 : 1,
      duration: const Duration(milliseconds: 400),
      curve: OnboardingUiTokens.motionEaseIn,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) {
                  final scale = 0.92 + (t * 0.12);
                  final letterSpacing = lerpDouble(14, -1.2, t)!;
                  final blur = (1.0 - t) * 10.0;
                  
                  return Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: t,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Soft gold glow behind the logo
                            Text(
                              'CrickNova',
                              style: OnboardingTextStyles.serif(
                                color: const Color(0xFFD4AF37).withValues(alpha: 0.2 * t),
                                fontSize: 52,
                                fontWeight: FontWeight.w300,
                                letterSpacing: letterSpacing,
                              ).copyWith(
                                shadows: [
                                  Shadow(
                                    color: const Color(0xFFD4AF37).withValues(alpha: 0.4 * t),
                                    blurRadius: 30 * t,
                                  ),
                                ],
                              ),
                            ),
                            // Main white logo text
                            Text(
                              'CrickNova',
                              style: OnboardingTextStyles.serif(
                                color: const Color(0xFFFAFAF9),
                                fontSize: 52,
                                fontWeight: FontWeight.w300,
                                letterSpacing: letterSpacing,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                tagline,
                textAlign: TextAlign.center,
                style: OnboardingTextStyles.uiSans(
                  color: OnboardingColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
