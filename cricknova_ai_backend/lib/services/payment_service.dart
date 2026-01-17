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

  Future<void> _activatePremiumOnServer({
    required PaymentSuccessResponse response,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User not logged in during payment success');
    }

    // 🔥 This is the REAL premium activation (source of truth)
    await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(user.uid)
        .set({
      'isPremium': true,
      'plan': 'IN_99', // replace dynamically if needed
      'paymentId': response.paymentId,
      'orderId': response.orderId,
      'signature': response.signature,
      'startDate': DateTime.now().toIso8601String(),
      'expiryDate': DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String(),
    }, SetOptions(merge: true));
  }

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
        // 1️⃣ Activate premium in Firestore (REAL source)
        await _activatePremiumOnServer(response: response);

        // 2️⃣ Sync premium into app memory
        await PremiumService.restoreOnLaunch();
      } catch (e) {
        // If this fails, user paid but premium didn't sync
        // It WILL recover on next app launch
      }

      onSuccess(response);
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
      await PremiumService.restoreOnLaunch();
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}