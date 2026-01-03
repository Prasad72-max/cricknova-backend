import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  bool isIndia = true;
  // 🔐 TEMP: Simulated user subscription state (replace with backend later)
  bool isPremium = false;
  int usedVideoCompare = 0;
  int videoCompareLimit = 0;

  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();

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

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final verifyRes = await http.post(
        Uri.parse("http://192.168.1.17:8000/payment/verify-payment"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "razorpay_order_id": response.orderId,
          "razorpay_payment_id": response.paymentId,
          "razorpay_signature": response.signature,
          "user_id": "demo@cricknova.ai",
          "plan": "YEARLY_599"
        }),
      );

      final data = jsonDecode(verifyRes.body);

      if (verifyRes.statusCode == 200 && data["status"] == "success") {
        setState(() {
          isPremium = true;
          videoCompareLimit = 15;
          usedVideoCompare = 0;
        });

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
      const SnackBar(
        content: Text("Payment failed or cancelled"),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Opening ${response.walletName}…"),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  void _startRazorpayCheckout(int amountRupees) async {
    final res = await http.post(
      Uri.parse("http://192.168.1.17:8000/payment/create-order"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"amount": amountRupees}),
    );

    if (res.statusCode != 200) {
      throw Exception("Order creation failed");
    }

    final data = jsonDecode(res.body);

    final options = {
      'key': 'rzp_live_RyxXeylgDimsty',
      'order_id': data['orderId'],
      'amount': data['amount'], // paise
      'currency': 'INR',
      'name': 'CrickNova AI',
      'description': 'Premium Subscription',
      'prefill': {
        'email': 'demo@cricknova.ai',
      },
      'retry': {
        'enabled': true,
        'max_count': 1,
      },
      'theme': {
        'color': '#00A8FF',
      },
      // Removed 'external' block so Razorpay decides payment methods automatically.
    };

    debugPrint("🚀 Razorpay options: $options");
    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint("❌ Razorpay open failed: $e");
    }
  }

  bool canUseFeature({required int used, required int limit}) {
    if (!isPremium) return false;
    if (used >= limit) return false;
    return true;
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
          "2 AI Mistake Analyses / month",
          "10 AI Coach Chats / month",
          "Speed • Swing • Spin (limited)",
          "Basic Swing Path",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "6 Months",
        price: "₹299",
        tag: null,
        glowColor: Colors.purpleAccent,
        features: [
          "15 AI Mistake Analyses / 6 months",
          "80 AI Coach Chats / 6 months",
          "Advanced Speed Tracking",
          "Shot Map Lite",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly",
        price: "₹499",
        tag: null,
        glowColor: Colors.greenAccent,
        features: [
          "25 AI Mistake Analyses / year",
          "140 AI Coach Chats / year",
          "Shot Heatmap",
          "Game Simulation AI",
          "Bowling Accuracy Tracking",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly Elite",
        price: "₹599",
        tag: "Elite 💎",
        glowColor: Colors.amberAccent,
        features: [
          "10 AI Mistake Analyses / month",
          "200 AI Coach Chats / month",
          "15 Video Compare (Analyse Yourself)",
          "Early Access to New AI",
          "Unlimited Cloud Storage",
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
        tag: null,
        glowColor: Colors.blueAccent,
        features: [
          "2 AI Mistake Analyses / month",
          "10 AI Coach Chats / month",
          "Speed • Swing • Spin (limited)",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "6 Months",
        price: "\$39.99",
        tag: null,
        glowColor: Colors.purpleAccent,
        features: [
          "15 AI Mistake Analyses / 6 months",
          "80 AI Coach Chats / 6 months",
          "Advanced Speed Tracking",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly",
        price: "\$59.99",
        tag: "Best Value 🔥",
        glowColor: Colors.greenAccent,
        features: [
          "25 AI Mistake Analyses / year",
          "140 AI Coach Chats / year",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly Elite",
        price: "\$89.99",
        tag: "Elite 🍿",
        glowColor: Colors.amberAccent,
        features: [
          "10 AI Mistake Analyses / month",
          "200 AI Coach Chats / month",
          "15 Video Compare (Analyse Yourself)",
          "Early Access to New AI",
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
            onTap: () {
              // Direct, non-scripted Razorpay flow
              // Razorpay will automatically show UPI, cards, netbanking, wallets
              final numeric = double.parse(price.replaceAll(RegExp(r'[^0-9.]'), ''));
              _startRazorpayCheckout(numeric.toInt());
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
              child: const Center(
                child: Text("Buy Now",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
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
