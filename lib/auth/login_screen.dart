import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../navigation/main_navigation.dart';
import '../onboarding/cricknova_onboarding_store.dart';
import '../onboarding/cricknova_onboarding_screen.dart';
import '../onboarding/cricknova_paywall_reel_screen.dart';
import '../onboarding/cricknova_pre_paywall_flow_screen.dart';
import '../onboarding/onboarding_ui_tokens.dart';
import '../services/premium_service.dart';

enum LoginPostLoginTarget {
  auto,
  app,
  onboarding,
  paywall,
  getStarted,
  signInCheck,
}

class LoginScreen extends StatelessWidget {
  final LoginPostLoginTarget postLoginTarget;
  final bool skipOnboardingGetStarted;

  const LoginScreen({
    super.key,
    this.postLoginTarget = LoginPostLoginTarget.auto,
    this.skipOnboardingGetStarted = false,
  });

  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<bool> _firestoreUserExists(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> _storeSession(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final firebaseIdToken = await user.getIdToken();
    if (firebaseIdToken != null && firebaseIdToken.isNotEmpty) {
      await prefs.setString("firebase_id_token", firebaseIdToken);
    }

    await prefs.setBool("is_logged_in", true);
    await prefs.setString("user_id", user.uid);
    await prefs.setString("login_type", "google");
    await prefs.setString("user_name", user.displayName ?? "Player");
    await prefs.setString("userName", user.displayName ?? "Player");
  }

  Future<void> _finishLoginWarmup(User user) async {
    try {
      final refreshedToken = await user.getIdToken(true);
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("firebase_id_token", refreshedToken);
      }
    } catch (_) {}
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    bool loaderOpen = false;
    try {
      // Show blocking loader
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      loaderOpen = true;

      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        try {
          await FirebaseAuth.instance.signOut();
          await _googleSignIn.signOut();
        } catch (_) {}
        if (loaderOpen && navigator.canPop()) {
          navigator.pop();
        }
        return;
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final user = userCredential.user;
      if (user == null) {
        if (loaderOpen && navigator.canPop()) {
          navigator.pop();
        }
        return;
      }

      final userName = user.displayName ?? "Player";

      try {
        await _storeSession(user);
      } catch (_) {}

      try {
        await CricknovaOnboardingStore.promotePendingToUser(user.uid);
        await CricknovaOnboardingStore.syncOnboardingNameFromFirestore(
          user.uid,
        );
        await CricknovaOnboardingStore.markCompleted(user.uid);
      } catch (_) {}

      try {
        await PremiumService.clearPremium();
      } catch (_) {}

      try {
        await PremiumService.ensureFreshState();
      } catch (_) {}

      // Close loader
      if (!context.mounted) return;
      if (loaderOpen && navigator.canPop()) {
        navigator.pop();
      }
      loaderOpen = false;

      if (!context.mounted) return;
      unawaited(_finishLoginWarmup(user));

      bool exists = await _firestoreUserExists(user.uid);

      // If the user doesn't exist in Firestore, check if their Firebase Auth
      // account is actually an old account (e.g. created before we enforced
      // Firestore doc creation on every login). If it's old (>5 mins), they
      // are a returning user who just lost or never had their Firestore doc.
      if (!exists) {
        final creationTime = user.metadata.creationTime;
        if (creationTime != null) {
          final diff = DateTime.now().difference(creationTime);
          if (diff.inMinutes > 5) {
            // This is an old Firebase user! Create their Firestore doc now.
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                    'name': userName,
                    'source': 'google_auth_legacy_migration',
                  }, SetOptions(merge: true));
              exists = true; // Treat them as existing so they bypass onboarding
            } catch (e) {
              debugPrint('Error creating legacy user doc: $e');
            }
          }
        }
      }

      // If the user has reached the end of onboarding (paywall/app target)
      // but doesn't have a Firestore document yet (e.g. they just re-registered
      // after account deletion), create a base document so they are recognized
      // as a returning user on the next app launch.
      if (!exists &&
          (postLoginTarget == LoginPostLoginTarget.paywall ||
              postLoginTarget == LoginPostLoginTarget.app)) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
                'name': userName,
                'source': 'google_auth',
              }, SetOptions(merge: true));
          exists = true; // They are now registered
        } catch (e) {
          debugPrint('Error creating base user doc: $e');
        }
      }

      if (exists) {
        try {
          await PremiumService.ensureFreshState();
        } catch (_) {}
      }

      Widget signedInDestination({bool usePrePaywall = false}) {
        final bool isPremium = PremiumService.isPremiumActive;
        if (isPremium) {
          return MainNavigation(userName: userName);
        }
        if (usePrePaywall) {
          return CricknovaPrePaywallFlowScreen(
            userName: userName,
            allowSkipToApp: false,
          );
        }
        return CricknovaPaywallReelScreen(userName: userName);
      }

      final Widget destination = switch (postLoginTarget) {
        LoginPostLoginTarget.paywall =>
          PremiumService.isPremiumActive
              ? MainNavigation(userName: userName)
              : CricknovaPaywallReelScreen(userName: userName),
        LoginPostLoginTarget.app => MainNavigation(userName: userName),
        LoginPostLoginTarget.onboarding => await (() async {
          if (exists) {
            return signedInDestination();
          }
          await CricknovaOnboardingStore.clearCompleted(user.uid);
          return CricknovaOnboardingScreen(
            userName: userName,
            skipGetStarted: skipOnboardingGetStarted,
          );
        })(),
        LoginPostLoginTarget.getStarted => await (() async {
          if (exists) {
            return signedInDestination(usePrePaywall: true);
          }
          // New account not in Firestore — sign them out so the
          // welcome pane's "Sign in" button can pick a different account.
          await CricknovaOnboardingStore.clearCompleted(user.uid);
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          try {
            await _googleSignIn.signOut();
          } catch (_) {}
          return CricknovaOnboardingScreen(
            userName: userName,
            skipGetStarted: false, // show welcome step WITH sign-in button
          );
        })(),
        LoginPostLoginTarget.signInCheck => await (() async {
          if (exists) {
            return signedInDestination();
          }
          await CricknovaOnboardingStore.clearCompleted(user.uid);
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          try {
            await _googleSignIn.signOut();
          } catch (_) {}
          return CricknovaOnboardingScreen(
            userName: userName,
            skipGetStarted: false, // show welcome step WITH sign-in button
            entryNotice:
                'Account not found. Complete the questions or sign in with a registered account.',
          );
        })(),
        LoginPostLoginTarget.auto => await (() async {
          if (exists) {
            return signedInDestination();
          }
          await CricknovaOnboardingStore.clearCompleted(user.uid);
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          try {
            await _googleSignIn.signOut();
          } catch (_) {}
          return CricknovaOnboardingScreen(
            userName: userName,
            skipGetStarted: false, // show welcome step WITH sign-in button
          );
        })(),
      };

      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => destination),
        (route) => false,
      );
    } catch (e) {
      try {
        await FirebaseAuth.instance.signOut();
        await _googleSignIn.signOut();
      } catch (_) {}
      if (loaderOpen && navigator.canPop()) {
        navigator.pop();
      }
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Login failed. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: OnboardingColors.bgSurface,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: OnboardingColors.borderSubtle),
                    ),
                    child: const Icon(
                      Icons.sports_cricket_rounded,
                      size: 42,
                      color: OnboardingColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'CrickNova',
                    textAlign: TextAlign.center,
                    style: OnboardingTextStyles.uiSans(
                      color: OnboardingColors.textPrimary,
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in to continue with your personalized cricket plan.',
                    textAlign: TextAlign.center,
                    style: OnboardingTextStyles.uiSans(
                      color: OnboardingColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              _loginButton(
                text: 'Continue with Google',
                icon: Icons.g_mobiledata,
                color: OnboardingColors.textPrimary,
                textColor: OnboardingColors.ctaText,
                onTap: () => signInWithGoogle(context),
              ),
              const SizedBox(height: 18),
              Text(
                'Your saved answers will be ready after login.',
                textAlign: TextAlign.center,
                style: OnboardingTextStyles.uiSans(
                  color: OnboardingColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              Text(
                'By continuing, you agree to our Terms & Privacy Policy',
                style: OnboardingTextStyles.uiSans(
                  color: OnboardingColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _loginButton({
    required String text,
    required IconData icon,
    required Color color,
    required Color textColor,
    bool border = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          border: border ? Border.all(color: Colors.white24) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor),
            const SizedBox(width: 10),
            Text(
              text,
              style: OnboardingTextStyles.uiSans(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
