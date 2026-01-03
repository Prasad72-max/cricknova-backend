import 'dart:convert';
import 'package:flutter_cashfree_pg_sdk/flutter_cashfree_pg_sdk.dart';
import 'package:http/http.dart' as http;

class CashfreeService {
  static Future<bool> startPayment({
    required double amount,
    required String customerId,
    required String email,
    required String phone,
  }) async {
    // 1. Call backend
    final res = await http.post(
      Uri.parse("http://192.168.1.17:8000/payment/create-order"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "order_amount": amount,
        "order_currency": "INR",
        "customer_id": customerId,
        "customer_email": email,
        "customer_phone": phone,
      }),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception("Backend error: ${res.body}");
    }
    if (data["status"] != "success") return false;

    // 2. Launch Cashfree SDK
    final cfPayment = CFPaymentGatewayService();

    final session = CFSession(
      paymentSessionId: data["payment_session_id"],
      orderId: data["order_id"],
      environment: CFEnvironment.SANDBOX, // change to PRODUCTION later
    );

    final result = await cfPayment.doPayment(session);

    if (result == null) return false;

    final txStatus = result["txStatus"]?.toString().toUpperCase();
    return txStatus == "SUCCESS";
  }
}