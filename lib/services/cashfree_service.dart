import 'dart:convert';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:http/http.dart' as http;

class RazorpayService {
  late Razorpay _razorpay;

  void init({
    required Function(Map<String, dynamic>) onSuccess,
    required Function(Map<String, dynamic>) onError,
  }) {
    _razorpay = Razorpay();

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse response) {
      onSuccess({
        "paymentId": response.paymentId,
        "orderId": response.orderId,
        "signature": response.signature,
      });
    });

    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,
        (PaymentFailureResponse response) {
      onError({
        "code": response.code,
        "message": response.message,
      });
    });
  }

  Future<void> startPayment({
    required int amountInPaise,
    required String name,
    required String email,
    required String phone,
  }) async {
    final res = await http.post(
      Uri.parse("https://cricknova-backend.onrender.com/payment/create-order"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "amount": amountInPaise,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("Order creation failed: ${res.body}");
    }

    final data = jsonDecode(res.body);

    final options = {
      "key": "rzp_live_xxxxxxxxxx", // Razorpay LIVE key_id only
      "amount": data["amount"],
      "currency": data["currency"],
      "name": "CrickNova",
      "description": "Subscription Payment",
      "order_id": data["orderId"],
      "prefill": {
        "email": email,
        "contact": phone,
      },
    };

    _razorpay.open(options);
  }

  void dispose() {
    _razorpay.clear();
  }
}