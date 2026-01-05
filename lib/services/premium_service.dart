import 'package:shared_preferences/shared_preferences.dart';

class PremiumService {
  static const String _premiumKey = "is_premium";
  static const String _orderIdKey = "premium_order_id";
  static const String _paymentIdKey = "premium_payment_id";

  /// Activate premium ONLY after successful Razorpay payment
  static Future<void> activatePremium({
    required String orderId,
    required String paymentId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Safety check
    if (orderId.isEmpty || paymentId.isEmpty) {
      throw Exception("Invalid payment data");
    }

    await prefs.setBool(_premiumKey, true);
    await prefs.setString(_orderIdKey, orderId);
    await prefs.setString(_paymentIdKey, paymentId);
  }

  /// Check if user has premium
  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_premiumKey) ?? false;
  }

  /// Get last successful Razorpay order ID
  static Future<String?> getOrderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_orderIdKey);
  }

  /// Get last successful Razorpay payment ID
  static Future<String?> getPaymentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_paymentIdKey);
  }

  /// Remove premium (logout / reset / testing)
  static Future<void> clearPremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_premiumKey);
    await prefs.remove(_orderIdKey);
    await prefs.remove(_paymentIdKey);
  }
}