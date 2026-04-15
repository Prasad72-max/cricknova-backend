import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:async';
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

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  late PricingRegion _resolvedPricingRegion;
  bool _isRegionLoading = true;

  // Track selected plan
  String? _lastPlanPrice;

  String? _animatingPlan;
  bool _showPremiumShimmer = false;
  Timer? _countdownTimer;
  final ScrollController _scrollController = ScrollController();

  bool _pendingPlayBillingSuccessPopup = false;
  bool _wasPremium = false;

  final Map<String, GlobalKey> _planKeys = <String, GlobalKey>{
    "₹99": GlobalKey(),
    "₹299": GlobalKey(),
    "₹499": GlobalKey(),
    "₹1999": GlobalKey(),
    "\$29.99": GlobalKey(),
    "\$49.99": GlobalKey(),
    "\$69.99": GlobalKey(),
    "\$169.99": GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _resolvedPricingRegion = PricingLocationService.currentRegion;
    _wasPremium = PremiumService.isPremiumActive;
    PricingLocationService.regionNotifier.addListener(
      _handlePricingRegionChange,
    );
    PremiumService.premiumNotifier.addListener(_handlePremiumStateChange);
    MainNavigation.activeTabNotifier.addListener(_handleTabVisibilityChange);
    _loadShimmerPreference();
    _startCountdownTicker();
    unawaited(_resolvePricingRegion());
  }

  bool get _isPremiumTabVisible {
    if (widget.entrySource != 'tab') return true;
    return !PremiumService.isPremiumActive &&
        MainNavigation.activeTabNotifier.value == 3;
  }

  void _handleTabVisibilityChange() {
    if (_isPremiumTabVisible) {
      _startCountdownTicker();
      return;
    }
    _countdownTimer?.cancel();
    _countdownTimer = null;
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
    final bool isPremium = PremiumService.isPremiumActive;
    setState(() {});
    _startCountdownTicker();

    if (_pendingPlayBillingSuccessPopup && !_wasPremium && isPremium) {
      _pendingPlayBillingSuccessPopup = false;
      unawaited(_showSuccessPopup());
    }
    _wasPremium = isPremium;
  }

  Future<void> _showSuccessPopup() async {
    final displayName = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final userName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : "Player";
    if (!mounted) return;
    await showPremiumSuccessScreen(context, userName: userName);
  }

  void _startCountdownTicker() {
    _countdownTimer?.cancel();
    if (PremiumService.expiryDate == null || !_isPremiumTabVisible) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (PremiumService.expiryDate == null || !_isPremiumTabVisible) {
        _countdownTimer?.cancel();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    PricingLocationService.regionNotifier.removeListener(
      _handlePricingRegionChange,
    );
    PremiumService.premiumNotifier.removeListener(_handlePremiumStateChange);
    MainNavigation.activeTabNotifier.removeListener(_handleTabVisibilityChange);
    _countdownTimer?.cancel();
    _scrollController.dispose();
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
        return "Ultra International • \$169.99";
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
        return price == "\$169.99";
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

    if (isActive) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _scrollToCurrentPlanCard,
          child: card,
        ),
      );
    }

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

  void _scrollToCurrentPlanCard() {
    final String? price = _priceLabelForCurrentPlan();
    if (price == null) return;
    final targetContext = _planKeys[price]?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  String? _priceLabelForCurrentPlan() {
    switch (PremiumService.plan) {
      case "IN_99":
        return "₹99";
      case "IN_299":
        return "₹299";
      case "IN_499":
        return "₹499";
      case "IN_1999":
        return "₹1999";
      case "INTL_MONTHLY":
        return "\$29.99";
      case "INTL_6M":
        return "\$49.99";
      case "INTL_YEARLY":
        return "\$69.99";
      case "INTL_ULTRA":
      case "INT_ULTRA":
      case "ULTRA":
        return "\$169.99";
      default:
        return null;
    }
  }

  Future<void> _showPlayBillingSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1220).withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border.all(color: Colors.white12),
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
                    "Pay with Play Store Billing",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Google Play will handle billing, renewals, and cancellations.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      label: const Text(
                        "Continue",
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF38BDF8),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        _pendingPlayBillingSuccessPopup = true;
                        await _startGooglePlayCheckout();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
      case "\$169.99":
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
            "Google Play plan not found for this card. Please use one of the mapped plans: ₹99, ₹299, ₹499, ₹1999, \$29.99, \$49.99, \$69.99, or \$169.99.",
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
            controller: _scrollController,
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
      KeyedSubtree(
        key: _planKeys["₹99"],
        child: sexyPlanCard(
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["₹299"],
        child: sexyPlanCard(
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["₹499"],
        child: sexyPlanCard(
          title: "Yearly",
          price: "₹499",
          tag: "Best Value 💎",
          glowColor: Colors.greenAccent,
          features: [
            "3,000 AI Chats",
            "60 Mistake Detection",
            "Analyse Yourself Batting/Bowling (60 Vid Compare)",
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["₹1999"],
        child: sexyPlanCard(
          title: "ULTRA PRO",
          price: "₹1999",
          tag: "Elite Access 👑",
          glowColor: Colors.redAccent,
          features: [
            "5,000 AI Chats",
            "150 Mistake Detection",
            "150 Analyse Yourself Batting/Bowling",
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
      ),
    ];
  }

  List<Widget> indiaCompareOnlyPlans() {
    return [
      KeyedSubtree(
        key: _planKeys["₹499"],
        child: sexyPlanCard(
          title: "Yearly",
          price: "₹499",
          tag: "Analyse Pro 🎯",
          glowColor: Colors.greenAccent,
          features: [
            "3,000 AI Chats",
            "60 Mistake Detection",
            "Analyse Yourself Batting/Bowling (60 Vid Compare)",
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["₹1999"],
        child: sexyPlanCard(
          title: "ULTRA PRO",
          price: "₹1999",
          tag: "Unlimited Analysis 🚀",
          glowColor: Colors.redAccent,
          features: [
            "5,000 AI Chats",
            "150 Mistake Detection",
            "Analyse Yourself Batting/",
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
      ),
    ];
  }

  // ---------------- INTERNATIONAL PLANS ----------------
  List<Widget> internationalPlans() {
    return [
      KeyedSubtree(
        key: _planKeys["\$29.99"],
        child: sexyPlanCard(
          title: "Monthly",
          price: "\$29.99",
          tag: "Starter Pass ⚡",
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["\$49.99"],
        child: sexyPlanCard(
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["\$69.99"],
        child: sexyPlanCard(
          title: "Yearly",
          price: "\$69.99",
          tag: "Best Deal 💰",
          glowColor: Colors.greenAccent,
          features: [
            "3,000 AI Chats",
            "60 Mistake Detection",
            "Analyse Yourself Batting/Bowling (60 Vid Compare)",
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["\$169.99"],
        child: sexyPlanCard(
          title: "ULTRA INTERNATIONAL",
          price: "\$169.99",
          tag: "Elite International 🌍",
          glowColor: Colors.redAccent,
          features: [
            "7,000 AI Chats",
            "150 Diff Analyse",
            "150 Mistake Detection",
            "Analyse Yourself Batting/Bowling (150 Vid Compare)",
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
      KeyedSubtree(
        key: _planKeys["\$69.99"],
        child: sexyPlanCard(
          title: "Yearly",
          price: "\$69.99",
          tag: "Best Value 💎",
          glowColor: Colors.greenAccent,
          features: [
            "3,000 AI Chats",
            "60 Mistake Detection",
            "Analyse Yourself Batting/Bowling (60 Vid Compare)",
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
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["\$169.99"],
        child: sexyPlanCard(
          title: "ULTRA INTERNATIONAL",
          price: "\$169.99",
          tag: "Unlimited Analysis 🚀",
          glowColor: Colors.redAccent,
          features: [
            "7,000 AI Chats",
            "150 Diff Analyse",
            "150 Mistake Detection",
            "Analyse Yourself Batting/Bowling (150 Vid Compare)",
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
                    HapticFeedback.mediumImpact();

                    setState(() {
                      _animatingPlan = price;
                    });

                    _lastPlanPrice = price;

                    if (!mounted) return;

                    await _showPlayBillingSheet();

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
                          child: Text(
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
