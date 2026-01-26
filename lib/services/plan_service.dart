import 'package:shared_preferences/shared_preferences.dart';

class PlanService {
  // -----------------------------
  // BASIC PLAN CHECK
  // -----------------------------
  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    // Do NOT trust local flag alone; backend sync must set this
    return prefs.getBool("isPremium") == true;
  }

  // -----------------------------
  // PAYMENT SOURCE (PAYPAL / PLAY)
  // -----------------------------
  static Future<void> setPremium(bool value) async {
    // ⚠️ WARNING: This should ONLY be called after backend verification
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isPremium", value);
    if (!value) {
      await prefs.setInt("chatLimit", 0);
      await prefs.setInt("mistakeLimit", 0);
      await prefs.setInt("diffLimit", 0);
    }
  }

  // -----------------------------
  // APPLY REAL PLAN LIMITS (FROM BACKEND / PAYMENT)
  // -----------------------------
  static Future<void> applyPlanLimits({
    required int chatLimit,
    required int mistakeLimit,
    required int diffLimit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("chatLimit", chatLimit);
    await prefs.setInt("mistakeLimit", mistakeLimit);
    await prefs.setInt("diffLimit", diffLimit);
    await prefs.setInt("chatUsed", 0);
    await prefs.setInt("mistakeUsed", 0);
    await prefs.setInt("diffUsed", 0);
    await prefs.setBool("isPremium", true);
  }

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
    final isPremium = prefs.getBool("isPremium") ?? false;
    if (!isPremium) return false;

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
    final isPremium = prefs.getBool("isPremium") ?? false;
    if (!isPremium) return false;

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
    final isPremium = prefs.getBool("isPremium") ?? false;
    if (!isPremium) return false;

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
  }

  // -----------------------------
  // SYNC PLAN FROM BACKEND (SOURCE OF TRUTH)
  // -----------------------------
  static Future<void> syncFromBackend({
    required bool isPremium,
    required int chatLimit,
    required int mistakeLimit,
    required int diffLimit,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (!isPremium) {
      await prefs.setBool("isPremium", false);
      await prefs.setInt("chatLimit", 0);
      await prefs.setInt("mistakeLimit", 0);
      await prefs.setInt("diffLimit", 0);
      await resetUsage();
      return;
    }

    await prefs.setBool("isPremium", true);
    await prefs.setInt("chatLimit", chatLimit);
    await prefs.setInt("mistakeLimit", mistakeLimit);
    await prefs.setInt("diffLimit", diffLimit);

    // Reset usage ONLY when plan actually changes
    await prefs.setInt("chatUsed", 0);
    await prefs.setInt("mistakeUsed", 0);
    await prefs.setInt("diffUsed", 0);
  }
}
