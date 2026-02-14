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
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw StateError("User not logged in");
        }
        final idToken = await user.getIdToken(true);
        if (idToken == null) {
          throw StateError("Failed to obtain Firebase ID token");
        }
        final verifyRes = await http.post(
          Uri.parse("$backendBaseUrl/payment/verify-payment"),
          headers: {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": "Bearer $idToken",
          },
          body: jsonEncode({
            "razorpay_order_id": response.orderId,
            "razorpay_payment_id": response.paymentId,
            "razorpay_signature": response.signature,
            "plan": "IN_99",
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
      final idToken = await user.getIdToken(true);
      if (idToken == null) {
        throw StateError("Failed to obtain Firebase ID token");
      }
      final res = await http.post(
        Uri.parse("$backendBaseUrl/paypal/create-order"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $idToken",
        },
        body: jsonEncode({
          "amount": amountUsd,
          "currency": "USD",
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

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        // Fallback: try opening inside in-app browser
        final fallbackLaunched = await launchUrl(
          uri,
          mode: LaunchMode.inAppBrowserView,
        );

        if (!fallbackLaunched) {
          throw StateError("Unable to open PayPal checkout page");
        }
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

    final idToken = await user.getIdToken(true);
    if (idToken == null) {
      throw StateError("Failed to obtain Firebase ID token");
    }
    final res = await http.post(
      Uri.parse("$backendBaseUrl/paypal/capture-order"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $idToken",
      },
      body: jsonEncode({
        "order_id": _pendingPayPalOrderId,
        "plan": plan,
        "user_id": user.uid,
      }),
    );

    final data = jsonDecode(res.body);

    if (data["premium"] == true) {
      await PremiumService.syncFromBackend(
        FirebaseAuth.instance.currentUser!.uid,
      );
      await PremiumService.refresh();
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}