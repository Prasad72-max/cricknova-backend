import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../navigation/main_navigation.dart';
import '../services/premium_service.dart';
import 'post_login_welcome_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> signInWithGoogle(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Show blocking loader
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        navigator.pop();
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
        navigator.pop();
        return;
      }

      // ✅ ALWAYS store Firebase ID token (not Google ID token)
      final firebaseIdToken = await user.getIdToken(true);
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        throw Exception("Failed to fetch Firebase ID token");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("firebase_id_token", firebaseIdToken);

      await prefs.setBool("is_logged_in", true);
      await prefs.setString("user_id", user.uid);
      await prefs.setString("login_type", "google");
      await prefs.setString("user_name", user.displayName ?? "Player");

      // 🔒 IMPORTANT: Clear any cached premium from previous user
      await PremiumService.clearPremium();

      // 🔥 Restore premium strictly for THIS user UID from Firestore
      await PremiumService.syncFromFirestore(user.uid);

      // 🔁 Force token refresh AFTER premium sync (critical for backend auth)
      final refreshedToken = await FirebaseAuth.instance.currentUser
          ?.getIdToken(true);
      if (refreshedToken == null || refreshedToken.isEmpty) {
        throw Exception(
          "Failed to refresh Firebase ID token after premium sync",
        );
      }
      await prefs.setString("firebase_id_token", refreshedToken);

      final userName = user.displayName ?? "Player";
      final showWelcomeEntrance = await PostLoginWelcomeScreen.shouldShowFor(
        prefs: prefs,
        user: user,
        explicitIsNewUser: userCredential.additionalUserInfo?.isNewUser,
      );
      if (showWelcomeEntrance) {
        await PostLoginWelcomeScreen.markSeen(prefs, user.uid);
      }

      // Close loader
      if (!context.mounted) return;
      navigator.pop();

      // Navigate only AFTER premium sync
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => showWelcomeEntrance
              ? PostLoginWelcomeScreen(userName: userName)
              : MainNavigation(userName: userName),
        ),
        (route) => false,
      );
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text("Google login failed"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            children: [
              const Spacer(),

              // LOGO + TITLE
              Column(
                children: const [
                  Icon(
                    Icons.sports_cricket,
                    size: 64,
                    color: Color(0xFF7CFF6B),
                    shadows: [
                      Shadow(color: Color(0xFF7CFF6B), blurRadius: 14),
                      Shadow(color: Color(0xAA7CFF6B), blurRadius: 24),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    "CrickNova AI",
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Where cricket meets intelligence",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              // GOOGLE BUTTON
              _loginButton(
                text: "Continue with Google",
                icon: Icons.g_mobiledata,
                color: Colors.white,
                textColor: Colors.black,
                onTap: () => signInWithGoogle(context),
              ),

              const SizedBox(height: 16),

              const Spacer(),

              const Text(
                "By continuing, you agree to our Terms & Privacy Policy",
                style: TextStyle(color: Colors.white38, fontSize: 11),
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
        height: 54,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: border ? Border.all(color: Colors.white24) : null,
          boxShadow: color != Colors.transparent
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(
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
