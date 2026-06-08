import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../auth/login_screen.dart';
import '../navigation/main_navigation.dart';
import '../onboarding/cricknova_onboarding_screen.dart';
import '../onboarding/cricknova_onboarding_store.dart';
import '../onboarding/onboarding_ui_tokens.dart';
import '../services/backend_warmup_service.dart';
import '../services/premium_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.startupFuture});

  final Future<void> startupFuture;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashNavigationTarget {
  const _SplashNavigationTarget.online(this.destination) : hasInternet = true;

  const _SplashNavigationTarget.offline()
    : hasInternet = false,
      destination = null;

  final bool hasInternet;
  final Widget? destination;
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _onboardingSeenKey = 'cricknova_onboarding_seen_once';
  static const Duration _startupTimeout = Duration(seconds: 3);
  static const Duration _authRestoreTimeout = Duration(milliseconds: 500);
  bool _fadeOut = false;
  bool _networkDialogOpen = false;

  final String _taglineFull = 'TRAIN LIKE A PRO. POWERED BY AI.';
  String _taglineTyped = '';
  bool _cursorOn = true;

  Timer? _typingTimer;
  Timer? _cursorTimer;
  Timer? _advanceTimer;
  Future<_SplashNavigationTarget>? _navigationTargetFuture;

  @override
  void initState() {
    super.initState();
    unawaited(BackendWarmupService.instance.wake(force: true));
    _startCursorBlinking();
    _startTaglineTyping();
    _navigationTargetFuture = _prepareNavigationTarget();
    // Keep the final brand splash polished without repeating the player logo.
    _advanceTimer = Timer(const Duration(seconds: 3), _advance);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache both image assets for smooth, lag-free premium rendering
    precacheImage(const AssetImage('assets/images/splash_player.png'), context);
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

  void _startCursorBlinking() {
    _cursorTimer?.cancel();
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _cursorOn = !_cursorOn);
    });
  }

  void _startTaglineTyping() {
    _typingTimer?.cancel();
    int i = 0;
    _typingTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _typingTimer = Timer.periodic(const Duration(milliseconds: 12), (t) {
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

    late final _SplashNavigationTarget target;
    try {
      target = await (_navigationTargetFuture ??= _prepareNavigationTarget());
    } catch (error, stackTrace) {
      debugPrint('Splash navigation fallback: $error\n$stackTrace');
      target = await _fallbackNavigationTarget();
    }
    if (!mounted) return;
    if (!target.hasInternet || target.destination == null) {
      await _showNetworkErrorDialog();
      return;
    }

    setState(() => _fadeOut = true);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            target.destination!,
      ),
    );
  }

  Future<_SplashNavigationTarget> _prepareNavigationTarget() async {
    try {
      await widget.startupFuture.timeout(_startupTimeout);
    } catch (error) {
      // Startup services must never leave the visible splash blocked forever.
      debugPrint('Splash startup continued after error/timeout: $error');
    }

    if (kIsWeb) {
      final user = await _restoredFirebaseUser();
      final userName = user?.displayName ?? 'Player';
      if (user != null) {
        try {
          await PremiumService.ensureFreshState();
        } catch (_) {}
        return _SplashNavigationTarget.online(
          MainNavigation(userName: userName),
        );
      }
      return const _SplashNavigationTarget.online(
        LoginScreen(postLoginTarget: LoginPostLoginTarget.getStarted),
      );
    }

    if (Platform.isMacOS && Firebase.apps.isEmpty) {
      return _localNavigationTarget();
    }

    final prefs = await SharedPreferences.getInstance();
    final user = await _restoredFirebaseUser();
    final userName = await _resolvedCachedUserName(prefs, user);
    final onboardingSeen = prefs.getBool(_onboardingSeenKey) ?? false;
    final pendingAnswers = await CricknovaOnboardingStore.loadPendingAnswers();
    final pendingCompleted = await CricknovaOnboardingStore.isPendingCompleted();

    if (user != null) {
      // Signed-in users must not be sent back to Google login on every app
      // launch. Let Firebase's persisted native session win before any network
      // checks, because DNS/Firestore can be slow while auth is already valid.
      unawaited(_refreshReturningUserInBackground(user));
      return _SplashNavigationTarget.online(MainNavigation(userName: userName));
    }

    if (_hadSavedLogin(prefs)) {
      final cachedName =
          prefs.getString('userName') ??
          prefs.getString('user_name') ??
          prefs.getString('displayName') ??
          'Player';
      unawaited(_restoreGoogleSessionSilently());
      return _SplashNavigationTarget.online(
        MainNavigation(userName: cachedName),
      );
    }

    // Desktop DNS/network permissions can be delayed independently of the
    // actual Firebase connection, so do not gate macOS startup on a DNS probe.
    if (!Platform.isMacOS) {
      final hasInternet = await _hasInternetConnection();
      if (!hasInternet) {
        return const _SplashNavigationTarget.offline();
      }
    }

    if (pendingAnswers.isNotEmpty && !pendingCompleted) {
      return const _SplashNavigationTarget.online(
        CricknovaOnboardingScreen(userName: 'Player', skipGetStarted: false),
      );
    }

    if (!onboardingSeen) {
      await prefs.setBool(_onboardingSeenKey, true);
      return const _SplashNavigationTarget.online(
        CricknovaOnboardingScreen(userName: 'Player', skipGetStarted: false),
      );
    }
    return const _SplashNavigationTarget.online(
      LoginScreen(postLoginTarget: LoginPostLoginTarget.getStarted),
    );
  }

  Future<_SplashNavigationTarget> _fallbackNavigationTarget() async {
    try {
      return await _localNavigationTarget();
    } catch (error) {
      debugPrint('Splash local fallback failed: $error');
    }

    return const _SplashNavigationTarget.online(
      LoginScreen(postLoginTarget: LoginPostLoginTarget.getStarted),
    );
  }

  Future<_SplashNavigationTarget> _localNavigationTarget() async {
    final prefs = await SharedPreferences.getInstance();
    if (Platform.isMacOS && Firebase.apps.isEmpty) {
      return const _SplashNavigationTarget.online(
        MainNavigation(userName: 'Player'),
      );
    }

    if (Firebase.apps.isNotEmpty) {
      final user = await _restoredFirebaseUser();
      if (user != null) {
        return _SplashNavigationTarget.online(
          MainNavigation(userName: user.displayName ?? 'Player'),
        );
      }
    }

    final onboardingSeen = prefs.getBool(_onboardingSeenKey) ?? false;
    final pendingAnswers = await CricknovaOnboardingStore.loadPendingAnswers();
    final pendingCompleted = await CricknovaOnboardingStore.isPendingCompleted();
    if (pendingAnswers.isNotEmpty && !pendingCompleted) {
      return const _SplashNavigationTarget.online(
        CricknovaOnboardingScreen(userName: 'Player', skipGetStarted: false),
      );
    }
    if (!onboardingSeen) {
      await prefs.setBool(_onboardingSeenKey, true);
      return const _SplashNavigationTarget.online(
        CricknovaOnboardingScreen(userName: 'Player', skipGetStarted: false),
      );
    }
    return const _SplashNavigationTarget.online(
      LoginScreen(postLoginTarget: LoginPostLoginTarget.getStarted),
    );
  }

  Future<User?> _restoredFirebaseUser() async {
    if (Firebase.apps.isEmpty) return null;
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    final prefs = await SharedPreferences.getInstance();
    final hadSavedLogin = _hadSavedLogin(prefs);
    try {
      return await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(_authRestoreTimeout);
    } catch (_) {
      final restored = FirebaseAuth.instance.currentUser;
      if (restored != null || !hadSavedLogin) return restored;
      return _restoreGoogleSessionSilently();
    }
  }

  bool _hadSavedLogin(SharedPreferences prefs) {
    return prefs.getBool('is_logged_in') == true ||
        prefs.getBool('isLoggedIn') == true ||
        (prefs.getString('user_id')?.isNotEmpty ?? false) ||
        (prefs.getString('uid')?.isNotEmpty ?? false);
  }

  Future<User?> _restoreGoogleSessionSilently() async {
    try {
      final googleUser = await GoogleSignIn().signInSilently();
      if (googleUser == null) return FirebaseAuth.instance.currentUser;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      return userCredential.user ?? FirebaseAuth.instance.currentUser;
    } catch (error) {
      debugPrint('Silent auth restore failed: $error');
      return FirebaseAuth.instance.currentUser;
    }
  }

  Future<void> _refreshReturningUserInBackground(User user) async {
    try {
      await PremiumService.ensureFreshState();
    } catch (_) {}
    try {
      await CricknovaOnboardingStore.syncOnboardingNameFromFirestore(user.uid);
    } catch (_) {}
  }

  Future<String> _resolvedCachedUserName(
    SharedPreferences prefs,
    User? user,
  ) async {
    final uid = user?.uid;
    final candidates = <String?>[
      if (uid != null) prefs.getString('profileName_$uid'),
      if (uid != null) prefs.getString('userName_$uid'),
      prefs.getString('profileName'),
      prefs.getString('userName'),
      prefs.getString('user_name'),
      prefs.getString('displayName'),
      user?.displayName,
    ];
    for (final candidate in candidates) {
      final name = candidate?.trim();
      if (name != null && name.isNotEmpty && name.toLowerCase() != 'player') {
        return name;
      }
    }
    return 'Player';
  }

  Future<bool> _hasInternetConnection() async {
    if (kIsWeb) {
      return true;
    }
    try {
      final result = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(milliseconds: 700));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showNetworkErrorDialog() async {
    if (_networkDialogOpen) return;
    _networkDialogOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111113),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF2A2A2F)),
          ),
          title: Text(
            'Network error',
            style: OnboardingTextStyles.uiSans(
              color: OnboardingColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Please turn on mobile data or Wi-Fi to continue.',
            style: OnboardingTextStyles.uiSans(
              color: OnboardingColors.textSecondary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _networkDialogOpen = false;
                _navigationTargetFuture = _prepareNavigationTarget();
                unawaited(_advance());
              },
              child: Text(
                'Retry',
                style: OnboardingTextStyles.uiSans(
                  color: const Color(0xFFD4AF37),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    _networkDialogOpen = false;
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [
              Color(
                0xFF151718,
              ), // Elegant warm charcoal center (matches center of your image)
              Color(0xFF050506), // Deep near-black vignette outer edges
            ],
          ),
        ),
        child: SafeArea(child: _buildSplash()),
      ),
    );
  }

  Widget _buildSplash() {
    return AnimatedOpacity(
      key: const ValueKey('splash'),
      opacity: _fadeOut ? 0 : 1,
      duration: const Duration(milliseconds: 180),
      curve: OnboardingUiTokens.motionEaseIn,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildBrandLogo(),
        ),
      ),
    );
  }

  Widget _buildBrandLogo() {
    final cursor = _cursorOn ? '|' : '';
    final tagline = '$_taglineTyped$cursor';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final scale = 0.92 + (t * 0.08);
            final letterSpacing = lerpDouble(14, -1.2, t)!;
            final blur = (1.0 - t) * 8.0;

            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: t,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Elegant circular cricketer player logo (matching launch style, without CN letters overlay!)
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                          boxShadow: [
                            // Intense gold lighting splash behind brand logo
                            BoxShadow(
                              color: const Color(
                                0xFFFFD700,
                              ).withValues(alpha: 0.3 * t),
                              blurRadius: 20 * t,
                              spreadRadius: 1 * t,
                            ),
                            BoxShadow(
                              color: const Color(
                                0xFFD4AF37,
                              ).withValues(alpha: 0.2 * t),
                              blurRadius: 30 * t,
                              spreadRadius: 3 * t,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/splash_player.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Soft gold glow behind the logo
                          Text(
                            'CrickNova',
                            style:
                                OnboardingTextStyles.serif(
                                  color: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.2 * t),
                                  fontSize: 52,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: letterSpacing,
                                ).copyWith(
                                  shadows: [
                                    Shadow(
                                      color: const Color(
                                        0xFFD4AF37,
                                      ).withValues(alpha: 0.4 * t),
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
    );
  }
}
