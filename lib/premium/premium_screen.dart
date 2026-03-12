import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:confetti/confetti.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart';

import '../services/premium_service.dart';

Future<void> showPremiumSuccessScreen(
  BuildContext context, {
  required String userName,
}) async {
  await Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => PremiumSuccessScreen(userName: userName),
      transitionsBuilder: (_, animation, __, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(opacity: fade, child: child);
      },
    ),
  );
}

class PremiumSuccessScreen extends StatefulWidget {
  final String userName;

  const PremiumSuccessScreen({super.key, required this.userName});

  @override
  State<PremiumSuccessScreen> createState() => _PremiumSuccessScreenState();
}

class _PremiumSuccessScreenState extends State<PremiumSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final ConfettiController _confettiController;
  final AudioPlayer _gongPlayer = AudioPlayer();
  final AudioPlayer _sparklePlayer = AudioPlayer();
  bool _triggeredGong = false;
  bool _triggeredSparkle = false;
  bool _heartbeatStarted = false;
  Timer? _heartbeatTimer;
  int _heartbeatTick = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..addListener(_tick);
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 1800),
    );
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _confettiController.dispose();
    _gongPlayer.dispose();
    _sparklePlayer.dispose();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _tick() {
    final t = _controller.value;
    if (!_triggeredGong && t >= 0.02) {
      _triggeredGong = true;
      _playGong();
      _startHeartbeat();
    }
    if (!_triggeredSparkle && t >= 0.12) {
      _triggeredSparkle = true;
      _confettiController.play();
      _playSparkle();
    }
  }

  void _startHeartbeat() {
    if (_heartbeatStarted) return;
    _heartbeatStarted = true;
    _heartbeatTick = 0;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 260), (t) {
      _heartbeatTick += 1;
      if (_heartbeatTick >= 8) {
        t.cancel();
        return;
      }
      if (_heartbeatTick.isOdd) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
    });
  }

  Future<void> _playGong() async {
    try {
      await _gongPlayer.setReleaseMode(ReleaseMode.stop);
      await _gongPlayer.play(AssetSource("audio/premium_gong.wav"));
    } catch (_) {}
  }

  Future<void> _playSparkle() async {
    try {
      await _sparklePlayer.setReleaseMode(ReleaseMode.stop);
      await _sparklePlayer.play(AssetSource("audio/gold_sparkle.wav"));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final flareT = _segment(t, 0.00, 0.16);
          final cardT = _segment(t, 0.18, 0.62);
          final iconsT = _segment(t, 0.60, 0.92);
          final bgColor = Color.lerp(
            Colors.white,
            const Color(0xFF050B1E),
            flareT,
          )!;
          return Stack(
            children: [
              Positioned.fill(
                child: Container(color: _ready ? bgColor : Colors.black),
              ),
              Positioned.fill(
                child: CustomPaint(painter: _LensFlarePainter(flareT)),
              ),
              Align(
                alignment: Alignment.center,
                child: _PremiumCardFlip(
                  progress: cardT,
                  userName: widget.userName,
                ),
              ),
              Positioned.fill(child: _FeatureIconFlight(progress: iconsT)),
              Positioned(
                top: 96,
                right: 40,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0F172A),
                    border: Border.all(
                      color: const Color(0xFFFFD700),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.4),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.directional,
                  blastDirection: math.pi / 2,
                  emissionFrequency: 0.03,
                  numberOfParticles: 18,
                  minBlastForce: 2,
                  maxBlastForce: 6,
                  gravity: 0.12,
                  colors: const [Color(0xFFFFD700), Color(0xFFFFE8A3)],
                  createParticlePath: _stripParticlePath,
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 96,
                child: Column(
                  children: const [
                    Text(
                      "You are now in the top 1% of serious cricketers.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 34,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Share.share(
                            "I just unlocked CrickNova Elite Member status! 🏏✨",
                          );
                        },
                        icon: const Icon(Icons.share, color: Colors.white),
                        label: const Text(
                          "Share Success",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.white10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "ENTER THE ELITE ARENA",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _segment(double t, double start, double end) {
    if (t <= start) return 0.0;
    if (t >= end) return 1.0;
    return ((t - start) / (end - start)).clamp(0.0, 1.0);
  }

  Path _stripParticlePath(Size size) {
    final path = Path();
    path.addOval(Rect.fromCircle(center: Offset.zero, radius: 3.2));
    return path;
  }
}

class _LensFlarePainter extends CustomPainter {
  final double progress;

  _LensFlarePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height * 0.32);
    final radius = lerpDouble(40, size.width * 0.9, progress);
    final glowOpacity = (1 - progress).clamp(0.0, 1.0);
    final flarePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.9 * glowOpacity),
          Colors.white.withOpacity(0.4 * glowOpacity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, flarePaint);
    final streakPaint = Paint()
      ..color = Colors.white.withOpacity(0.45 * glowOpacity)
      ..strokeWidth = 2.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      streakPaint,
    );
  }

  double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(covariant _LensFlarePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _PremiumCardFlip extends StatelessWidget {
  final double progress;
  final String userName;

  const _PremiumCardFlip({required this.progress, required this.userName});

  @override
  Widget build(BuildContext context) {
    final rotation = (1 - progress) * math.pi;
    final eased = Curves.easeOut.transform(progress);
    final scale = 0.84 + (0.16 * eased);
    final isFront = rotation <= (math.pi / 2);
    return Transform.scale(
      scale: scale,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(rotation),
        child: Container(
          width: 290,
          height: 170,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF1B8), Color(0xFFB8860B), Color(0xFFFFE39A)],
            ),
            border: Border.all(color: const Color(0xFFFFD700), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.45),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: isFront
              ? const _PremiumCardFront()
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(math.pi),
                  child: _PremiumCardBack(userName: userName),
                ),
        ),
      ),
    );
  }
}

