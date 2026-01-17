import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cricknova_fixed/services/premium_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PaymentService {
  static const String backendBaseUrl = "https://cricknova-backend.onrender.com";
  final Razorpay _razorpay = Razorpay();
  String? _keyId;
  String? _pendingPayPalOrderId;


  void init({
    required String keyId,
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onError,
    required Function(ExternalWalletResponse) onExternalWallet,
  }) {
    _keyId = keyId;
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse response) async {
      try {
        final verifyRes = await http.post(
          Uri.parse("$backendBaseUrl/payment/verify-payment"),
          headers: {
            "Content-Type": "application/json",
            "Accept": "application/json",
          },
          body: jsonEncode({
            "razorpay_order_id": response.orderId,
            "razorpay_payment_id": response.paymentId,
            "razorpay_signature": response.signature,
            "user_id": FirebaseAuth.instance.currentUser?.uid,
            "plan": "IN_1999",
          }),
        );

        final verifyData = jsonDecode(verifyRes.body);

        if (verifyRes.statusCode == 200 &&
            verifyData is Map &&
            verifyData["status"] == "success") {
          await PremiumService.syncFromBackend(
            FirebaseAuth.instance.currentUser!.uid,
          );
          onSuccess(response);
        } else {
          throw StateError(
              "Backend verification failed: ${verifyRes.body}");
        }
      } catch (e) {
        onError(
          PaymentFailureResponse(
            code: -1,
            message: "Payment verified by Razorpay but failed on server",
          ),
        );
      }
    });
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);
  }

  void startPayment({
    required String orderId,
    required int amount,
    required String email,
  }) {
    if (_keyId == null) {
      throw StateError('Razorpay keyId not initialized');
    }

    final options = {
      'key': _keyId, // injected at runtime
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

  Future<void> startPayPalPayment({
    required double amountUsd,
    required String plan,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError("User not logged in");
    }

    try {
      final res = await http.post(
        Uri.parse("$backendBaseUrl/paypal/create-order"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "amount_usd": amountUsd,
          "plan": plan,
          "user_id": user.uid,
        }),
      );

      if (res.statusCode != 200) {
        throw StateError("Failed to create PayPal order: ${res.body}");
      }

      final data = jsonDecode(res.body);
      _pendingPayPalOrderId = data["order_id"];
      final approvalUrl = data["approval_url"];

      if (approvalUrl == null || approvalUrl.toString().isEmpty) {
        throw StateError("PayPal approval URL missing");
      }

      final uri = Uri.parse(approvalUrl.toString());

      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        throw StateError("Cannot launch PayPal URL: $uri");
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw StateError("PayPal launchUrl returned false");
      }
    } catch (e) {
      // Let UI stop loader & show error
      rethrow;
    }
  }

  Future<void> confirmPayPalPayment({
    required String plan,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError("User not logged in");
    }

    if (_pendingPayPalOrderId == null) {
      throw StateError("No pending PayPal order to capture");
    }

    final res = await http.post(
      Uri.parse("$backendBaseUrl/paypal/capture"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "order_id": _pendingPayPalOrderId,
        "user_id": user.uid,
        "plan": plan,
      }),
    );

    final data = jsonDecode(res.body);

    if (data["premium"] == true) {
      await PremiumService.syncFromBackend(
        FirebaseAuth.instance.currentUser!.uid,
      );
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}