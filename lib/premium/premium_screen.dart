import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/premium_service.dart';
import '../services/live_nets_purchase_service.dart';
import '../services/pricing_location_service.dart';
import '../services/subscription_provider.dart';
import '../navigation/main_navigation.dart';
import '../live/live_nets_tab.dart';
import '../services/trial_access_service.dart';
import '../onboarding/cricknova_paywall_screen.dart';

Future<void> showPremiumSuccessScreen(
  BuildContext context, {
  required String userName,
}) async {
  await Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          PremiumSuccessScreen(userName: userName),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
    _WelcomeFeature(Icons.psychology_rounded, "Cricknova Analysis"),
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
                                      "Welcome to CrickNova AI",
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
                                      "Your personal Cricknova Chat Coach starts now",
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

class _FreePlanDetailsScreen extends StatefulWidget {
  const _FreePlanDetailsScreen();

  @override
  State<_FreePlanDetailsScreen> createState() => _FreePlanDetailsScreenState();
}

class _FreePlanDetailsScreenState extends State<_FreePlanDetailsScreen> {
  static const int _freeUploadLimit = 7;

  static const List<String> _features = [
    "7 video uploads every 24 hours",
    "Speed Detection on free uploads",
    "Swing Detection on free uploads",
    "Spin Detection on free uploads",
    "DRS Decision System",
    "UltraEdge Detection",
    "Speed Graph",
    "Accuracy Table",
  ];

  Timer? _timer;
  int _used = 0;
  Duration _resetIn = const Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _loadQuota();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _loadQuota());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _uid() => FirebaseAuth.instance.currentUser?.uid ?? "guest";

  String _windowStartKey() => 'free_video_upload_window_start_${_uid()}';

  String _countKey() => 'free_video_upload_count_${_uid()}';

  DocumentReference<Map<String, dynamic>>? _quotaDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection("free_video_upload_limits")
        .doc(user.uid);
  }

  int? _intFromQuotaValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  Future<void> _loadQuota() async {
    final prefs = await SharedPreferences.getInstance();
    final quotaDoc = _quotaDoc();
    Map<String, dynamic>? remoteData;
    if (quotaDoc != null) {
      try {
        final snapshot = await quotaDoc.get();
        remoteData = snapshot.data();
      } catch (_) {
        remoteData = null;
      }
    }

    final startMs =
        _intFromQuotaValue(remoteData?["window_start_ms"]) ??
        prefs.getInt(_windowStartKey());

    int used = 0;
    Duration resetIn = const Duration(hours: 24);

    if (startMs != null) {
      final resetAt = DateTime.fromMillisecondsSinceEpoch(
        startMs,
      ).add(const Duration(hours: 24));
      resetIn = resetAt.difference(DateTime.now());
      if (resetIn.isNegative) {
        await prefs.remove(_windowStartKey());
        await prefs.setInt(_countKey(), 0);
        resetIn = const Duration(hours: 24);
      } else {
        used =
            _intFromQuotaValue(remoteData?["used"]) ??
            prefs.getInt(_countKey()) ??
            0;
        await prefs.setInt(_windowStartKey(), startMs);
        await prefs.setInt(_countKey(), used);
      }
    }

    if (!mounted) return;
    setState(() {
      _used = used.clamp(0, _freeUploadLimit);
      _resetIn = resetIn;
    });
  }

  String _formatReset(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final hours = safe.inHours.toString().padLeft(2, '0');
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "${hours}H ${minutes}M ${seconds}S";
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (_freeUploadLimit - _used).clamp(0, _freeUploadLimit);
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
              Text(
                "$remaining of $_freeUploadLimit video uploads left. Count resets in ${_formatReset(_resetIn)}.",
                style: const TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  "Go Elite for unlimited video uploads.",
                  style: TextStyle(
                    color: Color(0xFFFFE8A3),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: _features.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
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
              colors: [Color(0xFF02040C), Color(0xFF071025), Color(0xFF020714)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _InternationalAnalyticsBackdropPainter(),
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

class _InternationalAnalyticsBackdropPainter extends CustomPainter {
  const _InternationalAnalyticsBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Removed background graph lines and grid to make background empty
  }

  @override
  bool shouldRepaint(
    covariant _InternationalAnalyticsBackdropPainter oldDelegate,
  ) {
    return false;
  }
}

class _InternationalPremiumHero extends StatelessWidget {
  const _InternationalPremiumHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            const Color(0xFF07111F).withValues(alpha: 0.82),
            const Color(0xFF020614).withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFF67E8F9).withValues(alpha: 0.26),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
            blurRadius: 34,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: const Color(0xFFA855F7).withValues(alpha: 0.10),
            blurRadius: 44,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -10,
            child: Icon(
              Icons.sports_cricket_rounded,
              color: Colors.white.withValues(alpha: 0.055),
              size: 104,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF67E8F9).withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  "GLOBAL AI CRICKET ACCESS",
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFBAF4FF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "CRICKNOVA INTERNATIONAL PREMIUM 🌍",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Elite Cricket Intelligence Powered By AI",
                style: GoogleFonts.poppins(
                  color: const Color(0xFFD8F7FF).withValues(alpha: 0.82),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _HeroMetric(label: "SPEED", value: "AI"),
                  const SizedBox(width: 10),
                  _HeroMetric(label: "SWING", value: "LIVE"),
                  const SizedBox(width: 10),
                  _HeroMetric(label: "DRS", value: "EDGE"),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: Colors.white54,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PremiumScreen extends StatefulWidget {
  final String? entrySource;
  final bool showDirectPlansOnly;

  const PremiumScreen({
    super.key,
    this.entrySource,
    this.showDirectPlansOnly = false,
  });

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumEntryHighlight {
  const _PremiumEntryHighlight({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keywords,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> keywords;
}

class _LiveNetsPack {
  const _LiveNetsPack({
    required this.minutes,
    required this.priceInr,
    required this.priceUsd,
    required this.productId,
    required this.badge,
  });

  final int minutes;
  final int priceInr;
  final double priceUsd;
  final String productId;
  final String badge;
}

class _LiveNetsPackCard extends StatelessWidget {
  const _LiveNetsPackCard({
    required this.pack,
    required this.onTap,
    required this.isStarting,
  });

  final _LiveNetsPack pack;
  final VoidCallback onTap;
  final bool isStarting;

  @override
  Widget build(BuildContext context) {
    final title = '${pack.minutes} Min';
    final isIndia = PricingLocationService.isIndia;
    final price = isIndia
        ? '₹${pack.priceInr}'
        : '\$${pack.priceUsd.toStringAsFixed(2)}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isStarting ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.42),
                  ),
                ),
                child: Text(
                  pack.badge,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF00E5FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF00E5FF),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    isStarting ? 'Starting...' : 'Buy Now',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
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

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  static bool _hasShownTrialPopupSession = false;
  late PricingRegion _resolvedPricingRegion;
  bool _isRegionLoading = true;

  // Track selected plan
  String? _lastPlanPrice;

  String? _animatingPlan;
  bool _showPremiumShimmer = false;
  Timer? _countdownTimer;
  final ValueNotifier<Duration?> _countdownRemaining = ValueNotifier(null);
  final ScrollController _scrollController = ScrollController();

  bool _pendingPlayBillingSuccessPopup = false;
  bool _wasPremium = false;
  bool _startingLivePack = false;

  final Map<String, GlobalKey> _planKeys = <String, GlobalKey>{
    "₹99": GlobalKey(),
    "₹299": GlobalKey(),
    "₹499": GlobalKey(),
    "₹1999": GlobalKey(),
    "\$8.99": GlobalKey(),
    "\$29.99": GlobalKey(),
    "\$59.99": GlobalKey(),
    "\$109.99": GlobalKey(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isPremiumTabVisible) {
        _checkAndOfferTrial();
      }
    });
  }

  Future<void> _checkAndOfferTrial() async {
    if (PremiumService.isPremiumActive) return;
    if (_hasShownTrialPopupSession) return;

    // Check if eligible
    final bool isEligible = await TrialAccessService.isTrialAvailable();
    if (!isEligible) return;
    if (!mounted) return;

    // Double check visibility
    if (!_isPremiumTabVisible) return;

    _hasShownTrialPopupSession = true;

    final user = FirebaseAuth.instance.currentUser;
    final String resolvedName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : "Player";

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFF38BDF8),
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Special Offer",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "You are eligible for a 3-Day Free Trial of CrickNova Elite! Get unlimited AI analysis, DRS, and Speed Detection for free.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CricknovaPaywallScreen(userName: resolvedName),
                        ),
                      );
                    },
                    child: const Text(
                      "Claim 3-Day Trial",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Maybe Later",
                    style: TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _isPremiumTabVisible {
    if (widget.entrySource != 'tab') return true;
    return !PremiumService.isPremiumActive &&
        MainNavigation.activeTabNotifier.value == 3;
  }

  void _handleTabVisibilityChange() {
    if (_isPremiumTabVisible) {
      _startCountdownTicker();
      _checkAndOfferTrial();
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
      if (PremiumService.expiryDate == null || !_isPremiumTabVisible) {
        _countdownTimer?.cancel();
        _countdownRemaining.value = null;
        return;
      }
      _countdownRemaining.value = _remainingDuration();
    });
    _countdownRemaining.value = _remainingDuration();
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
    _countdownRemaining.dispose();
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
        return "Starter ⚡ • \$8.99/month";
      case "INTL_6M":
        return "Season Pass 🔥 • \$29.99 / 6 months";
      case "INTL_YEARLY":
        return "Pro Athlete 💎 • \$59.99/year";
      case "INTL_ULTRA":
      case "INT_ULTRA":
      case "ULTRA":
        return "CrickNova Elite 👑 • \$109.99/year";
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
        return price == "\$8.99";
      case "INTL_6M":
        return price == "\$29.99";
      case "INTL_YEARLY":
        return price == "\$59.99";
      case "INTL_ULTRA":
      case "INT_ULTRA":
      case "ULTRA":
        return price == "\$109.99";
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
          if (!isActive)
            const Text(
              "Free Plan includes 7 video uploads every 24 hours. Tap to view your count.",
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            )
          else
            ValueListenableBuilder<Duration?>(
              valueListenable: _countdownRemaining,
              builder: (context, remaining, _) {
                return Text(
                  "Remaining: ${_formatCountdown(remaining ?? _remainingDuration())}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                );
              },
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
        return "\$8.99";
      case "INTL_6M":
        return "\$29.99";
      case "INTL_YEARLY":
        return "\$59.99";
      case "INTL_ULTRA":
      case "INT_ULTRA":
      case "ULTRA":
        return "\$109.99";
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
      case "\$8.99":
        return SubscriptionProvider.monthlyPlanId;
      case "₹299":
      case "\$29.99":
        return SubscriptionProvider.sixMonthPlanId;
      case "₹499":
      case "\$59.99":
        return SubscriptionProvider.oneYearPlanId;
      case "₹1999":
      case "\$109.99":
        return SubscriptionProvider.oneYearElitePlanId;
      default:
        return null;
    }
  }

  Future<void> _startGooglePlayCheckout({
    bool allowFreeTrial = false,
    bool requireFreeTrial = false,
  }) async {
    final String? basePlanId = _selectedGooglePlayBasePlanId();
    if (basePlanId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Google Play plan not found for this card. Please use one of the mapped plans: ₹99, ₹299, ₹499, ₹1999, \$8.99, \$29.99, \$59.99, or \$109.99.",
          ),
        ),
      );
      return;
    }

    final SubscriptionProvider subscriptionProvider = context
        .read<SubscriptionProvider>();
    await subscriptionProvider.fetchProducts();
    final GooglePlaySubscriptionPlan? selectedPlan = subscriptionProvider
        .planForBasePlanId(
          basePlanId,
          allowFreeTrial: allowFreeTrial,
          requireFreeTrial: requireFreeTrial,
        );

    if (selectedPlan == null) {
      if (!mounted) return;
      final String message =
          subscriptionProvider.lastError ??
          (requireFreeTrial
              ? "The 3-day free trial is not available for this Google account. Try a new eligible tester account or choose the yearly subscription."
              : "This Google Play plan is not available right now.");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final bool launched = await subscriptionProvider.purchasePlan(
      selectedPlan,
      allowFreeTrial: allowFreeTrial,
      requireFreeTrial: requireFreeTrial,
    );
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

  String? _entrySourceFromRoute() {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return (args?['source'] as String?) ?? widget.entrySource;
  }

  _PremiumEntryHighlight? _entryHighlightFor(String? source) {
    switch (source) {
      case "ai_coach":
        return const _PremiumEntryHighlight(
          title: "Cricknova Chat Coach",
          subtitle: "You were redirected because Chat Coach needs Premium.",
          icon: Icons.auto_awesome_rounded,
          keywords: ["Cricknova Chat Coach", "Priority AI"],
        );
      case "analyse":
      case "compare_lock":
      case "compare_limit":
        return const _PremiumEntryHighlight(
          title: "Cricknova Analyse Yourself Batting",
          subtitle: "You were redirected to unlock batting video comparison.",
          icon: Icons.analytics_rounded,
          keywords: ["Cricknova Analyse Yourself"],
        );
      case "bowling_analysis":
      case "mistake_lock":
      case "mistake_usage_limit":
        return const _PremiumEntryHighlight(
          title: "Cricknova Mistake Detection",
          subtitle: "You were redirected to unlock bowling AI feedback.",
          icon: Icons.sports_baseball_rounded,
          keywords: ["Cricknova Mistake Detection"],
        );
      case "bowling_compare":
        return const _PremiumEntryHighlight(
          title: "Bowling Compare",
          subtitle: "You were redirected to unlock bowling video comparison.",
          icon: Icons.compare_arrows_rounded,
          keywords: ["Cricknova Analyse Yourself"],
        );
      case "upload_gate":
        return const _PremiumEntryHighlight(
          title: "Training Video Analysis",
          subtitle: "You were redirected to unlock AI video analysis.",
          icon: Icons.cloud_upload_rounded,
          keywords: ["Speed Detection", "Swing Detection", "Spin Detection"],
        );
      case "certificate_lock":
        return const _PremiumEntryHighlight(
          title: "Speed Certificates",
          subtitle: "You were redirected to unlock premium certificates.",
          icon: Icons.workspace_premium_rounded,
          keywords: ["Speed Certificates"],
        );
      default:
        return null;
    }
  }

  bool _isAnalyseEntrySource(String? source) {
    return source == "analyse" ||
        source == "compare_lock" ||
        source == "compare_limit" ||
        source == "bowling_compare" ||
        source == "bowling_analysis";
  }

  bool _shouldHighlightFeature(String feature) {
    final highlight = _entryHighlightFor(_entrySourceFromRoute());
    if (highlight == null) return false;
    final lowerFeature = feature.toLowerCase();
    return highlight.keywords.any(
      (keyword) => lowerFeature.contains(keyword.toLowerCase()),
    );
  }

  Widget _entryHighlightCard(_PremiumEntryHighlight highlight) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(highlight.icon, color: const Color(0xFF7DD3FC)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Unlocking: ${highlight.title}",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  highlight.subtitle,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isIndia = _resolvedPricingRegion == PricingRegion.india;
    final bool directPlansOnly = widget.showDirectPlansOnly;
    final String? entrySource = _entrySourceFromRoute();
    final highlight = _entryHighlightFor(entrySource);
    final bool isAnalyseEntry = _isAnalyseEntrySource(entrySource);
    if (!_showPremiumShimmer && PremiumService.isPremiumActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _enablePremiumShimmer();
      });
    }
    // ✅ Guard: auto-close ONLY if user opened paywall as a forced paywall,
    // and NOT when user explicitly opens from Profile or Features tab.
    if (PremiumService.isPremiumActive &&
        widget.entrySource == null &&
        entrySource != "profile" &&
        entrySource != "features") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          isIndia ? "Premium Plans" : "International Premium",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.2,
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
                if (!isIndia) const _InternationalPremiumHero(),
                _currentPlanOverviewCard(),
                if (highlight != null) _entryHighlightCard(highlight),
                if (isIndia) _liveNetsPayAsYouGoSection(),
                ...(isIndia
                    ? (directPlansOnly
                          ? indiaDirectPlans()
                          : (isAnalyseEntry
                                ? indiaCompareOnlyPlans()
                                : indiaPlans()))
                    : internationalPlans()),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.blueAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.blueAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Note: Cricknova Analyse Yourself and Mistake Detection limits are shared between Batting and Bowling. Each usage counts as 1 towards your total limit.",
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveNetsPayAsYouGoSection() {
    final packs = LiveNetsPurchaseService.packs
        .map(
          (pack) => _LiveNetsPack(
            minutes: pack.minutes,
            priceInr: pack.amountInr,
            priceUsd: pack.amountUsd,
            productId: pack.productId,
            badge: switch (pack.minutes) {
              3 => 'Quick Net',
              10 => 'Match Prep',
              _ => 'Deep Work',
            },
          ),
        )
        .toList(growable: false);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bolt_rounded, color: Color(0xFF00E5FF)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pay-As-You-Go Live Nets',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Buy only live AI net time. Normal subscription plans stay separate below.',
            style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final pack in packs)
                _LiveNetsPackCard(
                  pack: pack,
                  isStarting: _startingLivePack,
                  onTap: () => _startLivePackCheckout(pack),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startLivePackCheckout(_LiveNetsPack pack) async {
    if (_startingLivePack) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in before purchasing Live Nets time.'),
        ),
      );
      return;
    }

    setState(() => _startingLivePack = true);

    try {
      final purchaseService = LiveNetsPurchaseService.instance;
      await purchaseService.initialize();
      final launched = await purchaseService.buyPack(pack.productId);
      if (!launched) {
        throw StateError(
          purchaseService.lastError ?? 'Unable to start Google Play billing.',
        );
      }
      await PremiumService.refreshLiveEdgeBalance(uid: user.uid);
      PremiumService.premiumNotifier.forceNotify();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start CrickNova Edge: $error')),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _startingLivePack = false);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Live Nets ${pack.minutes} min purchase started. Starting Live Nets.',
        ),
      ),
    );
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LiveNetsTab()));
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
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                    blurRadius: 16,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            text,
            style: GoogleFonts.poppins(
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
          tag: "Starter",
          glowColor: Colors.blueAccent,
          features: [
            "200 Cricknova Chat Coach",
            "15 Cricknova Mistake Detection (Batting/Bowling)",
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
          tag: "Most Popular",
          glowColor: Colors.purpleAccent,
          features: [
            "1,200 Cricknova Chat Coach",
            "30 Cricknova Mistake Detection (Batting/Bowling)",
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
          tag: "Best Value",
          glowColor: Colors.greenAccent,
          features: [
            "3,000 Cricknova Chat Coach",
            "60 Cricknova Mistake Detection (Batting/Bowling)",
            "60 Cricknova Analyse Yourself (Batting/Bowling)",
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
          tag: "Elite Access",
          glowColor: Colors.redAccent,
          features: [
            "5,000 Cricknova Chat Coach",
            "150 Cricknova Mistake Detection (Batting/Bowling)",
            "150 Cricknova Analyse Yourself (Batting/Bowling)",
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

  List<Widget> indiaDirectPlans() {
    return [
      KeyedSubtree(
        key: _planKeys["₹99"],
        child: sexyPlanCard(
          title: "Monthly",
          price: "₹99",
          tag: "Starter ⚡",
          glowColor: Colors.blueAccent,
          features: [
            "200 Cricknova Chat Coach",
            "15 Cricknova Mistake Detection (Batting/Bowling)",
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
        key: _planKeys["₹499"],
        child: sexyPlanCard(
          title: "Yearly",
          price: "₹499",
          tag: "Best Value 💎",
          glowColor: Colors.greenAccent,
          features: [
            "3,000 Cricknova Chat Coach",
            "60 Cricknova Mistake Detection (Batting/Bowling)",
            "60 Cricknova Analyse Yourself (Batting/Bowling)",
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
    ];
  }

  List<Widget> indiaCompareOnlyPlans() {
    return [
      KeyedSubtree(
        key: _planKeys["₹499"],
        child: sexyPlanCard(
          title: "Yearly",
          price: "₹499",
          tag: "Analyse Pro",
          glowColor: Colors.greenAccent,
          features: [
            "3,000 Cricknova Chat Coach",
            "60 Cricknova Mistake Detection (Batting/Bowling)",
            "60 Cricknova Analyse Yourself (Batting/Bowling)",
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
          tag: "Unlimited Analysis",
          glowColor: Colors.redAccent,
          features: [
            "5,000 Cricknova Chat Coach",
            "150 Cricknova Mistake Detection (Batting/Bowling)",
            "150 Cricknova Analyse Yourself (Batting/Bowling)",
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
        key: _planKeys["\$8.99"],
        child: sexyPlanCard(
          title: "STARTER ⚡",
          price: "\$8.99/month",
          purchasePriceKey: "\$8.99",
          tag: "Starter ⚡",
          glowColor: Colors.blueAccent,
          features: [
            "250 Cricknova Chat Coach",
            "15 Cricknova Mistake Detection (Batting/Bowling)",
            "15 Cricknova Analyse Yourself (Batting/Bowling)",
            "AI Speed Analysis",
            "AI Swing Analysis",
            "AI Spin Analysis",
            "DRS Decision System",
            "UltraEdge Detection",
          ],
        ),
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["\$29.99"],
        child: sexyPlanCard(
          title: "SEASON PASS 🔥",
          price: "\$29.99 / 6 months",
          purchasePriceKey: "\$29.99",
          tag: "Most Popular",
          glowColor: Colors.purpleAccent,
          features: [
            "1500 Cricknova Chat Coach",
            "30 Cricknova Mistake Detection (Batting/Bowling)",
            "30 Cricknova Analyse Yourself (Batting/Bowling)",
            "Advanced Speed Analysis",
            "Advanced Swing Analysis",
            "Advanced Spin Analysis",
            "Monthly Performance Reports",
            "XP System & Milestones",
            "Enhanced DRS System",
            "Enhanced UltraEdge",
            "Progress Tracking",
          ],
        ),
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["\$59.99"],
        child: sexyPlanCard(
          title: "PRO ATHLETE 💎",
          price: "\$59.99/year",
          purchasePriceKey: "\$59.99",
          tag: "Best Deal",
          glowColor: Colors.greenAccent,
          features: [
            "5000 Cricknova Chat Coach",
            "60 Cricknova Mistake Detection (Batting/Bowling)",
            "60 Cricknova Analyse Yourself (Batting/Bowling)",
            "Speed Graph",
            "Accuracy Graph",
            "Speed Certificates",
            "Advanced AI Reports",
            "Advanced DRS Decision System",
            "Advanced UltraEdge Detection",
          ],
        ),
      ),
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _planKeys["\$109.99"],
        child: sexyPlanCard(
          title: "CRICKNOVA ELITE 👑",
          price: "\$109.99/year",
          purchasePriceKey: "\$109.99",
          tag: "Elite International 🌍",
          glowColor: Colors.redAccent,
          features: [
            "Unlimited Cricknova Chat Coach",
            "150 Cricknova Mistake Detection (Batting/Bowling)",
            "150 Cricknova Analyse Yourself (Batting/Bowling)",
            "Elite AI Engine",
            "Elite Speed/Swing/Spin Analysis",
            "Priority AI Processing",
            "Premium Reports",
            "Exclusive Features",
            "Special Gifts",
            "Elite DRS System",
            "Elite UltraEdge",
          ],
        ),
      ),
    ];
  }

  List<Widget> internationalDirectPlans() {
    return internationalPlans();
  }

  List<Widget> internationalCompareOnlyPlans() {
    return internationalPlans();
  }

  // 🌟 LUXURY PLAN CARD (Sleek Minimalist Gold)
  Widget sexyPlanCard({
    required String title,
    required String price,
    required Color glowColor, // kept for signature compatibility
    required List<String> features,
    String? tag,
    String? purchasePriceKey,
  }) {
    final String planKey = purchasePriceKey ?? price;
    final rawTag = (tag ?? '').trim();
    final bool isMostPopular =
        rawTag.contains("Most Popular") ||
        rawTag.contains("ULTRA") ||
        rawTag.contains("Best") ||
        rawTag.contains("Analyse Pro");
    final bool isCurrentPlan = _isCurrentPlan(planKey);
    final String displayTag = isCurrentPlan
        ? "Current Plan"
        : (rawTag.isEmpty ? "" : rawTag);

    final cardGradient = [
      Colors.white.withValues(alpha: 0.085),
      const Color(0xFF0B1220).withValues(alpha: 0.94),
      const Color(0xFF050712).withValues(alpha: 0.98),
    ];
    final goldColor = const Color(0xFFD4AF37);
    final accentColor = isCurrentPlan ? goldColor : glowColor;

    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 18, bottom: 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: cardGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: accentColor.withValues(
                  alpha: isMostPopular ? 0.55 : 0.34,
                ),
                width: isMostPopular ? 1.5 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(
                    alpha: isMostPopular ? 0.28 : 0.18,
                  ),
                  blurRadius: isMostPopular ? 42 : 30,
                  spreadRadius: isMostPopular ? 2 : 0,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                children: [
                  Positioned(
                    top: -70,
                    right: -56,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accentColor.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: GoogleFonts.poppins(
                            color: accentColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          price,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 4,
                          width: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              colors: [
                                accentColor,
                                accentColor.withValues(alpha: 0.12),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.34),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),
                        if (planKey == "\$109.99")
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              "Elite international access for less than \$0.31 per day",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (price == "₹1999")
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              "Less than ₹5 per day",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.10),
                            height: 1,
                          ),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 1400),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (int i = 0; i < features.length; i++)
                                  Builder(
                                    builder: (context) {
                                      final isHighlighted =
                                          _shouldHighlightFeature(features[i]);
                                      return Opacity(
                                        opacity: (value * 2.5 - (i * 0.1))
                                            .clamp(0.0, 1.0),
                                        child: Transform.translate(
                                          offset: Offset(
                                            0,
                                            15 *
                                                (1 -
                                                    (value * 2.5 - (i * 0.1))
                                                        .clamp(0.0, 1.0)),
                                          ),
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isHighlighted
                                                  ? 10
                                                  : 0,
                                              vertical: isHighlighted ? 8 : 0,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isHighlighted
                                                  ? const Color(
                                                      0xFF38BDF8,
                                                    ).withValues(alpha: 0.12)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isHighlighted
                                                    ? const Color(
                                                        0xFF38BDF8,
                                                      ).withValues(alpha: 0.45)
                                                    : Colors.transparent,
                                              ),
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  isHighlighted
                                                      ? Icons
                                                            .arrow_circle_right_rounded
                                                      : Icons
                                                            .check_circle_rounded,
                                                  color: isHighlighted
                                                      ? const Color(0xFF7DD3FC)
                                                      : accentColor,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 14),
                                                Flexible(
                                                  child: Text(
                                                    features[i],
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: isHighlighted
                                                                ? 1.0
                                                                : 0.88,
                                                          ),
                                                      fontSize: 15,
                                                      fontWeight: isHighlighted
                                                          ? FontWeight.w800
                                                          : FontWeight.w500,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.mediumImpact();
                            if (!mounted) return;

                            setState(() {
                              _animatingPlan = planKey;
                            });
                            _lastPlanPrice = planKey;

                            try {
                              await _showPlayBillingSheet();
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _animatingPlan = null;
                                });
                              }
                            }
                          },
                          child: AnimatedScale(
                            scale: _animatingPlan == planKey ? 0.96 : 1.0,
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accentColor.withValues(alpha: 0.95),
                                    accentColor.withValues(alpha: 0.70),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.28),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  isCurrentPlan ? "Current Plan" : "Upgrade",
                                  style: GoogleFonts.poppins(
                                    color: Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (displayTag.isNotEmpty)
            Positioned(
              top: 0,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: isCurrentPlan
                      ? const LinearGradient(
                          colors: [Color(0xFFFFE28A), Color(0xFFFFB300)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isCurrentPlan ? null : const Color(0xFF1A1A1A),
                  border: Border.all(
                    color:
                        (isCurrentPlan
                                ? const Color(0xFFFFD700)
                                : (isMostPopular
                                      ? goldColor
                                      : const Color(0xFF38BDF8)))
                            .withValues(alpha: 0.42),
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    if (isCurrentPlan)
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrentPlan)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          size: 14,
                          color: Colors.black,
                        ),
                      ),
                    Text(
                      displayTag.toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: isCurrentPlan
                            ? Colors.black
                            : (isMostPopular
                                  ? goldColor
                                  : const Color(0xFF7DD3FC)),
                        fontWeight: isCurrentPlan
                            ? FontWeight.w900
                            : FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.35,
                      ),
                    ),
                  ],
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
