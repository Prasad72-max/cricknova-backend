import 'package:flutter/material.dart';
import 'dart:developer';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  bool isIndia = true;
  // 🔐 TEMP: Simulated user subscription state (replace with backend later)

  late Razorpay _razorpay;
  String? _razorpayKey;
  bool _isPaying = false;

  // Track selected plan
  String? _lastPlanTitle;
  String? _lastPlanPrice;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    debugPrint("Razorpay initialized");
    _prefetchRazorpayKey();

    _razorpay.on(
      Razorpay.EVENT_PAYMENT_SUCCESS,
      _handlePaymentSuccess,
    );

    _razorpay.on(
      Razorpay.EVENT_PAYMENT_ERROR,
      _handlePaymentError,
    );

    _razorpay.on(
      Razorpay.EVENT_EXTERNAL_WALLET,
      _handleExternalWallet,
    );
  }

  Future<void> _prefetchRazorpayKey() async {
    try {
      final res = await http.get(
        Uri.parse("https://cricknova-backend.onrender.com/payment/config"),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _razorpayKey = data['key_id'];
        debugPrint("⚡ Razorpay key prefetched");
      }
    } catch (e) {
      debugPrint("⚠️ Razorpay key prefetch failed");
    }
  }


  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final planCode = _lastPlanPrice == "₹99"
          ? "IN_99"
          : _lastPlanPrice == "₹299"
              ? "IN_299"
              : _lastPlanPrice == "₹499"
                  ? "IN_499"
                  : _lastPlanPrice == "₹1999"
                      ? "IN_1999"
                      : null;
      final verifyRes = await http
          .post(
            Uri.parse("https://cricknova-backend.onrender.com/payment/verify-payment"),
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({
              "razorpay_order_id": response.orderId,
              "razorpay_payment_id": response.paymentId,
              "razorpay_signature": response.signature,
              "user_id": FirebaseAuth.instance.currentUser?.uid,
              "plan": planCode
            }),
          )
          .timeout(const Duration(seconds: 60));

      final data = jsonDecode(verifyRes.body);
      debugPrint("✅ Payment verify response: $data");

      if (verifyRes.statusCode == 200 && data["status"] == "success") {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Payment verified • Premium activated"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception("Verification failed");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Payment verification failed"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Payment failed: ${response.code} | ${response.message}",
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
    debugPrint("❌ Razorpay error => code=${response.code}, message=${response.message}");
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Opening ${response.walletName}…"),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _startRazorpayCheckout(int amountRupees) async {
    if (_isPaying) return;
    _isPaying = true;

    try {
      if (_razorpayKey == null) {
        await _prefetchRazorpayKey();
      }

      if (_razorpayKey == null) {
        throw Exception("Razorpay key not available");
      }

      final res = await http.post(
        Uri.parse("https://cricknova-backend.onrender.com/payment/create-order"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"amount": amountRupees}),
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception("Order creation failed");
      }

      final data = jsonDecode(res.body);

      final options = {
        'key': _razorpayKey,
        'order_id': data['orderId'],
        'amount': data['amount'],
        'currency': data['currency'] ?? 'INR',
        'name': 'CrickNova AI',
        'description': 'Premium Subscription',
        'prefill': {
          'email': 'demo@cricknova.ai',
        },
        'theme': {
          'color': '#00A8FF',
        },
      };

      _razorpay.open(options);
    } catch (e, st) {
      log("❌ Payment start failed", error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Unable to start payment"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      _isPaying = false;
    }
  }


  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060606),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Upgrade to Premium",
          style: TextStyle(
            color: Color(0xFF00A8FF),
            fontWeight: FontWeight.bold,
            fontSize: 22,
            shadows: [
              Shadow(
                color: Color(0xFF00A8FF),
                blurRadius: 20,
              ),
            ],
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [

            // 🌍 COUNTRY SELECTOR (Neon Tabs)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: neonTab(
                      text: "India",
                      selected: isIndia,
                      onTap: () => setState(() => isIndia = true),
                    ),
                  ),
                  Expanded(
                    child: neonTab(
                      text: "International",
                      selected: !isIndia,
                      onTap: () => setState(() => isIndia = false),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // INDIA PLANS
            if (isIndia) ...indiaPlans(),

            // INTERNATIONAL PLANS
            if (!isIndia) ...internationalPlans(),
          ],
        ),
      ),
    );
  }

  // 🌈 Neon Tab Button
  Widget neonTab({required String text, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: selected
              ? [const BoxShadow(color: Colors.blueAccent, blurRadius: 12)]
              : [],
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }


  // ---------------- INDIA PLANS ----------------
  List<Widget> indiaPlans() {
    return [
      sexyPlanCard(
        title: "Monthly",
        price: "₹99",
        tag: "Starter",
        glowColor: Colors.blueAccent,
        features: [
          "200 AI Chats",
          "15 Mistake Detections",
          "Speed • Swing • Spin (Basic)",
          "Basic Swing Path",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "6 Months",
        price: "₹299",
        glowColor: Colors.purpleAccent,
        features: [
          "1,200 AI Chats",
          "30 Mistake Detections",
          "Advanced Speed Tracking",
          "Shot Map Lite",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly",
        price: "₹499",
        glowColor: Colors.greenAccent,
        features: [
          "3,000 AI Chats",
          "60 Mistake Detections",
          "50 Video Compare",
          "Shot Heatmap",
          "Game Simulation AI",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA PRO",
        price: "₹1999",
        tag: "Best Value 🏆",
        glowColor: Colors.redAccent,
        features: [
          "1 Year Access",
          "20,000 AI Chats",
          "200 Mistake Detections",
          "200 Video Compare",
          "All Premium Features",
          "Priority AI Processing",
        ],
      ),
    ];
  }

  // ---------------- INTERNATIONAL PLANS ----------------
  List<Widget> internationalPlans() {
    return [
      sexyPlanCard(
        title: "Monthly",
        price: "\$29.99",
        glowColor: Colors.blueAccent,
        features: [
          "300 AI Chats",
          "20 Mistake Detections",
          "Basic Speed • Swing • Spin",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "6 Months",
        price: "\$39.99",
        glowColor: Colors.purpleAccent,
        features: [
          "1,200 AI Chats",
          "30 Mistake Detections",
          "5 Video Compare",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly",
        price: "\$59.99",
        glowColor: Colors.greenAccent,
        features: [
          "1,800 AI Chats",
          "50 Mistake Detections",
          "10 Video Compare",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA INTERNATIONAL",
        price: "\$149.99",
        tag: "Unlimited Feel 🌍",
        glowColor: Colors.redAccent,
        features: [
          "1 Year Access",
          "20,000 AI Chats",
          "200 Mistake Detections",
          "150 Video Compare",
          "All Features Unlocked",
          "Priority AI",
        ],
      ),
    ];
  }

  // 🌟 SEXY PLAN CARD (Neon + Glass UI)
  Widget sexyPlanCard({
    required String title,
    required String price,
    required Color glowColor,
    required List<String> features,
    String? tag,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: glowColor.withOpacity(0.4), blurRadius: 24),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tag != null)
            Text(tag,
                style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          const SizedBox(height: 6),

          Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 24)),
          Text(price,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          const Text("Features Included:",
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 10),

          for (String f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text("• $f",
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
            ),

          const SizedBox(height: 16),

          GestureDetector(
            onTap: _isPaying
                ? null
                : () {
                    // Track selected plan before payment
                    _lastPlanTitle = title;
                    _lastPlanPrice = price;
                    if (!mounted) return;
                    final numeric = double.parse(price.replaceAll(RegExp(r'[^0-9.]'), ''));
                    if (isIndia) {
                      debugPrint("🟢 Starting Razorpay payment for ₹${numeric.toInt()}");
                      _startRazorpayCheckout(numeric.toInt()); // pass RUPEES only
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("International payments handled via PayPal / Payoneer"),
                          backgroundColor: Colors.blueAccent,
                        ),
                      );
                    }
                  },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  glowColor,
                  glowColor.withOpacity(0.6),
                ]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _isPaying
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Buy Now",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 👑 SEXY LIFETIME CARD
  Widget lifetimeCardSexy({
    required String price,
    required List<String> features,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFE6A800)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.amber, blurRadius: 30),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Lifetime VIP",
              style: TextStyle(color: Colors.black, fontSize: 26)),
          Text(price,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          const Text("Lifetime Features:",
              style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 10),

          for (String f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text("• $f",
                  style: const TextStyle(color: Colors.black87, fontSize: 15)),
            ),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text("Buy Lifetime",
                  style: TextStyle(
                      color: Colors.amber,
                      fontSize: 19,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
