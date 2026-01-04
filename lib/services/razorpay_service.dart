import 'premium_service.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter/foundation.dart';

class RazorpayService {
  late Razorpay _razorpay;

  /// Initialize Razorpay and register callbacks
  void init({
    required void Function(PaymentSuccessResponse) onPaymentSuccess,
    required void Function(PaymentFailureResponse) onPaymentError,
    required void Function(ExternalWalletResponse) onExternalWallet,
  }) {
    _razorpay = Razorpay();

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      debugPrint("✅ Razorpay payment success: ${response.paymentId}");

      // 🔥 Activate premium immediately
      await PremiumService.activatePremium();

      // Forward to original callback
      onPaymentSuccess(response);
    });
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);
  }

  /// Open Razorpay checkout (LIVE payment)
  void openCheckout({
    required String orderId,
    required int amount, // amount in paise
    required String email,
    String? contact, // ✅ OPTIONAL (global safe)
  }) {
    final Map<String, Object> options = {
      "key": "rzp_live_RyxXeylgDimsty", // LIVE KEY
      "order_id": orderId,
      "amount": amount,
      "currency": "INR",
      "name": "CrickNova AI",
      "description": "Premium Subscription",

      "prefill": {
        "email": email,
        if (contact != null) "contact": contact,
      },

      "retry": {
        "enabled": true,
        "max_count": 1,
      },

      "theme": {
        "color": "#00A8FF",
      },
    };

    debugPrint("🚀 Razorpay options → $options");
    _razorpay.open(options);
  }

  /// Clear listeners
  void dispose() {
    _razorpay.clear();
  }
}