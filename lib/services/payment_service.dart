import 'package:razorpay_flutter/razorpay_flutter.dart';

class PaymentService {
  final Razorpay _razorpay = Razorpay();

  void startPayment({
    required String orderId,
    required int amount,
    required String email,
  }) {
    var options = {
      'key': 'rzp_live_xxxxxxxx', // ONLY KEY_ID
      'amount': amount,
      'order_id': orderId,
      'name': 'CrickNova AI',
      'description': 'Premium Subscription',
      'prefill': {
        'email': email,
      }
    };

    _razorpay.open(options);
  }
}