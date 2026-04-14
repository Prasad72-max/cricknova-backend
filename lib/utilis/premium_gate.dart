import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ✅ CENTRAL SINGLE SOURCE OF TRUTH FOR PREMIUM (READ-ONLY)
/// --------------------------------------------------------
/// • UI must NEVER decide premium by itself
/// • Premium is valid ONLY if a valid subscription exists
/// • Reads from `subscriptions` collection (NOT users)
/// • No navigation side effects
class PremiumGate {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static bool _isPremium = false;
  static String _plan = "FREE";
  static bool _initialized = false;

  /// 🔁 Call ONCE after login / splash
  static Future<void> sync() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _reset();
      return;
    }

    try {
      final doc = await _firestore
          .collection("subscriptions")
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) {
        _reset();
        return;
      }

      final data = doc.data()!;
      final expiryRaw =
          data["expiry"] ?? data["expiryDate"] ?? data["expiry_date"];

      DateTime? expiry;
      if (expiryRaw is Timestamp) {
        expiry = expiryRaw.toDate();
      } else if (expiryRaw is String) {
        expiry = DateTime.tryParse(expiryRaw);
      }

      if (expiry == null || DateTime.now().isAfter(expiry)) {
        _reset();
        return;
      }

      _isPremium = true;
      _plan = data["plan"] ?? "UNKNOWN";
      _initialized = true;
    } catch (_) {
      // keep last known safe state
    }
  }

  static bool get ready => _initialized;

  /// ✅ SAFE CHECK (NO FIRESTORE CALL)
  static bool get isPremium => _isPremium;

  static String get plan => _plan;

  static void _reset() {
    _isPremium = false;
    _plan = "FREE";
    _initialized = true;
  }
}