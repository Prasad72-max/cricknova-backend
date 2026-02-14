import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:developer';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/premium_service.dart';

Future<void> showRestartRequiredDialog(BuildContext context) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.85),
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Scaffold(
        backgroundColor: const Color(0xFF020A1F),
        body: SafeArea(
          child: Column(
            children: [
              // 🔥 TOP NOTCH STYLE GLOW HEADER
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF38BDF8), Color(0xFF7C3AED)],
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(36),
                  ),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.workspace_premium,
                        size: 60, color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      "PREMIUM UNLOCKED",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 50),

              const Text(
                "You’re Now Elite 👑",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  "Your payment was successful.\n\nRestart the app once to activate all Premium features.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ),

              const Spacer(),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: GestureDetector(
                  onTap: () {
                    Future.delayed(const Duration(milliseconds: 200), () {
                      exit(0);
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF38BDF8), Color(0xFF7C3AED)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFF38BDF8),
                          blurRadius: 20,
                        )
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        "Restart & Enter Premium",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          ),
          child: child,
        ),
      );
    },
  );
}

class PremiumScreen extends StatefulWidget {
  final String? entrySource;

  const PremiumScreen({
    super.key,
    this.entrySource,
  });

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class PayPalWebViewScreen extends StatelessWidget {
  final String approvalUrl;
  final String orderId;
  final String planId;

  const PayPalWebViewScreen({
    super.key,
    required this.approvalUrl,
    required this.orderId,
    required this.planId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PayPal Checkout"),
      ),
      body: WebViewWidget(
        controller: WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (nav) async {
                if (nav.url.contains("paypal-success")) {
                  await _capture(context);
                  return NavigationDecision.prevent;
                }
                if (nav.url.contains("paypal-cancel")) {
                  Navigator.pop(context);
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
            ),
          )
          ..loadRequest(Uri.parse(approvalUrl)),
      ),
    );
  }

  Future<void> _capture(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String? idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) return;

    final res = await http.post(
      Uri.parse("https://cricknova-backend.onrender.com/paypal/capture"),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode({
        "order_id": orderId,
        "plan": planId,
      }),
    );

    final data = jsonDecode(res.body);

