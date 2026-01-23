import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../navigation/main_navigation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/premium_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      // Show blocking loader
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        Navigator.pop(context);
        return;
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
        Navigator.pop(context);
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

      // 🔥 HARD BLOCK: backend is source of truth
      // This MUST complete before Home is shown
      await PremiumService.restoreOnLaunch();

      // Close loader
      Navigator.pop(context);

      // Navigate only AFTER premium sync
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MainNavigation(userName: user.displayName ?? "Player"),
        ),
        (route) => false,
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
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
                  Icon(Icons.sports_cricket,
                      size: 64, color: Colors.blueAccent),
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
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
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
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                  )
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