class _PremiumCardFront extends StatelessWidget {
  const _PremiumCardFront();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            "CRICKNOVA ELITE",
            style: TextStyle(
              color: const Color(0xFF2C1C00),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              shadows: [
                Shadow(
                  color: Colors.white.withOpacity(0.75),
                  offset: const Offset(-1, -1),
                  blurRadius: 2,
                ),
                const Shadow(
                  color: Color(0xFF8A6A00),
                  offset: Offset(1, 2),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 120,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF8A6A00).withOpacity(0.4),
            ),
          ),
          const Spacer(),
          const Text(
            "Elite Membership Card",
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumCardBack extends StatelessWidget {
  final String userName;

  const _PremiumCardBack({required this.userName});

  @override
  Widget build(BuildContext context) {
    final name = userName.isEmpty ? "Player" : userName;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ELITE MEMBER",
            style: TextStyle(
              color: Color(0xFF2C1C00),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const Spacer(),
          Text(
            name,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Member Since 2026",
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureIconFlight extends StatelessWidget {
  final double progress;

  const _FeatureIconFlight({required this.progress});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final target = Offset(size.width - 70, 140);
    final icons = [
      _IconFlightData(
        icon: Icons.all_inclusive,
        label: "Unlimited CrickNova Analysis",
        start: Offset(size.width * 0.2, size.height * 0.65),
      ),
      _IconFlightData(
        icon: Icons.track_changes,
        label: "Pro-Level Mistake Detection",
        start: Offset(size.width * 0.5, size.height * 0.7),
      ),
      _IconFlightData(
        icon: Icons.workspace_premium,
        label: "Priority Server Access",
        start: Offset(size.width * 0.8, size.height * 0.62),
      ),
    ];

    return Stack(
      children: icons.map((data) {
        final dx = lerpDouble(data.start.dx, target.dx, progress);
        final dy = lerpDouble(data.start.dy, target.dy, progress);
        final opacity = (progress * 1.2).clamp(0.0, 1.0);
        return Positioned(
          left: dx - 18,
          top: dy - 18,
          child: Opacity(
            opacity: opacity,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0F172A),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.6),
                        blurRadius: 18,
                      ),
                    ],
                    border: Border.all(color: const Color(0xFFFFD700)),
                  ),
                  child: Icon(data.icon, color: const Color(0xFFFFD700)),
                ),
                const SizedBox(height: 4),
                Text(
                  data.label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

class _IconFlightData {
  final IconData icon;
  final String label;
  final Offset start;

  _IconFlightData({
    required this.icon,
    required this.label,
    required this.start,
  });
}

class PremiumScreen extends StatefulWidget {
  final String? entrySource;

  const PremiumScreen({super.key, this.entrySource});

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
      appBar: AppBar(title: const Text("PayPal Checkout")),
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

    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) return;

    final res = await http.post(
      Uri.parse("https://cricknova-backend.onrender.com/paypal/capture"),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode({"order_id": orderId, "plan": planId}),
    );

    final data = jsonDecode(res.body);

    if (res.statusCode == 200 && data["status"] == "success") {
      await PremiumService.syncFromBackend(user.uid);
      await PremiumService.refresh();
      PremiumService.premiumNotifier.notifyListeners();
      if (!context.mounted) return;
      Navigator.pop(context, true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("premium_shimmer", true);
      await showPremiumSuccessScreen(
        context,
        userName: user.displayName ?? "Player",
      );
    }
  }
}

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  bool? isIndia; // null until IP detection completes
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
  bool _showPremiumShimmer = false;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    debugPrint("Razorpay initialized");

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);

    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);

    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    // 🌍 Detect IP on screen load
    _loadCachedPricingMode();
    _detectIPAndSetPricing();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _loadShimmerPreference();
  }

  Future<void> _loadCachedPricingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString("pricingMode");
    bool? cached;
    if (stored == "INR") {
      cached = true;
    } else if (stored == "USD") {
      cached = false;
    }
    cached ??= Platform.localeName.toUpperCase().contains("_IN");
    if (!mounted) return;
    setState(() => isIndia = cached);
  }

  Future<void> _loadShimmerPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool("premium_shimmer") ?? false;
    if (!mounted) return;
    setState(() => _showPremiumShimmer = enabled);
    if (enabled) {
      _shimmerController.repeat();
    }
  }

