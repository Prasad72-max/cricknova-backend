import 'package:shared_preferences/shared_preferences.dart';

class PlanService {
  // -----------------------------
  // BASIC PLAN CHECK
  // -----------------------------
  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    // If limits exist, user is premium
    return prefs.getInt("chatLimit") != null;
  }

  // -----------------------------
  // PAYMENT SOURCE (PAYPAL / PLAY)
  // -----------------------------
  static Future<void> setPaymentSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("paymentSource", source); // paypal | play
  }

  static Future<String?> getPaymentSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("paymentSource");
  }

  // -----------------------------
  // CHAT LIMIT
  // -----------------------------
  static Future<bool> canUseChat() async {
    final prefs = await SharedPreferences.getInstance();
    final limit = prefs.getInt("chatLimit") ?? 0;
    final used = prefs.getInt("chatUsed") ?? 0;
    return used < limit;
  }

  static Future<void> incrementChat() async {
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt("chatUsed") ?? 0;
    await prefs.setInt("chatUsed", used + 1);
  }

  // -----------------------------
  // MISTAKE ANALYSIS LIMIT
  // -----------------------------
  static Future<bool> canUseMistake() async {
    final prefs = await SharedPreferences.getInstance();
    final limit = prefs.getInt("mistakeLimit") ?? 0;
    final used = prefs.getInt("mistakeUsed") ?? 0;
    return used < limit;
  }

  static Future<void> incrementMistake() async {
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt("mistakeUsed") ?? 0;
    await prefs.setInt("mistakeUsed", used + 1);
  }

  // -----------------------------
  // VIDEO / DIFF LIMIT (OPTIONAL)
  // -----------------------------
  static Future<bool> canUseDiff() async {
    final prefs = await SharedPreferences.getInstance();
    final limit = prefs.getInt("diffLimit") ?? 0;
    final used = prefs.getInt("diffUsed") ?? 0;
    return used < limit;
  }

  static Future<void> incrementDiff() async {
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt("diffUsed") ?? 0;
    await prefs.setInt("diffUsed", used + 1);
  }

  // -----------------------------
  // RESET ALL USAGE (ON NEW PLAN)
  // -----------------------------
  static Future<void> resetUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("chatUsed", 0);
    await prefs.setInt("mistakeUsed", 0);
    await prefs.setInt("diffUsed", 0);
    await prefs.remove("paymentSource");
  }
}