    if (res.statusCode == 200 && data["status"] == "success") {
      await PremiumService.syncFromBackend(user.uid);
      await PremiumService.refresh();
      PremiumService.premiumNotifier.notifyListeners();
      if (!context.mounted) return;
      Navigator.pop(context, true);
      await showRestartRequiredDialog(context);
    }
  }
}

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  bool isIndia = true;
  static const bool isPayPalSandbox = true; // set false when going live
  // 🔐 TEMP: Simulated user subscription state (replace with backend later)

  late Razorpay _razorpay;
  String? _razorpayKey;
  bool _isPaying = false;
  String? _payingPlan;

  // Track selected plan
  String? _lastPlanTitle;
  String? _lastPlanPrice;

  String? _animatingPlan;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    debugPrint("Razorpay initialized");

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
    if (planCode == null) {
      throw Exception("Invalid plan selected");
    }

    final user = FirebaseAuth.instance.currentUser!;
    final String? idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw Exception("Firebase ID token missing");
    }

    // Show SnackBar indicating premium activation and restart required
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          backgroundColor: Colors.black,
          content: Text(
            "Premium Activated 🎉\n"
            "Your payment was successful.\n"
            "Please restart the app once to unlock all premium features.",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final verifyRes = await http.post(
      Uri.parse("https://cricknova-backend.onrender.com/payment/verify-payment"),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode({
        "razorpay_order_id": response.orderId,
        "razorpay_payment_id": response.paymentId,
        "razorpay_signature": response.signature,
        "plan": planCode,
      }),
    );

    final data = jsonDecode(verifyRes.body);

    if (verifyRes.statusCode == 200 && data["success"] == true) {
      await PremiumService.syncFromBackend(user.uid);
      await PremiumService.refresh();
      PremiumService.premiumNotifier.notifyListeners();
      if (!mounted) return;
      setState(() {});
      Navigator.pop(context, true);
      await showRestartRequiredDialog(context);
    } else {
      _isPaying = false;
      throw Exception("Payment verification failed");
    }
  } catch (e) {
    debugPrint("❌ Payment verify exception: $e");
  }
  _isPaying = false;
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
    _isPaying = false;
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

    try {
      if (_razorpayKey == null) {
        final keyRes = await http.get(
          Uri.parse("https://cricknova-backend.onrender.com/payment/config"),
        ).timeout(const Duration(seconds: 15));

        if (keyRes.statusCode != 200) {
          throw Exception("Failed to load Razorpay key");
        }

        final keyData = jsonDecode(keyRes.body);
        _razorpayKey = keyData['key_id'];

        if (_razorpayKey == null || _razorpayKey!.isEmpty) {
          throw Exception("Razorpay key missing from backend");
        }
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
          'email': FirebaseAuth.instance.currentUser?.email ?? 'demo@cricknova.ai',
        },
        'method': {
          'upi': true,
          'card': true,
          'netbanking': true,
          'wallet': true,
        },
        'modal': {
          'confirm_close': true,
        },
        'theme': {
          'color': '#00A8FF',
        },
        'retry': {
          'enabled': true,
          'max_count': 1,
        },
      };

      _isPaying = true;
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
      // Do not reset _isPaying here; let handlers do it
    }
  }


  Future<void> _startPayPalCheckout(String planId) async {
    if (_isPaying) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login first")),
      );
      return;
    }

    try {
      setState(() {
        _isPaying = true;
        _payingPlan = planId;
      });

      // Compute amount and planCode
      double amount;
      String planCode;

      switch (planId) {
        case "\$29.99":
          amount = 29.99;
          planCode = "INTL_MONTHLY";
          break;
        case "\$49.99":
          amount = 49.99;
          planCode = "INTL_6M";
          break;
        case "\$69.99":
          amount = 69.99;
          planCode = "INTL_YEARLY";
          break;
        case "\$159.99":
          amount = 159.99;
          planCode = "INTL_ULTRA";
          break;
        default:
          throw Exception("Invalid PayPal plan");
      }

      // 1️⃣ Create PayPal order (backend) via POST
      final String? idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        throw Exception("Firebase ID token missing");
      }

      final createRes = await http.post(
        Uri.parse("https://cricknova-backend.onrender.com/paypal/create-order"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "authorization": "Bearer $idToken",
        },
        body: jsonEncode({
          "amount_usd": amount,
          "plan": planCode,
          "user_id": user.uid,
        }),
      );

      if (createRes.statusCode != 200 && createRes.statusCode != 201) {
        throw Exception("PayPal order creation failed");
      }

      final createData = jsonDecode(createRes.body);

      debugPrint("🧾 PAYPAL CREATE RESPONSE = $createData");

      final String orderId = createData["order_id"];

      final String? approvalUrl =
          createData["approval_url"] ?? createData["approvalUrl"];

      if (approvalUrl == null || approvalUrl.isEmpty) {
        debugPrint("❌ PayPal response invalid: $createData");
        throw Exception("PayPal approval URL missing");
      }

      debugPrint("🔥 PAYPAL APPROVAL URL = $approvalUrl");

      if (!mounted) return;

      setState(() {
        _isPaying = false;
        _payingPlan = null;
      });

      final Uri uri = Uri.parse(approvalUrl);

      bool launched = false;

      try {
        // Open using default handler (system decides best option)
        launched = await launchUrl(uri);
      } catch (e) {
        debugPrint("❌ Launch exception: $e");
      }

      if (!launched) {
        debugPrint("⚠️ Falling back to internal WebView");

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PayPalWebViewScreen(
              approvalUrl: approvalUrl,
              orderId: orderId,
              planId: planCode,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Unable to open PayPal. Please try again."),
            backgroundColor: Colors.redAccent,
          ),
        );
        if (mounted) {
          setState(() {
            _isPaying = false;
            _payingPlan = null;
          });
        }
      }
    }
  }

  Future<void> _confirmPayPalPayment({
    required String orderId,
    required String planId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final String? idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        throw Exception("Firebase ID token missing");
      }

      final res = await http.post(
        Uri.parse("https://cricknova-backend.onrender.com/paypal/capture"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "authorization": "Bearer $idToken",
        },
        body: jsonEncode({
          "order_id": orderId,
          "plan": planId,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data["status"] == "success") {
        await PremiumService.syncFromBackend(user.uid);
        if (!mounted) return;
        setState(() {});
        Navigator.pop(context, true);
        await showRestartRequiredDialog(context);
      } else {
        throw Exception("Capture failed");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Payment not completed on PayPal. If you haven't paid yet, please finish payment first.",
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
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
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final String? sourceFromArgs = args?['source'] as String?;
    // ✅ Guard: auto-close ONLY if user opened paywall as a forced paywall,
    // and NOT when user explicitly opens from Profile or Features tab.
    if (PremiumService.isPremiumActive &&
        widget.entrySource == null &&
        sourceFromArgs != "profile" &&
        sourceFromArgs != "features") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFF020A1F),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Upgrade to Premium",
          style: TextStyle(
            color: Color(0xFF38BDF8),
            fontWeight: FontWeight.bold,
            fontSize: 22,
            shadows: [
              Shadow(
                color: Color(0xFF38BDF8),
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
                color: const Color(0xFF0F172A),
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
            if (isIndia)
              ...((sourceFromArgs ?? widget.entrySource) == "analyse"
                  ? indiaCompareOnlyPlans()
                  : indiaPlans()),

            // INTERNATIONAL PLANS
            if (!isIndia)
              ...((sourceFromArgs ?? widget.entrySource) == "analyse"
                  ? internationalCompareOnlyPlans()
                  : internationalPlans()),
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
          color: selected ? const Color(0xFF38BDF8) : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: selected
              ? [const BoxShadow(color: Color(0xFF38BDF8), blurRadius: 12)]
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
        tag: "Starter ⚡",
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
        tag: "Most Popular 🔥",
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
        tag: "Best Value 💎",
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
        tag: "Elite Access 👑",
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

  List<Widget> indiaCompareOnlyPlans() {
    return [
      sexyPlanCard(
        title: "Yearly",
        price: "₹499",
        tag: "Analyse Pro 🎯",
        glowColor: Colors.greenAccent,
        features: [
          "Analyse Yourself",
          "50 Video Compare",
          "3,000 AI Chats",
          "60 Mistake Detections",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA PRO",
        price: "₹1999",
        tag: "Unlimited Analysis 🚀",
        glowColor: Colors.redAccent,
        features: [
          "Unlimited Analyse",
          "200 Video Compare",
          "20,000 AI Chats",
          "200 Mistake Detections",
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
        tag: "Starter Pass ⚡",
        glowColor: Colors.blueAccent,
        features: [
          "200 AI Chats",
          "20 Mistake Detections",
          "Basic Speed • Swing • Spin",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "6 Months",
        price: "\$49.99",
        tag: "Most Popular 🔥",
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
        price: "\$69.99",
        tag: "Best Deal 💰",
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
        price: "\$159.99",
        tag: "Elite International 🌍",
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

  List<Widget> internationalCompareOnlyPlans() {
    return [
      sexyPlanCard(
        title: "6 Months",
        price: "\$49.99",
        tag: "Analyse Pro 🎯",
        glowColor: Colors.purpleAccent,
        features: [
          "Analyse Yourself",
          "5 Video Compare",
          "1,200 AI Chats",
          "30 Mistake Detections",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly",
        price: "\$69.99",
        tag: "Best Value 💎",
        glowColor: Colors.greenAccent,
        features: [
          "Analyse Yourself",
          "10 Video Compare",
          "1,800 AI Chats",
          "50 Mistake Detections",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA INTERNATIONAL",
        price: "\$159.99",
        tag: "Unlimited Analysis 🚀",
        glowColor: Colors.redAccent,
        features: [
          "Unlimited Analyse",
          "150 Video Compare",
          "20,000 AI Chats",
          "200 Mistake Detections",
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
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
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),

          const SizedBox(height: 16),

          GestureDetector(
            onTap: () async {
              if (_isPaying) return;

              HapticFeedback.mediumImpact();

              setState(() {
                _animatingPlan = price;
              });

              await Future.delayed(const Duration(milliseconds: 180));

              _lastPlanTitle = title;
              _lastPlanPrice = price;

              if (!mounted) return;

              final numeric =
                  double.parse(price.replaceAll(RegExp(r'[^0-9.]'), ''));

              // SHOW payment option selector dialog
              await _showPaymentOptionDialog(
                price: price,
                onCrickNova: () {
                  if (isIndia) {
                    debugPrint("🟢 CrickNova payment for ₹${numeric.toInt()}");
                    _startRazorpayCheckout(numeric.toInt());
                  } else {
                    debugPrint("🌍 CrickNova PayPal payment for $price");
                    _startPayPalCheckout(price);
                  }
                },
                onGooglePlay: () async {
                  if (isIndia) {
                    // Google Play Billing not yet integrated for India
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Google Play payment coming soon"),
                      ),
                    );
                  } else {
                    // 🌍 International users: fallback to CrickNova (PayPal)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Redirecting via secure checkout"),
                      ),
                    );
                    _startPayPalCheckout(price);
                  }
                },
              );

              setState(() {
                _animatingPlan = null;
              });
            },
            child: AnimatedScale(
              scale: _animatingPlan == price ? 0.94 : 1.0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _animatingPlan == price ? 0.85 : 1.0,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      glowColor,
                      glowColor.withOpacity(0.8),
                    ]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(0.6),
                        blurRadius: 18,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                  child: Center(
                    child: (_payingPlan == price)
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
            ),
          ),
        ],
      ),
    );
  }

  // --- Payment Option Selector Dialog ---
  Future<void> _showPaymentOptionDialog({
    required String price,
    required VoidCallback onCrickNova,
    required VoidCallback onGooglePlay,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const Text(
                "Choose how to check out",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choose who will manage all aspects of your purchase.",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),

              // 🟢 CrickNova Option (Recommended)
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onCrickNova();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF020A1F),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.greenAccent, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent.withOpacity(0.25),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sports_cricket,
                          color: Colors.greenAccent, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  "CrickNova",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    "Recommended",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "AI Cricket Intelligence",
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          color: Colors.white38, size: 16),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // 🔵 Google Play Option (Trusted)
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onGooglePlay();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF020A1F),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_fill,
                          color: Colors.blueAccent, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Google Play",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Fast • Secure • Trusted",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          color: Colors.white38, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
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