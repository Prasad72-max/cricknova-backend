import 'dart:convert';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RazorpayService {
  late Razorpay _razorpay;

  void init({
    required Function(Map<String, dynamic>) onSuccess,
    required Function(Map<String, dynamic>) onError,
  }) {
    _razorpay = Razorpay();

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse response) async {
      try {
        final user = FirebaseAuth.instance.currentUser;
        final token = await user?.getIdToken();

        final verifyRes = await http.post(
          Uri.parse("https://cricknova-backend.onrender.com/payment/verify-payment"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          },
          body: jsonEncode({
            "razorpay_order_id": response.orderId,
            "razorpay_payment_id": response.paymentId,
            "razorpay_signature": response.signature,
            "plan": "monthly"
          }),
        );

        final data = jsonDecode(verifyRes.body);

        if (verifyRes.statusCode == 200 && data["status"] == "success") {
          onSuccess({
            "paymentId": response.paymentId,
            "orderId": response.orderId,
            "signature": response.signature,
          });
        } else {
          onError({
            "code": "VERIFY_FAILED",
            "message": "Payment verification failed on backend",
          });
        }
      } catch (e) {
        onError({
          "code": "VERIFY_EXCEPTION",
          "message": e.toString(),
        });
      }
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
    // 1️⃣ Fetch Razorpay key from backend (LIVE / TEST handled by backend)
    final keyRes = await http.get(
      Uri.parse("https://cricknova-backend.onrender.com/payment/config"),
    );

    if (keyRes.statusCode != 200) {
      throw Exception("Failed to fetch Razorpay key");
    }

    final keyData = jsonDecode(keyRes.body);
    final razorpayKey = keyData["key_id"];

    if (razorpayKey == null) {
      throw Exception("Razorpay key missing from backend");
    }

    // 2️⃣ Create order on backend
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    final res = await http.post(
      Uri.parse("https://cricknova-backend.onrender.com/payment/create-order"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "amount": amountInPaise ~/ 100,
        "plan": "monthly"
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("Order creation failed: ${res.body}");
    }

    final data = jsonDecode(res.body);

    // 3️⃣ Open Razorpay Checkout
    final options = {
      "key": razorpayKey,
      "amount": data["amount"], // MUST be in paise (backend returns paise)
      "currency": data["currency"],
      "name": "CrickNova",
      "description": "Subscription Payment",
      "order_id": data["orderId"],
      "prefill": {
        "email": email,
        "contact": phone,
      },
      "theme": {
        "color": "#000000",
      },
    };

    if (kDebugMode) {
      debugPrint("RAZORPAY OPTIONS => $options");
    }

    _razorpay.open(options);
  }

  void dispose() {
    _razorpay.clear();
  }
}