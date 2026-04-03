import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/premium_service.dart';
import '../services/pricing_location_service.dart';
import '../services/subscription_provider.dart';
import '../navigation/main_navigation.dart';

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
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  late final AnimationController _floatController;
  final List<_WelcomeFeature> _features = const [
    _WelcomeFeature(Icons.psychology_rounded, "AI-Powered Analysis"),
    _WelcomeFeature(Icons.gavel_rounded, "DRS Decision System"),
    _WelcomeFeature(Icons.graphic_eq_rounded, "UltraEdge Detection"),
    _WelcomeFeature(Icons.query_stats_rounded, "Speed & Accuracy Graphs"),
    _WelcomeFeature(Icons.emoji_events_rounded, "XP & Rewards System"),
  ];

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.userName.trim().isEmpty
        ? "Player"
        : widget.userName.trim();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _entryController,
          _pulseController,
          _floatController,
        ]),
        builder: (context, _) {
          final entry = Curves.easeOutCubic.transform(_entryController.value);
          final popupScale = 0.92 + (entry * 0.08);
          final popupOffset = 36 * (1 - entry);
          final pulse = 0.85 + (_pulseController.value * 0.25);
          final floatDy = math.sin(_floatController.value * math.pi * 2) * 5;
          final ctaScale = _entryController.value < 0.75
              ? 0.94
              : 0.94 +
                    (Curves.elasticOut.transform(
                          ((_entryController.value - 0.75) / 0.25).clamp(
                            0.0,
                            1.0,
                          ),
                        ) *
                        0.06);
          return Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 10 * entry,
                    sigmaY: 10 * entry,
                  ),
                  child: Container(
                    color: const Color(0xFF0B0E11).withValues(alpha: 0.88),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _WelcomeParticlesPainter(
                      drift: _floatController.value,
                      opacity: 0.55 * entry,
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: entry,
                  child: Transform.translate(
                    offset: Offset(0, popupOffset),
                    child: Transform.scale(
                      scale: popupScale,
                      child: Transform.translate(
                        offset: Offset(0, floatDy),
                        child: Container(
                          width: math.min(
                            MediaQuery.of(context).size.width - 34,
                            430,
                          ),
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF10161F).withValues(alpha: 0.98),
                                const Color(0xFF0C1118).withValues(alpha: 0.96),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFF1E90FF,
                              ).withValues(alpha: 0.34),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF1E90FF,
                                ).withValues(alpha: 0.14),
                                blurRadius: 36,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.42),
                                blurRadius: 36,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        center: const Alignment(0, -0.8),
                                        radius: 1.25,
                                        colors: [
                                          const Color(
                                            0xFF1E90FF,
                                          ).withValues(alpha: 0.17 * pulse),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _CardSweepPainter(
                                        progress: _floatController.value,
                                        opacity: 0.12 * entry,
                                      ),
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 4),
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 108 * pulse,
                                          height: 108 * pulse,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: RadialGradient(
                                              colors: [
                                                const Color(
                                                  0xFF1E90FF,
                                                ).withValues(alpha: 0.22),
                                                const Color(
                                                  0xFF1E90FF,
                                                ).withValues(alpha: 0.04),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: 88,
                                          height: 88,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.white.withValues(
                                                  alpha: 0.13,
                                                ),
                                                const Color(
                                                  0xFF1B2430,
                                                ).withValues(alpha: 0.95),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFF1E90FF,
                                              ).withValues(alpha: 0.46),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF1E90FF)
                                                    .withValues(
                                                      alpha: 0.18 * pulse,
                                                    ),
                                                blurRadius: 28,
                                              ),
                                            ],
                                          ),
                                          child: const Center(
                                            child: Text(
                                              "CN",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 28,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1.4,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      "Welcome to CrickNova AI ⚡",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      "Your personal AI cricket coach starts now",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: const Color(
                                          0xFFC0CAD8,
                                        ).withValues(alpha: 0.92),
                                        fontSize: 14.5,
                                        height: 1.45,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      displayName,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF6DB6FF),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    for (int i = 0; i < _features.length; i++)
                                      _featureTile(
                                        feature: _features[i],
                                        index: i,
                                      ),
                                    const SizedBox(height: 22),
                                    Transform.scale(
                                      scale: ctaScale,
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            HapticFeedback.mediumImpact();
                                            Navigator.pop(context);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: Ink(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF36A2FF),
                                                  Color(0xFF1E90FF),
                                                  Color(0xFF136DCC),
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF1E90FF,
                                                  ).withValues(alpha: 0.34),
                                                  blurRadius: 24,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  "Start Training 🚀",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextButton(
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        Navigator.pop(context);
                                      },
                                      child: const Text(
                                        "Explore Premium",
                                        style: TextStyle(
                                          color: Color(0xFF8CBFFF),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _featureTile({required _WelcomeFeature feature, required int index}) {
    final start = 0.18 + (index * 0.10);
    final end = (start + 0.22).clamp(0.0, 1.0);
    final reveal = Curves.easeOutCubic.transform(
      ((_entryController.value - start) / (end - start)).clamp(0.0, 1.0),
    );
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - reveal)),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF1E90FF).withValues(alpha: 0.14),
                ),
                child: Icon(
                  feature.icon,
                  color: const Color(0xFF6DB6FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  feature.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeature {
  final IconData icon;
  final String label;

  const _WelcomeFeature(this.icon, this.label);
}

class _WelcomeParticlesPainter extends CustomPainter {
  final double drift;
  final double opacity;

  _WelcomeParticlesPainter({required this.drift, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()..style = PaintingStyle.fill;
    final points = <Offset>[
      Offset(size.width * 0.14, size.height * 0.22),
      Offset(size.width * 0.82, size.height * 0.18),
      Offset(size.width * 0.22, size.height * 0.72),
      Offset(size.width * 0.76, size.height * 0.68),
      Offset(size.width * 0.52, size.height * 0.30),
      Offset(size.width * 0.48, size.height * 0.82),
      Offset(size.width * 0.90, size.height * 0.48),
      Offset(size.width * 0.10, size.height * 0.50),
    ];
    for (int i = 0; i < points.length; i++) {
      final phase = drift + (i * 0.11);
      final dy = math.sin(phase * math.pi * 2) * 8;
      final radius = 1.8 + (i.isEven ? 0.8 : 0.0);
      paint.color = const Color(
        0xFF6DB6FF,
      ).withValues(alpha: opacity * (i.isEven ? 0.75 : 0.46));
      canvas.drawCircle(points[i] + Offset(0, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WelcomeParticlesPainter oldDelegate) {
    return oldDelegate.drift != drift || oldDelegate.opacity != opacity;
  }
}

class _CardSweepPainter extends CustomPainter {
  final double progress;
  final double opacity;

  _CardSweepPainter({required this.progress, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final left = (size.width + 120) * progress - 120;
    final rect = Rect.fromLTWH(left, 0, 90, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: opacity),
          Colors.transparent,
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect);
    canvas.save();
    canvas.rotate(-0.18);
    canvas.drawRect(rect.shift(const Offset(0, -20)), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CardSweepPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.opacity != opacity;
  }
}

class _FreePlanDetailsScreen extends StatelessWidget {
  const _FreePlanDetailsScreen();

  static const List<String> _features = [
    "Unlimited Speed Detection",
    "Unlimited Swing Detection",
    "Unlimited Spin Detection",
    "DRS Decision System",
    "UltraEdge Detection",
    "Speed Graph",
    "Accuracy Table",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020A1F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Free Plan",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.07),
                const Color(0xFF0B1220).withValues(alpha: 0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Free Plan Features",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Everything currently available in your Free Plan.",
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: _features.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final feature = _features[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF38BDF8),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StadiumLightBackdrop extends StatelessWidget {
  const _StadiumLightBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF020A1F), Color(0xFF060C23), Color(0xFF010713)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          top: -140,
          left: -40,
          right: -40,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
            child: Container(
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE8F2FF).withValues(alpha: 0.28),
                    const Color(0xFF9EC6FF).withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 80,
          left: 14,
          right: 14,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(120),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF3B82F6).withValues(alpha: 0.08),
                    const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                    const Color(0xFF1D4ED8).withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
  late PricingRegion _resolvedPricingRegion;
  bool _isRegionLoading = true;
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
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _resolvedPricingRegion = PricingLocationService.currentRegion;
    _razorpay = Razorpay();
    debugPrint("Razorpay initialized");

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);

    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);

    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    PricingLocationService.regionNotifier.addListener(
      _handlePricingRegionChange,
    );
    PremiumService.premiumNotifier.addListener(_handlePremiumStateChange);
    MainNavigation.activeTabNotifier.addListener(_handleTabVisibilityChange);
    _loadShimmerPreference();
    _startCountdownTicker();
    unawaited(_prefetchRazorpayKey());
    unawaited(_resolvePricingRegion());
  }

  bool get _isPremiumTabVisible {
    if (widget.entrySource != 'tab') return true;
    return !PremiumService.isPremiumActive &&
        MainNavigation.activeTabNotifier.value == 3;
  }

  void _handleTabVisibilityChange() {
    _startCountdownTicker();
  }

  Future<void> _resolvePricingRegion() async {
    PricingRegion resolvedRegion = PricingLocationService.currentRegion;
    try {
      resolvedRegion = await PricingLocationService.refreshPricingRegion(
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      resolvedRegion = PricingLocationService.currentRegion;
    }

    if (!mounted) return;
    setState(() {
      _resolvedPricingRegion = resolvedRegion;
      _isRegionLoading = false;
    });
  }

  void _handlePricingRegionChange() {
    unawaited(_resolvePricingRegion());
  }

  Future<void> _loadShimmerPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool("premium_shimmer") ?? false;
    if (!mounted) return;
    setState(() => _showPremiumShimmer = enabled);
  }

  Future<void> _enablePremiumShimmer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("premium_shimmer", true);
    if (!mounted) return;
    setState(() => _showPremiumShimmer = true);
  }

  void _handlePremiumStateChange() {
    if (!mounted) return;
    setState(() {});
    _startCountdownTicker();
  }

  void _startCountdownTicker() {
    _countdownTimer?.cancel();
    if (PremiumService.expiryDate == null || !_isPremiumTabVisible) return;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (PremiumService.expiryDate == null || !_isPremiumTabVisible) {
        _countdownTimer?.cancel();
        return;
      }
      setState(() {});
    });
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
    PricingLocationService.regionNotifier.removeListener(
      _handlePricingRegionChange,
    );
    PremiumService.premiumNotifier.removeListener(_handlePremiumStateChange);
    MainNavigation.activeTabNotifier.removeListener(_handleTabVisibilityChange);
    _countdownTimer?.cancel();
    _razorpay.clear();
    super.dispose();
  }

  String _currentPlanLabel() {
    switch (PremiumService.plan) {
      case "IN_99":
        return "Monthly • ₹99";
      case "IN_299":
        return "6 Months • ₹299";
      case "IN_499":
        return "Yearly • ₹499";
      case "IN_1999":
        return "Ultra Pro • ₹1999";
      case "INTL_MONTHLY":
        return "Monthly • \$29.99";
      case "INTL_6M":
        return "6 Months • \$49.99";
      case "INTL_YEARLY":
        return "Yearly • \$69.99";
      case "INTL_ULTRA":
      case "INT_ULTRA":
      case "ULTRA":
        return "Ultra International • \$159.99";
      default:
        return "Free Plan";
    }
  }

  bool _isCurrentPlan(String price) {
    switch (PremiumService.plan) {
      case "IN_99":
        return price == "₹99";
      case "IN_299":
        return price == "₹299";
      case "IN_499":
        return price == "₹499";
      case "IN_1999":
        return price == "₹1999";
      case "INTL_MONTHLY":
        return price == "\$29.99";
      case "INTL_6M":
        return price == "\$49.99";
      case "INTL_YEARLY":
        return price == "\$69.99";
      case "INTL_ULTRA":
      case "INT_ULTRA":
      case "ULTRA":
        return price == "\$159.99" || price == "\$169.99";
      default:
        return false;
    }
  }

  Duration? _remainingDuration() {
    final expiry = PremiumService.expiryDate;
    if (expiry == null) return null;
    final diff = expiry.difference(DateTime.now());
    if (diff.isNegative) return Duration.zero;
    return diff;
  }

  String _formatCountdown(Duration? duration) {
    if (duration == null) return "--D --H --M --S --MS";
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final milliseconds = duration.inMilliseconds.remainder(1000);
    return "${days}D ${hours.toString().padLeft(2, '0')}H ${minutes.toString().padLeft(2, '0')}M ${seconds.toString().padLeft(2, '0')}S ${milliseconds.toString().padLeft(3, '0')}MS";
  }

  Widget _currentPlanOverviewCard() {
    final remaining = _remainingDuration();
    final isActive = PremiumService.isPremiumActive;
    final card = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.08),
            const Color(0xFF0A1533).withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isActive
              ? const Color(0xFFFFD700).withValues(alpha: 0.75)
              : Colors.white12,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:
                (isActive ? const Color(0xFFFFD700) : const Color(0xFF38BDF8))
                    .withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFFFD700).withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFFFFD700).withValues(alpha: 0.55)
                        : Colors.white24,
                  ),
                ),
                child: Text(
                  isActive ? "CURRENT PLAN" : "NO ACTIVE PLAN",
                  style: TextStyle(
                    color: isActive ? const Color(0xFFFFD700) : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                isActive ? Icons.workspace_premium : Icons.lock_outline_rounded,
                color: isActive ? const Color(0xFFFFD700) : Colors.white54,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _currentPlanLabel(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isActive
                ? "Remaining: ${_formatCountdown(remaining)}"
                : "Tap to view Free Plan features.",
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFFA0A0A0),
              fontSize: isActive ? 14 : 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );

    if (isActive) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _FreePlanDetailsScreen()),
          );
        },
        child: card,
      ),
    );
  }

  void onMethodSelected(String method) {
    final bool isIndia = _resolvedPricingRegion == PricingRegion.india;
    final price = _lastPlanPrice;
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please choose a plan first.")),
      );
      return;
    }
    final numeric = double.parse(price.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (method == "cricknova_pay") {
      if (isIndia == true) {
        debugPrint("CrickNova payment for ₹${numeric.toInt()}");
        _startRazorpayCheckout(numeric.toInt());
      } else {
        debugPrint("CrickNova PayPal payment for $price");
        _startPayPalCheckout(price);
      }
      return;
    }
    if (method == "google_play") {
      _startGooglePlayCheckout();
    }
  }

  String? _selectedGooglePlayBasePlanId() {
    switch (_lastPlanPrice) {
      case "₹99":
      case "\$29.99":
        return SubscriptionProvider.monthlyPlanId;
      case "₹299":
      case "\$49.99":
        return SubscriptionProvider.sixMonthPlanId;
      case "₹499":
      case "\$69.99":
        return SubscriptionProvider.oneYearPlanId;
      case "₹1999":
      case "\$159.99":
        return SubscriptionProvider.oneYearElitePlanId;
      default:
        return null;
    }
  }

  Future<void> _startGooglePlayCheckout() async {
    final String? basePlanId = _selectedGooglePlayBasePlanId();
    if (basePlanId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Google Play plan not found for this card. Please use one of the mapped plans: ₹99, ₹299, ₹499, ₹1999, \$29.99, \$49.99, \$69.99, or \$159.99.",
          ),
        ),
      );
      return;
    }

    final SubscriptionProvider subscriptionProvider = context
        .read<SubscriptionProvider>();
    await subscriptionProvider.fetchProducts();
    final GooglePlaySubscriptionPlan? selectedPlan = subscriptionProvider
        .planForBasePlanId(basePlanId);

    if (selectedPlan == null) {
      if (!mounted) return;
      final String message =
          subscriptionProvider.lastError ??
          "This Google Play plan is not available right now.";
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final bool launched = await subscriptionProvider.purchasePlan(selectedPlan);
    if (!mounted) return;

    if (launched) {
      return;
    }

    final String message =
        subscriptionProvider.lastError ??
        "Unable to start Google Play billing right now.";
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> showPaymentMethodSelector(BuildContext context) async {
    final bool isIndia = _resolvedPricingRegion == PricingRegion.india;
    final directPayTitle = isIndia
        ? "Pay via CrickNova Pay (UPI)"
        : "International Checkout";
    final directPaySubtitle = isIndia
        ? "Pay directly via Razorpay"
        : "Pay securely via PayPal";

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1220).withValues(alpha: 0.9),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 24,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const Text(
                    "Choose Payment Method",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _paymentMethodTile(
                    title: "Pay with Play Store Billing",
                    subtitle:
                        "Use Google Play subscriptions, cards, or Play balance",
                    leading: Icons.play_circle_fill_rounded,
                    leadingColor: const Color(0xFF38BDF8),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onMethodSelected("google_play");
                    },
                  ),
                  if (isIndia != true) ...[
                    const SizedBox(height: 10),
                    _paymentMethodTile(
                      title: directPayTitle,
                      subtitle: directPaySubtitle,
                      leading: Icons.account_balance_wallet_rounded,
                      leadingColor: const Color(0xFFFFD700),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onMethodSelected("cricknova_pay");
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _paymentMethodTile({
    required String title,
    required String subtitle,
    required IconData leading,
    required Color leadingColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(leading, color: leadingColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isIndia = _resolvedPricingRegion == PricingRegion.india;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final String? sourceFromArgs = args?['source'] as String?;
    final bool isAnalyseEntry =
        sourceFromArgs == "analyse" || widget.entrySource == "analyse";
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

      body: Stack(
        children: [
          const Positioned.fill(child: _StadiumLightBackdrop()),
          SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                if (_isRegionLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      minHeight: 2.5,
                      color: Colors.white70,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                _currentPlanOverviewCard(),
                ...(isIndia
                    ? (isAnalyseEntry ? indiaCompareOnlyPlans() : indiaPlans())
                    : (isAnalyseEntry
                          ? internationalCompareOnlyPlans()
                          : internationalPlans())),
              ],
            ),
          ),
        ],
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
          "15 Mistake Detection",
          "Basic Speed Detection",
          "Basic Swing Detection",
          "Basic Spin Detection",
          "Basic DRS Decision System",
          "Basic UltraEdge Detection",
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
          "30 Mistake Detection",
          "Enhanced Speed Detection",
          "Enhanced Swing Detection",
          "Enhanced Spin Detection",
          "Monthly Reports",
          "XP System & Milestones",
          "Enhanced DRS Decision System",
          "Enhanced UltraEdge Detection",
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
          "60 Mistake Detection",
          "Advanced Speed Detection",
          "Advanced Swing Detection",
          "Advanced Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Advanced DRS Decision System",
          "Advanced UltraEdge Detection",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA PRO",
        price: "₹1999",
        tag: "Elite Access 👑",
        glowColor: Colors.redAccent,
        features: [
          "5,000 AI Chats",
          "150 Mistake Detection",
          "Pro Speed Detection",
          "Pro Swing Detection",
          "Pro Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Special Gifts",
          "Pro DRS Decision System",
          "Pro UltraEdge Detection",
          "Priority AI",
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
          "3,000 AI Chats",
          "60 Mistake Detection",
          "Advanced Speed Detection",
          "Advanced Swing Detection",
          "Advanced Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Advanced DRS Decision System",
          "Advanced UltraEdge Detection",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA PRO",
        price: "₹1999",
        tag: "Unlimited Analysis 🚀",
        glowColor: Colors.redAccent,
        features: [
          "5,000 AI Chats",
          "150 Mistake Detection",
          "Pro Speed Detection",
          "Pro Swing Detection",
          "Pro Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Special Gifts",
          "Pro DRS Decision System",
          "Pro UltraEdge Detection",
          "Priority AI",
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
          "20 Mistake Detection",
          "Basic Speed Detection",
          "Basic Swing Detection",
          "Basic Spin Detection",
          "Basic DRS Decision System",
          "Basic UltraEdge Detection",
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
          "30 Mistake Detection",
          "Enhanced Speed Detection",
          "Enhanced Swing Detection",
          "Enhanced Spin Detection",
          "Monthly Reports",
          "XP System & Milestones",
          "Enhanced DRS Decision System",
          "Enhanced UltraEdge Detection",
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
          "50 Mistake Detection",
          "Advanced Speed Detection",
          "Advanced Swing Detection",
          "Advanced Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Advanced DRS Decision System",
          "Advanced UltraEdge Detection",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA INTERNATIONAL",
        price: "\$159.99",
        tag: "Elite International 🌍",
        glowColor: Colors.redAccent,
        features: [
          "7000 AI Chats",
          "150 Diff Analyse",
          "150 Mistake Detection",
          "Pro Speed Detection",
          "Pro Swing Detection",
          "Pro Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Special Gifts",
          "Pro DRS Decision System",
          "Pro UltraEdge Detection",
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
          "1,200 AI Chats",
          "30 Mistake Detection",
          "Enhanced Speed Detection",
          "Enhanced Swing Detection",
          "Enhanced Spin Detection",
          "Monthly Reports",
          "XP System & Milestones",
          "Enhanced DRS Decision System",
          "Enhanced UltraEdge Detection",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "Yearly",
        price: "\$69.99",
        tag: "Best Value 💎",
        glowColor: Colors.greenAccent,
        features: [
          "1,800 AI Chats",
          "50 Mistake Detection",
          "Advanced Speed Detection",
          "Advanced Swing Detection",
          "Advanced Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Advanced DRS Decision System",
          "Advanced UltraEdge Detection",
        ],
      ),
      const SizedBox(height: 20),
      sexyPlanCard(
        title: "ULTRA INTERNATIONAL",
        price: "\$169.99",
        tag: "Unlimited Analysis 🚀",
        glowColor: Colors.redAccent,
        features: [
          "7000 AI Chats",
          "150 Diff Analyse",
          "150 Mistake Detection",
          "Pro Speed Detection",
          "Pro Swing Detection",
          "Pro Spin Detection",
          "Speed Graph",
          "Accuracy Graph",
          "Monthly Reports",
          "XP System & Milestones",
          "Speed Certificates",
          "Special Gifts",
          "Pro DRS Decision System",
          "Pro UltraEdge Detection",
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
    final bool isMostPopular = (tag ?? "").contains("Most Popular");
    final bool isCurrentPlan = _isCurrentPlan(price);
    final cardGradient = isMostPopular
        ? const [Color(0xFF9A2BFF), Color(0xFF1D2CFF), Color(0xFF06155A)]
        : isCurrentPlan
        ? const [Color(0xFF10203F), Color(0xFF0C1730), Color(0xFF07101E)]
        : [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.04),
          ];
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 18, bottom: 22),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: cardGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isCurrentPlan
                    ? const Color(0xFFFFD700).withValues(alpha: 0.9)
                    : isMostPopular
                    ? const Color(0xFFBA78FF).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.12),
                width: isCurrentPlan ? 1.5 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isCurrentPlan
                              ? const Color(0xFFFFD700)
                              : (isMostPopular
                                    ? const Color(0xFF8F4BFF)
                                    : glowColor))
                          .withValues(
                            alpha: isCurrentPlan
                                ? 0.34
                                : (isMostPopular ? 0.55 : 0.35),
                          ),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
                if (isMostPopular)
                  BoxShadow(
                    color: const Color(0xFF2D4BFF).withValues(alpha: 0.45),
                    blurRadius: 40,
                    spreadRadius: 2,
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color:
                            (isMostPopular
                                    ? const Color(0xFF9A2BFF)
                                    : glowColor)
                                .withValues(alpha: 0.75),
                        blurRadius: 16,
                      ),
                      Shadow(
                        color:
                            (isMostPopular
                                    ? const Color(0xFF2D4BFF)
                                    : glowColor)
                                .withValues(alpha: 0.45),
                        blurRadius: 26,
                      ),
                    ],
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
                        _featureTick(
                          tint: isMostPopular
                              ? const Color(0xFFAF74FF)
                              : glowColor,
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

                    _lastPlanTitle = title;
                    _lastPlanPrice = price;

                    if (!mounted) return;

                    await showPaymentMethodSelector(context);

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
                          gradient: LinearGradient(
                            colors: isMostPopular
                                ? const [Color(0xFFBE47FF), Color(0xFF364BFF)]
                                : [glowColor, glowColor.withValues(alpha: 0.8)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isMostPopular
                                          ? const Color(0xFF9A2BFF)
                                          : glowColor)
                                      .withValues(alpha: 0.6),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color:
                                  (isMostPopular
                                          ? const Color(0xFF2D4BFF)
                                          : glowColor)
                                      .withValues(alpha: 0.32),
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
                              : Text(
                                  isCurrentPlan ? "CURRENT PLAN" : "BUY NOW",
                                  style: const TextStyle(
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
          ),
          if (tag != null)
            Positioned(
              top: 0,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: isMostPopular
                      ? const LinearGradient(
                          colors: [Color(0xFFD776FF), Color(0xFF5F5DFF)],
                        )
                      : tag.contains("Elite")
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
                    BoxShadow(
                      color:
                          (isMostPopular ? const Color(0xFF9A2BFF) : glowColor)
                              .withValues(alpha: 0.5),
                      blurRadius: 18,
                    ),
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
          if (isCurrentPlan)
            Positioned(
              top: 0,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE28A), Color(0xFFFFB300)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.34),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Text(
                  "ACTIVE",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _featureTick({required Color tint}) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [tint.withValues(alpha: 0.95), tint.withValues(alpha: 0.62)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.20),
            blurRadius: 8,
            spreadRadius: 0.2,
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
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
