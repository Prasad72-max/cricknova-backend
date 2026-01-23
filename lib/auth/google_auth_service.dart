import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/premium_service.dart';

class GoogleAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _googleSignIn = GoogleSignIn();

  static Future<bool> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return false;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);
      final user = userCred.user;

      if (user == null) return false;

      // 🔐 Force refresh Firebase ID token and store it
      final idToken = await userCred.user!.getIdToken(true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("firebaseIdToken", idToken);

      await prefs.setBool("isLoggedIn", true);
      await prefs.setString("loginType", "google");
      await prefs.setString("userId", user.uid);
      await prefs.setString("userEmail", user.email ?? "");
      await prefs.setString("userName", user.displayName ?? "Player");

      // 🔐 Sync premium from Firestore (source of truth)
      await PremiumService.syncFromFirestore(user.uid);

      return true;
    } catch (e) {
      print("GOOGLE LOGIN ERROR => $e");
      return false;
    }
  }
}