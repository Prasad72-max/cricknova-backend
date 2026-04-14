

import 'package:firebase_auth/firebase_auth.dart';

/// 🔐 Single source of truth for backend auth headers
/// ALWAYS use Firebase ID token (not accessToken)
Future<Map<String, String>> authHeader() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception("USER_NOT_LOGGED_IN");
  }

  // Force refresh to avoid expired / malformed tokens
  final String idToken = await user.getIdToken(true);

  return {
    "Authorization": "Bearer $idToken",
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
}