  Future<void> _enablePremiumShimmer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("premium_shimmer", true);
    if (!mounted) return;
    setState(() => _showPremiumShimmer = true);
    if (!_shimmerController.isAnimating) {
      _shimmerController.repeat();
    }
  }

  Future<void> _detectIPAndSetPricing() async {
    try {
      final res = await http
          .get(Uri.parse("https://ipapi.co/json/"))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final countryCode = data["country_code"];
        final ip = data["ip"];

        debugPrint("🌍 PREMIUM IP DATA => $data");

        final prefs = await SharedPreferences.getInstance();

        if (countryCode == "IN") {
          await prefs.setString("pricingMode", "INR");
          debugPrint("🇮🇳 PRICING MODE SET => INR");
        } else {
          await prefs.setString("pricingMode", "USD");
          debugPrint("🌎 PRICING MODE SET => USD");
        }

        if (!mounted) return;

        setState(() {
          isIndia = countryCode == "IN";
        });

        debugPrint("🧠 USER IP => $ip | COUNTRY => $countryCode");
      }
    } catch (e) {
      debugPrint("❌ PREMIUM IP detection failed: $e");
      if (isIndia == null) {
        await _loadCachedPricingMode();
      }
    }
  }

  Future<void> _prefetchRazorpayKey() async {
    try {
      final res = await http
          .get(
            Uri.parse("https://cricknova-backend.onrender.com/payment/config"),
          )
          .timeout(const Duration(seconds: 15));

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
      final String? idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw Exception("Firebase ID token missing");
      }

      // Show SnackBar indicating premium activation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            backgroundColor: Colors.black,
            content: Text(
              "Premium Activated 🎉\n"
              "Your payment was successful.\n"
              "Welcome to CrickNova Elite.",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        );
      }

      final verifyRes = await http.post(
        Uri.parse(
          "https://cricknova-backend.onrender.com/payment/verify-payment",
        ),
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
        await _enablePremiumShimmer();
        await showPremiumSuccessScreen(
          context,
          userName: user.displayName ?? "Player",
        );
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
        content: Text("Payment failed: ${response.code} | ${response.message}"),
        backgroundColor: Colors.redAccent,
      ),
    );
    debugPrint(
      "❌ Razorpay error => code=${response.code}, message=${response.message}",
    );
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
        final keyRes = await http
            .get(
              Uri.parse(
                "https://cricknova-backend.onrender.com/payment/config",
              ),
            )
            .timeout(const Duration(seconds: 15));

        if (keyRes.statusCode != 200) {
          throw Exception("Failed to load Razorpay key");
        }

        final keyData = jsonDecode(keyRes.body);
        _razorpayKey = keyData['key_id'];

        if (_razorpayKey == null || _razorpayKey!.isEmpty) {
          throw Exception("Razorpay key missing from backend");
        }
      }

      final res = await http
          .post(
            Uri.parse(
              "https://cricknova-backend.onrender.com/payment/create-order",
            ),
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({"amount": amountRupees}),
          )
          .timeout(const Duration(seconds: 20));

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
          'email':
              FirebaseAuth.instance.currentUser?.email ?? 'demo@cricknova.ai',
        },
        'method': {
          'upi': true,
          'card': true,
          'netbanking': true,
          'wallet': true,
        },
        'modal': {'confirm_close': true},
        'theme': {'color': '#00A8FF'},
        'retry': {'enabled': true, 'max_count': 1},
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please login first")));
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
      final String? idToken = await user.getIdToken();
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

      // Always open PayPal inside in-app WebView
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
      final String? idToken = await user.getIdToken();
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
        body: jsonEncode({"order_id": orderId, "plan": planId}),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data["status"] == "success") {
        await PremiumService.syncFromBackend(user.uid);
        if (!mounted) return;
        setState(() {});
        Navigator.pop(context, true);
        await _enablePremiumShimmer();
        await showPremiumSuccessScreen(
          context,
          userName: user.displayName ?? "Player",
        );
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
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final String? sourceFromArgs = args?['source'] as String?;
    if (!_showPremiumShimmer && PremiumService.isPremiumActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _enablePremiumShimmer();
      });
    }
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
    if (isIndia == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF020A1F),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
        ),
      );
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
            shadows: [Shadow(color: Color(0xFF38BDF8), blurRadius: 20)],
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // INDIA PLANS
            if (isIndia == true)
              ...((sourceFromArgs ?? widget.entrySource) == "analyse"
                  ? indiaCompareOnlyPlans()
                  : indiaPlans()),

            // INTERNATIONAL PLANS
            if (isIndia == false)
              ...((sourceFromArgs ?? widget.entrySource) == "analyse"
                  ? internationalCompareOnlyPlans()
                  : internationalPlans()),
          ],
        ),
      ),
    );
  }

  // 🌈 Neon Tab Button
  Widget neonTab({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF38BDF8)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF0B1220), Color(0xFF0F172A)],
                ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withOpacity(0.35),
                    blurRadius: 16,
                  ),
                ]
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
          "5,000 AI Chats",
          "150 Mistake Detections",
          "150 Video Compare",
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
          "150 Video Compare",
          "5,000 AI Chats",
          "150 Mistake Detections",
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
          "7,000 AI Chats",
          "150 Mistake Detections",
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
          "7,000 AI Chats",
          "150 Mistake Detections",
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 18, bottom: 22),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.35),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (price == "\$159.99")
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "Less than \$0.45 per day",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (price == "₹1999")
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "Less than ₹5 per day",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                "Features Included:",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              for (String f in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.contains("AI")
                            ? "💬"
                            : f.contains("Mistake")
                            ? "🎯"
                            : f.contains("Compare")
                            ? "🎥"
                            : "✅",
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          f,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
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

                  final numeric = double.parse(
                    price.replaceAll(RegExp(r'[^0-9.]'), ''),
                  );

                  // SHOW payment option selector dialog
                  await _showPaymentOptionDialog(
                    price: price,
                    onCrickNova: () {
                      if (isIndia == true) {
                        debugPrint(
                          "🟢 CrickNova payment for ₹${numeric.toInt()}",
                        );
                        _startRazorpayCheckout(numeric.toInt());
                      } else {
                        debugPrint("🌍 CrickNova PayPal payment for $price");
                        _startPayPalCheckout(price);
                      }
                    },
                    onGooglePlay: () async {
                      if (isIndia == true) {
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
                    child: _shimmerWrap(
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [glowColor, glowColor.withOpacity(0.8)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: glowColor.withOpacity(0.6),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: glowColor.withOpacity(0.25),
                              blurRadius: 35,
                              spreadRadius: 2,
                            ),
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
                                  "BUY NOW",
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
              ),
            ],
          ),
        ),
        if (tag != null)
          Positioned(
            top: 0,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: tag.contains("Elite")
                    ? const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFE6A800)],
                      )
                    : tag.contains("Best")
                    ? const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF334155)],
                      ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: glowColor.withOpacity(0.5), blurRadius: 18),
                ],
              ),
              child: Row(
                children: [
                  if (tag.contains("Elite"))
                    const Icon(
                      Icons.workspace_premium,
                      color: Color(0xFFFFD700),
                      size: 18,
                    ),
                  if (tag.contains("Elite")) const SizedBox(width: 6),
                  Text(
                    tag,
                    style: TextStyle(
                      color: tag.contains("Elite")
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _shimmerWrap(Widget child) {
    if (!_showPremiumShimmer) return child;
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        final t = _shimmerController.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final start = (t - 0.3).clamp(0.0, 1.0);
            final mid = t.clamp(0.0, 1.0);
            final end = (t + 0.3).clamp(0.0, 1.0);
            return LinearGradient(
              colors: const [
                Color(0x00FFFFFF),
                Color(0x66FFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: [start, mid, end],
            ).createShader(rect);
          },
          child: child,
        );
      },
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
                style: TextStyle(color: Colors.white54, fontSize: 14),
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
                      const Icon(
                        Icons.sports_cricket,
                        color: Colors.greenAccent,
                        size: 36,
                      ),
                      const SizedBox(width: 16),
                      Flexible(
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
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
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white38,
                        size: 16,
                      ),
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
                      const Icon(
                        Icons.play_circle_fill,
                        color: Colors.blueAccent,
                        size: 36,
                      ),
                      const SizedBox(width: 16),
                      Flexible(
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
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white38,
                        size: 16,
                      ),
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
        boxShadow: const [BoxShadow(color: Colors.amber, blurRadius: 30)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Lifetime VIP",
            style: TextStyle(color: Colors.black, fontSize: 26),
          ),
          Text(
            price,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          const Text(
            "Lifetime Features:",
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),

          for (String f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                "• $f",
                style: const TextStyle(color: Colors.black87, fontSize: 15),
              ),
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
              child: Text(
                "Buy Lifetime",
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
