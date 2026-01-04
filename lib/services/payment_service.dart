import 'package:razorpay_flutter/razorpay_flutter.dart';

class PaymentService {
  final Razorpay _razorpay = Razorpay();

  void init({
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onError,
    required Function(ExternalWalletResponse) onExternalWallet,
  }) {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);
  }

  void startPayment({
    required String orderId,
    required int amount,
    required String email,
  }) {
    final options = {
      'key': 'rzp_live_xxxxxxxx', // ONLY Razorpay key_id
      'amount': amount,
      'currency': 'INR',
      'order_id': orderId,
      'name': 'CrickNova AI',
      'description': 'Premium Subscription',
      'prefill': {
        'email': email,
      },
      'theme': {
        'color': '#0A1AFF',
      }
    };

    _razorpay.open(options);
  }

  void dispose() {
    _razorpay.clear();
  }
}