import 'premium_service.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter/foundation.dart';

class RazorpayService {
  late Razorpay _razorpay;
  bool _checkoutInProgress = false;

  /// Initialize Razorpay and register callbacks
  void init({
    required void Function(PaymentSuccessResponse) onPaymentSuccess,
    required void Function(PaymentFailureResponse) onPaymentError,
    required void Function(ExternalWalletResponse) onExternalWallet,
  }) {
    _razorpay = Razorpay();

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
      _checkoutInProgress = false;
      debugPrint("✅ Razorpay payment success: ${response.paymentId}");
      debugPrint("🧾 orderId=${response.orderId}, signature=${response.signature}");
      onPaymentSuccess(response);
    });
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      _checkoutInProgress = false;
      debugPrint("❌ Razorpay payment error: code=${response.code}, message=${response.message}");
      onPaymentError(response);
    });
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);
  }

  /// Open Razorpay checkout (LIVE payment)
  /// [key] is the Razorpay API key (do not hardcode; pass from caller)
  void openCheckout({
    required String key,
    required String orderId,
    required int amount, // amount in paise
    required String email,
    String? contact, // ✅ OPTIONAL (global safe)
  }) {
    final Map<String, Object> options = {
      "key": key, // Pass the key dynamically
      "order_id": orderId,
      /// amount must already be in paise (backend-controlled)
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
    _checkoutInProgress = true;
    _razorpay.open(options);
  }

  /// Clear listeners
  void dispose() {
    _checkoutInProgress = false;
    _razorpay.clear();
  }
}