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
import 'elite_status_screen.dart';
import 'payment_logos.dart';
import '../theme/crickx_colors.dart';

Future<void> showPremiumSuccessScreen(
  BuildContext context, {
  required String userName,
  bool edgeMode = false,
  int? edgeMinutes,
}) async {
  await Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          PremiumSuccessScreenV2(
            userName: userName,
            edgeMode: edgeMode,
            edgeMinutes: edgeMinutes,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(opacity: fade, child: child);
      },
    ),
  );
}

class PremiumSuccessScreen extends StatefulWidget {
  final String userName;
  final bool edgeMode;
  final int? edgeMinutes;

  const PremiumSuccessScreen({
    super.key,
    required this.userName,
    this.edgeMode = false,
    this.edgeMinutes,
  });

  @override
  State<PremiumSuccessScreen> createState() => _PremiumSuccessScreenState();
}

class PremiumSuccessScreenV2 extends StatefulWidget {
  const PremiumSuccessScreenV2({
    super.key,
    required this.userName,
    this.edgeMode = false,
    this.edgeMinutes,
  });

  final String userName;
  final bool edgeMode;
  final int? edgeMinutes;

  @override
  State<PremiumSuccessScreenV2> createState() => _PremiumSuccessScreenV2State();
}

class _PremiumSuccessScreenV2State extends State<PremiumSuccessScreenV2>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _loopController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    )..forward();
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _loopController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdge = widget.edgeMode;
    final accent = CrickXColors.limeSpark;
    final accentSoft = CrickXColors.limeSpark.withOpacity(0.85);
    final displayName = widget.userName.trim().isEmpty
        ? 'Player'
        : widget.userName.trim();
    final planLabel = isEdge ? _edgePlanLabel() : _premiumPlanLabel();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _entryController,
          _loopController,
          _pulseController,
        ]),
        builder: (context, _) {
          final entry = Curves.easeOutCubic.transform(_entryController.value);
          final headline = Curves.easeOutCubic.transform(
            ((_entryController.value - 0.24) / 0.44).clamp(0.0, 1.0),
          );
          final controls = Curves.easeOutCubic.transform(
            ((_entryController.value - 0.56) / 0.36).clamp(0.0, 1.0),
          );
          final spin = _loopController.value;
          final pulse = 0.88 + (_pulseController.value * 0.18);
          final coreRise = 44 * (1 - entry);

          return Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * entry,
                    sigmaY: 8 * entry,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          CrickXColors.graphite.withValues(alpha: 0.98),
                          CrickXColors.graphiteBg.withValues(alpha: 0.98),
                          Colors.black,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BigTechUnlockBackdropPainter(
                      spin: spin,
                      opacity: entry,
                      color: accent,
                      edgeMode: isEdge,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).maybePop();
                          },
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white70,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Transform.translate(
                            offset: Offset(0, coreRise),
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                Transform.scale(
                                  scale: pulse,
                                  child: CustomPaint(
                                    size: const Size(330, 330),
                                    painter: _BigTechOrbitPainter(
                                      spin: spin,
                                      opacity: entry,
                                      color: accent,
                                    ),
                                  ),
                                ),
                                Transform.rotate(
                                  angle: spin * math.pi * 2,
                                  child: CustomPaint(
                                    size: const Size(230, 230),
                                    painter: _CinematicHaloPainter(
                                      color: accent,
                                      opacity: entry,
                                    ),
                                  ),
                                ),
                                Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.0018)
                                    ..rotateY(spin * math.pi * 2)
                                    ..rotateX(-0.36),
                                  child: CustomPaint(
                                    size: const Size(158, 158),
                                    painter: _EliteCricketOrbPainter(
                                      spin: spin,
                                      pulse: pulse,
                                      edgeMode: isEdge,
                                    ),
                                  ),
                                ),
                                _floatingChip(
                                  icon: Icons.auto_awesome_rounded,
                                  label: isEdge ? 'LIVE AI' : 'AI COACH',
                                  angle: spin + 0.03,
                                  radius: 154,
                                  reveal: headline,
                                  color: accent,
                                ),
                                _floatingChip(
                                  icon: Icons.query_stats_rounded,
                                  label: isEdge ? '10 SEC CLIPS' : 'GRAPHS',
                                  angle: spin + 0.36,
                                  radius: 166,
                                  reveal: headline,
                                  color: accent,
                                ),
                                _floatingChip(
                                  icon: Icons.record_voice_over_rounded,
                                  label: isEdge ? 'CC + VOICE' : 'INSIGHTS',
                                  angle: spin + 0.69,
                                  radius: 152,
                                  reveal: headline,
                                  color: accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: headline,
                        child: Transform.translate(
                          offset: Offset(0, 24 * (1 - headline)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _unlockBadge(
                                text: isEdge
                                    ? 'CRICKNOVA EDGE UNLOCKED'
                                    : 'CRICKNOVA PREMIUM UNLOCKED',
                                color: accent,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                isEdge
                                    ? 'Welcome To The Edge'
                                    : 'Elite Mode Activated',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.playfairDisplay(
                                  color: Colors.white,
                                  fontSize: 39,
                                  height: 0.98,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                child: Text(
                                  isEdge
                                      ? 'Boom. Your live AI net session is awake. Every clip, every cue, every correction now moves at the speed of your cricket.'
                                      : 'Your AI coach, cricket intelligence and premium training tools are live. Train sharper, read faster, improve with intent.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.montserrat(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontSize: 14.5,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _stagePill(displayName, Colors.white70),
                                  _stagePill(planLabel, accentSoft),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Opacity(
                        opacity: controls,
                        child: Transform.scale(
                          scale: 0.94 + (controls * 0.06),
                          child: SizedBox(
                            width: math.min(
                              MediaQuery.of(context).size.width - 40,
                              390,
                            ),
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
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: const LinearGradient(
                                    colors: [
                                      CrickXColors.limeSpark,
                                      CrickXColors.limeSparkDark,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.34),
                                      blurRadius: 34,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 17,
                                  ),
                                  child: Center(
                                    child: Text(
                                      isEdge ? 'Enter The Edge' : 'Enter Elite',
                                      style: GoogleFonts.montserrat(
                                        color: CrickXColors.onLime,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).maybePop();
                          },
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: const Text(
                            'Back',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _unlockBadge({required String text, required Color color}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.42)),
          ),
          child: Text(
            text,
            style: GoogleFonts.montserrat(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stagePill(String label, Color color) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.montserrat(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _floatingChip({
    required IconData icon,
    required String label,
    required double angle,
    required double radius,
    required double reveal,
    required Color color,
  }) {
    final theta = angle * math.pi * 2;
    final x = math.cos(theta) * radius;
    final y = math.sin(theta) * radius * 0.43;
    final depth = ((math.sin(theta) + 1) / 2);
    return Opacity(
      opacity: reveal * (0.58 + depth * 0.42),
      child: Transform.translate(
        offset: Offset(x * reveal, y * reveal),
        child: Transform.scale(
          scale: (0.72 + depth * 0.20) * reveal,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.38)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: GoogleFonts.montserrat(
                        color: Colors.white.withValues(alpha: 0.90),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _premiumPlanLabel() {
    switch (PremiumService.plan) {
      case "IN_99":
        return "Monthly Elite • ₹99";
      case "IN_299":
        return "6 Months Elite • ₹299";
      case "IN_499":
        return "Yearly Elite • ₹499";
      case "IN_1999":
        return "Ultra Elite • ₹1999";
      case "INTL_MONTHLY":
        return "Monthly Elite • \$8.99";
      case "INTL_6M":
        return "6 Months Elite • \$29.99";
      case "INTL_YEARLY":
        return "Yearly Elite • \$59.99";
      case "INTL_ULTRA":
        return "Ultra Elite • \$109.99";
      default:
        return "CrickNova Elite";
    }
  }

  String _edgePlanLabel() {
    final minutes = widget.edgeMinutes;
    if (minutes == null || minutes <= 0) return "CrickNova Edge";
    return "CrickNova Edge • $minutes min";
  }
}

class _PremiumSuccessScreenState extends State<PremiumSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  late final AnimationController _floatController;
  late final AnimationController _spinController;
  List<_WelcomeFeature> get _features => widget.edgeMode
      ? const [
          _WelcomeFeature(
            Icons.auto_awesome_rounded,
            "Every 10 seconds becomes coachable",
          ),
          _WelcomeFeature(
            Icons.sports_cricket_rounded,
            "Live batting and bowling feedback",
          ),
          _WelcomeFeature(
            Icons.record_voice_over_rounded,
            "Coach voice, captions and review",
          ),
          _WelcomeFeature(
            Icons.bolt_rounded,
            "Your session now moves at match speed",
          ),
        ]
      : const [
          _WelcomeFeature(
            Icons.sports_cricket_rounded,
            "AI cricket analysis unlocked",
          ),
          _WelcomeFeature(
            Icons.auto_awesome_rounded,
            "CrickNova Coach is ready",
          ),
          _WelcomeFeature(
            Icons.query_stats_rounded,
            "Speed, swing and accuracy graphs",
          ),
          _WelcomeFeature(
            Icons.workspace_premium_rounded,
            "Elite progress journey activated",
          ),
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
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.userName.trim().isEmpty
        ? "Player"
        : widget.userName.trim();
    final isEdge = widget.edgeMode;
    const accent = CrickXColors.limeSpark;
    final accentSoft = CrickXColors.limeSpark.withValues(alpha: 0.85);
    final planLabel = isEdge ? _edgePlanLabel() : _successPlanLabel();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _entryController,
          _pulseController,
          _floatController,
          _spinController,
        ]),
        builder: (context, _) {
          final entry = Curves.easeOutCubic.transform(_entryController.value);
          final popupScale = 0.92 + (entry * 0.08);
          final popupOffset = 36 * (1 - entry);
          final pulse = 0.85 + (_pulseController.value * 0.25);
          final floatDy = math.sin(_floatController.value * math.pi * 2) * 5;
          final spin = _spinController.value;
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
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.45),
                        radius: 1.25,
                        colors: [
                          CrickXColors.graphite.withValues(alpha: 0.95),
                          CrickXColors.graphiteBg.withValues(alpha: 0.94),
                          Colors.black.withValues(alpha: 0.96),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _WelcomeParticlesPainter(
                      drift: _floatController.value,
                      opacity: 0.55 * entry,
                      color: accent,
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
                                CrickXColors.graphiteElevated.withValues(alpha: 0.98),
                                CrickXColors.graphiteBg.withValues(alpha: 0.98),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.46),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.20),
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
                                          accent.withValues(
                                            alpha: 0.18 * pulse,
                                          ),
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
                                    Text(
                                      isEdge
                                          ? "CRICKNOVA EDGE UNLOCKED"
                                          : "PREMIUM UNLOCKED",
                                      style: GoogleFonts.montserrat(
                                        color: accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.2,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Transform.rotate(
                                          angle: spin * math.pi * 2,
                                          child: CustomPaint(
                                            size: const Size(176, 176),
                                            painter: _EliteOrbitPainter(
                                              opacity: entry,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: 108 * pulse,
                                          height: 108 * pulse,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: RadialGradient(
                                              colors: [
                                                accent.withValues(alpha: 0.25),
                                                accent.withValues(alpha: 0.04),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                        Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.identity()
                                            ..setEntry(3, 2, 0.0014)
                                            ..rotateY(
                                              math.sin(spin * math.pi * 2) *
                                                  0.34,
                                            )
                                            ..rotateX(-0.18),
                                          child: CustomPaint(
                                            size: const Size(98, 98),
                                            painter: _EliteCricketOrbPainter(
                                              spin: spin,
                                              pulse: pulse,
                                              edgeMode: isEdge,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      isEdge
                                          ? "Now You Are Entering The Edge"
                                          : "CrickNova Elite Activated",
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.playfairDisplay(
                                        color: Colors.white,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      isEdge
                                          ? "Boom. CrickNova Edge is live. Your next session is built to change how you see your cricket."
                                          : "Your training dashboard, AI coach and premium cricket insights are now live.",
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.montserrat(
                                        color: Colors.white70,
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
                                        color: CrickXColors.limeSpark,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: CrickXColors.limeSpark.withValues(alpha: 0.42),
                                        ),
                                      ),
                                      child: Text(
                                        planLabel,
                                        style: GoogleFonts.montserrat(
                                          color: CrickXColors.limeSpark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
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
                                                  CrickXColors.limeSpark,
                                                  CrickXColors.limeSparkDark,
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: accent.withValues(
                                                    alpha: 0.34,
                                                  ),
                                                  blurRadius: 24,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                              child: Center(
                                                child: Text(
                                                  isEdge
                                                      ? "Start The Edge"
                                                      : "Enter CrickNova Elite",
                                                  style: const TextStyle(
                                                    color: CrickXColors.onLime,
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
                                          color: CrickXColors.limeSpark,
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
                  color: CrickXColors.limeSpark.withValues(alpha: 0.13),
                ),
                child: Icon(
                  feature.icon,
                  color: CrickXColors.limeSpark,
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

  String _successPlanLabel() {
    switch (PremiumService.plan) {
      case "IN_99":
        return "Monthly Elite • ₹99";
      case "IN_299":
        return "6 Months Elite • ₹299";
      case "IN_499":
        return "Yearly Elite • ₹499";
      case "IN_1999":
        return "Ultra Elite • ₹1999";
      case "INTL_MONTHLY":
        return "Monthly Elite • \$8.99";
      case "INTL_6M":
        return "6 Months Elite • \$29.99";
      case "INTL_YEARLY":
        return "Yearly Elite • \$59.99";
      case "INTL_ULTRA":
        return "Ultra Elite • \$109.99";
      default:
        return "CrickNova Elite";
    }
  }

  String _edgePlanLabel() {
    final minutes = widget.edgeMinutes;
    if (minutes == null || minutes <= 0) return "CrickNova Edge";
    return "CrickNova Edge • $minutes min";
  }
}

class _WelcomeFeature {
  final IconData icon;
  final String label;

  const _WelcomeFeature(this.icon, this.label);
}

class _BigTechUnlockBackdropPainter extends CustomPainter {
  const _BigTechUnlockBackdropPainter({
    required this.spin,
    required this.opacity,
    required this.color,
    required this.edgeMode,
  });

  final double spin;
  final double opacity;
  final Color color;
  final bool edgeMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final center = Offset(size.width / 2, size.height * 0.42);

    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              color.withValues(alpha: 0.25 * opacity),
              color.withValues(alpha: 0.06 * opacity),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.shortestSide * 0.74),
          );
    canvas.drawCircle(center, size.shortestSide * 0.74, glowPaint);

    final aurora = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.11 * opacity),
          CrickXColors.limeSparkDark.withValues(alpha: 0.08 * opacity),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    final auroraPath = Path()
      ..moveTo(-60, size.height * 0.18)
      ..cubicTo(
        size.width * 0.25,
        size.height * (0.06 + math.sin(spin * math.pi * 2) * 0.02),
        size.width * 0.72,
        size.height * 0.26,
        size.width + 70,
        size.height * 0.10,
      )
      ..lineTo(size.width + 80, size.height * 0.26)
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.38,
        size.width * 0.20,
        size.height * 0.22,
        -70,
        size.height * 0.36,
      )
      ..close();
    canvas.drawPath(auroraPath, aurora);

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = color.withValues(alpha: 0.08 * opacity);
    final horizon = size.height * 0.66;
    for (int i = -8; i <= 8; i++) {
      final x = size.width / 2 + i * 34.0;
      canvas.drawLine(
        Offset(x, horizon),
        Offset(size.width / 2 + i * 96.0, size.height + 60),
        gridPaint,
      );
    }
    for (int i = 0; i < 11; i++) {
      final t = i / 10;
      final y = horizon + math.pow(t, 1.9) * (size.height - horizon + 60);
      canvas.drawLine(Offset(-40, y), Offset(size.width + 40, y), gridPaint);
    }

    final starPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 44; i++) {
      final seed = i * 37.13;
      final x = (math.sin(seed) * 0.5 + 0.5) * size.width;
      final y = (math.cos(seed * 1.31) * 0.5 + 0.5) * size.height * 0.72;
      final shimmer = 0.45 + 0.55 * math.sin((spin + i * 0.07) * math.pi * 2);
      starPaint.color = Colors.white.withValues(
        alpha: opacity * shimmer * (i.isEven ? 0.42 : 0.24),
      );
      canvas.drawCircle(Offset(x, y), i.isEven ? 1.35 : 0.9, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BigTechUnlockBackdropPainter oldDelegate) {
    return oldDelegate.spin != spin ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color ||
        oldDelegate.edgeMode != edgeMode;
  }
}

class _BigTechOrbitPainter extends CustomPainter {
  const _BigTechOrbitPainter({
    required this.spin,
    required this.opacity,
    required this.color,
  });

  final double spin;
  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final center = size.center(Offset.zero);
    final rect = Offset.zero & size;

    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        transform: GradientRotation(spin * math.pi * 2),
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.80 * opacity),
          Colors.white.withValues(alpha: 0.35 * opacity),
          Colors.transparent,
          color.withValues(alpha: 0.36 * opacity),
          Colors.transparent,
        ],
      ).createShader(rect);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.24);
    canvas.scale(1.0, 0.42);
    canvas.drawCircle(Offset.zero, size.width * 0.43, outer);
    canvas.restore();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(0.58);
    canvas.scale(0.82, 0.30);
    canvas.drawCircle(Offset.zero, size.width * 0.42, outer..strokeWidth = 1.0);
    canvas.restore();

    final dotPaint = Paint()..color = color.withValues(alpha: opacity);
    final a = spin * math.pi * 2;
    canvas.drawCircle(
      center + Offset(math.cos(a) * 134, math.sin(a) * 58),
      3.4,
      dotPaint,
    );
    canvas.drawCircle(
      center + Offset(math.cos(a + math.pi) * 120, math.sin(a + math.pi) * 50),
      2.4,
      dotPaint..color = Colors.white.withValues(alpha: 0.62 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _BigTechOrbitPainter oldDelegate) {
    return oldDelegate.spin != spin ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color;
  }
}

class _CinematicHaloPainter extends CustomPainter {
  const _CinematicHaloPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.18 * opacity),
          color.withValues(alpha: 0.70 * opacity),
          Colors.white.withValues(alpha: 0.42 * opacity),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, radius * 0.82, paint);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.18 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, radius * 0.54, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _CinematicHaloPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.opacity != opacity;
  }
}

class _EliteOrbitPainter extends CustomPainter {
  final double opacity;
  final Color color;

  const _EliteOrbitPainter({
    required this.opacity,
    this.color = CrickXColors.limeSpark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final center = size.center(Offset.zero);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.85 * opacity),
          Colors.transparent,
          color.withValues(alpha: 0.45 * opacity),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);

    canvas.save();
    canvas.scale(1.0, 0.42);
    canvas.drawCircle(Offset(center.dx, center.dy / 0.42), 72, ringPaint);
    canvas.restore();

    final dotPaint = Paint()..color = color.withValues(alpha: opacity);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.50),
      3.2,
      dotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.22, size.height * 0.50),
      2.2,
      dotPaint..color = color.withValues(alpha: 0.55 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _EliteOrbitPainter oldDelegate) {
    return oldDelegate.opacity != opacity || oldDelegate.color != color;
  }
}

class _EliteCricketOrbPainter extends CustomPainter {
  final double spin;
  final double pulse;
  final bool edgeMode;

  const _EliteCricketOrbPainter({
    required this.spin,
    required this.pulse,
    this.edgeMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, radius * 0.72),
        width: radius * 1.38,
        height: radius * 0.26,
      ),
      shadowPaint,
    );

    final ballPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.42, -0.55),
        radius: 0.95,
        colors: [
          Colors.white.withValues(alpha: 0.98),
          CrickXColors.limeSpark,
          CrickXColors.limeSparkDark,
          CrickXColors.graphiteBg,
        ],
        stops: const [0.0, 0.18, 0.62, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius * 0.88, ballPaint);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = CrickXColors.limeSpark.withValues(alpha: 0.72);
    canvas.drawCircle(center, radius * 0.88, rimPaint);

    final seamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..color = CrickXColors.graphiteBg.withValues(alpha: 0.72);
    final seamShift = math.sin(spin * math.pi * 2) * radius * 0.18;
    final path = Path()
      ..moveTo(center.dx - radius * 0.58 + seamShift, center.dy - radius * 0.58)
      ..cubicTo(
        center.dx - radius * 0.15 + seamShift,
        center.dy - radius * 0.22,
        center.dx - radius * 0.16 + seamShift,
        center.dy + radius * 0.22,
        center.dx - radius * 0.58 + seamShift,
        center.dy + radius * 0.58,
      );
    canvas.drawPath(path, seamPaint);
    canvas.drawPath(
      path.shift(Offset(radius * 1.12 - seamShift * 1.4, 0)),
      seamPaint
        ..color = CrickXColors.limeSpark.withValues(alpha: 0.35),
    );

    final shinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28 * pulse);
    canvas.drawCircle(
      center.translate(-radius * 0.30, -radius * 0.34),
      radius * 0.20,
      shinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _EliteCricketOrbPainter oldDelegate) {
    return oldDelegate.spin != spin ||
        oldDelegate.pulse != pulse ||
        oldDelegate.edgeMode != edgeMode;
  }
}

class _WelcomeParticlesPainter extends CustomPainter {
  final double drift;
  final double opacity;
  final Color color;

  _WelcomeParticlesPainter({
    required this.drift,
    required this.opacity,
    this.color = CrickXColors.limeSpark,
  });

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
      paint.color = color.withValues(alpha: opacity * (i.isEven ? 0.75 : 0.46));
      canvas.drawCircle(points[i] + Offset(0, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WelcomeParticlesPainter oldDelegate) {
    return oldDelegate.drift != drift ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color;
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
  static const int _freeUploadLimit = 18;

  static const List<String> _features = [
    "18 video uploads every 24 hours",
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          "Free Plan",
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: CrickXColors.graphite,
            border: Border.all(color: CrickXColors.graphiteBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Free Plan Features",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "$remaining of $_freeUploadLimit video uploads left. Count resets in ${_formatReset(_resetIn)}.",
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CrickXColors.limeSpark.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: CrickXColors.limeSpark.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  "Go Elite for unlimited video uploads.",
                  style: GoogleFonts.poppins(
                    color: CrickXColors.limeSpark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: _features.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
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
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF22C55E),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              feature,
                              style: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
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

class PremiumScreen extends StatefulWidget {
  final String? entrySource;
  final bool showDirectPlansOnly;
  final int initialAccessTab;

  const PremiumScreen({
    super.key,
    this.entrySource,
    this.showDirectPlansOnly = false,
    this.initialAccessTab = 0,
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
    final title = '${pack.minutes} Min Net Session';
    final isIndia = PricingLocationService.isIndia;
    final price = isIndia
        ? '₹${pack.priceInr}'
        : '\$${pack.priceUsd.toStringAsFixed(2)}';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CrickXColors.graphite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CrickXColors.graphiteBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: CrickXColors.graphiteBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: CrickXColors.graphiteBorder,
                        ),
                      ),
                      child: const Icon(
                        Icons.timer_outlined,
                        color: CrickXColors.limeSpark,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.toUpperCase(),
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFE2E8F0),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Real-time live AI nets evaluation',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '/ session pack',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  height: 3.5,
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        CrickXColors.limeSpark,
                        CrickXColors.limeSparkDark,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildFeatureBullet(Icons.check_circle_rounded, '${pack.minutes} mins uninterrupted live recording'),
                const SizedBox(height: 8),
                _buildFeatureBullet(Icons.check_circle_rounded, 'Instant AI delivery detection & audio tips'),
                const SizedBox(height: 8),
                _buildFeatureBullet(Icons.check_circle_rounded, 'Saved review reels in your library'),
                const SizedBox(height: 20),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: isStarting ? null : onTap,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: CrickXColors.limeSpark,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: CrickXColors.limeSpark.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isStarting ? 'Activating...' : 'Activate Pack',
                          style: GoogleFonts.poppins(
                            color: CrickXColors.onLime,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (pack.badge.isNotEmpty)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: CrickXColors.graphiteElevated,
                  border: Border.all(
                    color: CrickXColors.graphiteBorder,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  pack.badge.toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: CrickXColors.limeSpark,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: CrickXColors.limeSpark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}



class _PremiumScreenState extends State<PremiumScreen>
    with TickerProviderStateMixin {
  late PricingRegion _resolvedPricingRegion;
  bool _isRegionLoading = true;

  // Track selected plan
  String? _lastPlanPrice;
  String? _lastPlanTitle;

  String? _animatingPlan;
  bool _showPremiumShimmer = false;
  Timer? _countdownTimer;
  StreamSubscription<LiveNetsPackConfig>? _edgePurchaseSuccessSub;
  final ValueNotifier<Duration?> _countdownRemaining = ValueNotifier(null);
  final ScrollController _scrollController = ScrollController();

  bool _pendingPlayBillingSuccessPopup = false;
  bool _wasPremium = false;
  bool _startingLivePack = false;
  late final TabController _accessTabController;

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
    _accessTabController = TabController(
      length: 2,
      initialIndex: widget.initialAccessTab.clamp(0, 1),
      vsync: this,
    );
    _wasPremium = PremiumService.isPremiumActive;
    PricingLocationService.regionNotifier.addListener(
      _handlePricingRegionChange,
    );
    PremiumService.premiumNotifier.addListener(_handlePremiumStateChange);
    MainNavigation.activeTabNotifier.addListener(_handleTabVisibilityChange);
    _edgePurchaseSuccessSub = LiveNetsPurchaseService
        .instance
        .purchaseSuccessStream
        .listen(_handleEdgePurchaseSuccess);
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
    // Trial popup removed.
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

  Future<void> _handleEdgePurchaseSuccess(LiveNetsPackConfig pack) async {
    if (!mounted) return;
    final displayName = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final userName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : "Player";
    await showPremiumSuccessScreen(
      context,
      userName: userName,
      edgeMode: true,
      edgeMinutes: pack.minutes,
    );
    if (!mounted) return;
    await PremiumService.refreshLiveEdgeBalance(
      uid: FirebaseAuth.instance.currentUser?.uid,
    );
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LiveNetsTab()));
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
    _edgePurchaseSuccessSub?.cancel();
    _accessTabController.dispose();
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
        return "CrickX Elite 👑 • \$109.99/year";
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
    if (!isActive) return const SizedBox.shrink();
    final card = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: CrickXColors.graphite,
        border: Border.all(
          color: isActive
              ? CrickXColors.limeSpark.withValues(alpha: 0.75)
              : CrickXColors.graphiteBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isActive ? CrickXColors.limeSpark : Colors.black)
                .withValues(alpha: isActive ? 0.18 : 0.7),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                      ? CrickXColors.limeSpark.withValues(alpha: 0.16)
                      : CrickXColors.graphiteElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isActive
                        ? CrickXColors.limeSpark.withValues(alpha: 0.55)
                        : CrickXColors.graphiteBorder,
                  ),
                ),
                child: Text(
                  isActive ? "CURRENT PLAN" : "NO ACTIVE PLAN",
                  style: TextStyle(
                    color: isActive ? CrickXColors.limeSpark : const Color(0xFFCBD5E1),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                isActive ? Icons.workspace_premium : Icons.lock_outline_rounded,
                color: isActive ? CrickXColors.limeSpark : Colors.white54,
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
              "Free Plan includes 18 video uploads every 24 hours. Tap to view your count.",
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
    final planTitle = _lastPlanTitle ?? "CrickNova Premium";
    final planPrice = _lastPlanPrice ?? "";

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(sheetContext).padding.bottom + 20,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF20232A),
                    Color(0xFF181A21),
                    Color(0xFF121419),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 32,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pull Handle
                    Container(
                      width: 44,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),

                    // Header with Official Google Play Logo & Shield
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2D36),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: GooglePlayLogo(size: 28),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "Google Play",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.verified_rounded,
                                          color: Color(0xFF00E676),
                                          size: 11,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          "Verified",
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFF86EFAC),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                "Official in-app billing & subscriptions",
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Selected Plan Summary Card
                    if (planPrice.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252831),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF4B5563).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    planTitle,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    "Billed securely via your Google Play account",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF374151), Color(0xFF4B5563)],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                planPrice,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 18),

                    // Supported Payment Methods Section Header
                    Row(
                      children: [
                        const Icon(
                          Icons.payments_rounded,
                          size: 15,
                          color: Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          "Accepted Payment Methods via Google Play",
                          style: GoogleFonts.poppins(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Payment Types Container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2027),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. UPI & Fast Apps
                          Row(
                            children: [
                              Text(
                                "UPI & Wallets",
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFE2E8F0),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                "Instant • 0 Fee",
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFF00E676),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              UpiLogoBadge(),
                              GPayLogoBadge(),
                              PhonePeLogoBadge(),
                              PaytmLogoBadge(),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Any UPI app: GPay, PhonePe, Paytm, BHIM, Cred & bank UPI IDs",
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 10.5,
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.08),
                              height: 1,
                            ),
                          ),

                          // 2. Debit & Credit Cards
                          Row(
                            children: [
                              Text(
                                "Debit & Credit Cards",
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFE2E8F0),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                "All Major Banks",
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              VisaLogoBadge(),
                              MastercardLogoBadge(),
                              RuPayLogoBadge(),
                              AmexLogoBadge(),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Visa, Mastercard, RuPay & Amex from Indian & international banks",
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 10.5,
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.08),
                              height: 1,
                            ),
                          ),

                          // 3. Net Banking & Play Balance
                          Row(
                            children: [
                              Text(
                                "NetBanking & Play Balance",
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFE2E8F0),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              NetBankingBadge(),
                              PlayBalanceBadge(),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "SBI, HDFC, ICICI, Axis & 50+ banks, plus Google Play redeem gift codes",
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Protection & Cancellation guarantee
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 15,
                          color: Color(0xFF00E676),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Cancel anytime with 1-tap in Google Play Subscriptions. No hidden charges.",
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Primary CTA Button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          _pendingPlayBillingSuccessPopup = true;
                          await _startGooglePlayCheckout();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF374151), Color(0xFF4B5563)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const GooglePlayLogo(size: 22),
                              const SizedBox(width: 10),
                              Text(
                                "Continue to Google Play",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
          "This Google Play plan is not available right now.";
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

  Widget _meshOrb({required double size, required List<Color> colors}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  Widget _premiumTopHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 14, 20, 16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: CrickXColors.graphite,
        border: Border.all(
          color: CrickXColors.graphiteBorder,
          width: 1.2,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).maybePop();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2D36),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: const Color(0xFF4B5563),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.sports_cricket_rounded,
                  color: Color(0xFFCBD5E1),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  "CRICKX ACCESS",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 36),
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
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
        ),
        child: Stack(
          children: [
            ListView(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _premiumTopHeader(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
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
                      _accessTabBar(),
                      const SizedBox(height: 18),
                      AnimatedBuilder(
                        animation: _accessTabController,
                        builder: (context, _) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _accessTabController.index == 1
                                ? KeyedSubtree(
                                    key: const ValueKey('edge_plans'),
                                    child: _liveNetsPayAsYouGoSection(),
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('normal_plans'),
                                    child: Column(
                                      children: [
                                        _currentPlanOverviewCard(),
                                        _premiumPlansSection(
                                          isIndia: isIndia,
                                          plans: isIndia
                                              ? (directPlansOnly
                                                    ? indiaDirectPlans()
                                                    : (isAnalyseEntry
                                                          ? indiaCompareOnlyPlans()
                                                          : indiaPlans()))
                                              : internationalPlans(),
                                        ),
                                      ],
                                    ),
                                  ),
                          );
                        },
                      ),
                      AnimatedBuilder(
                        animation: _accessTabController,
                        builder: (context, _) {
                          if (_accessTabController.index == 1) {
                            return const SizedBox(height: 12);
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D0D12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF23232A),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2A2D36),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFF4B5563).withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.info_outline_rounded,
                                      color: Color(0xFFCBD5E1),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      "Note: CrickX Analyse Yourself and Mistake Detection limits are shared between Batting and Bowling. Each usage counts as 1 towards your total limit.",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white.withValues(alpha: 0.72),
                                        fontSize: 12.5,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              for (final pack in packs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _LiveNetsPackCard(
                    pack: pack,
                    isStarting: _startingLivePack,
                    onTap: () => _startLivePackCheckout(pack),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accessTabBar() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CrickXColors.graphite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _accessTabController,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: CrickXColors.onLime,
        unselectedLabelColor: Colors.white60,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: CrickXColors.limeSpark,
          boxShadow: [
            BoxShadow(
              color: CrickXColors.limeSpark.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.workspace_premium_rounded, size: 18),
            text: 'Plans',
          ),
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.sports_cricket_rounded, size: 18),
            text: 'CrickX Edge',
          ),
        ],
      ),
    );
  }

  Widget _isometricFeatureIcon({
    required IconData icon,
    required List<Color> gradient,
  }) {
    final bool isLimeGradient = gradient.isNotEmpty &&
        (gradient.first == CrickXColors.limeSpark || gradient.last == CrickXColors.limeSpark);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          Positioned(
            left: 6,
            top: 8,
            child: Transform(
              transform: Matrix4.identity()..setEntry(0, 1, -0.15),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: gradient
                        .map((e) => e.withValues(alpha: 0.38))
                        .toList(),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: 3,
            child: Transform(
              transform: Matrix4.identity()
                ..rotateZ(-0.10)
                ..setEntry(3, 2, 0.001),
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isLimeGradient ? CrickXColors.onLime : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumPlansSection({
    required bool isIndia,
    required List<Widget> plans,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: CrickXColors.graphiteElevated,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: CrickXColors.graphiteBorder,
              ),
            ),
            child: Text(
              'SELECT MEMBERSHIP',
              style: GoogleFonts.poppins(
                color: CrickXColors.limeSpark,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _isometricFeatureIcon(
                icon: Icons.workspace_premium_rounded,
                gradient: const [CrickXColors.limeSpark, CrickXColors.limeSparkDark],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIndia ? 'Choose Your Plan' : 'Choose Your Global Plan',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Unlock app-wide AI coaching, analysis and tools',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...plans.map(
            (plan) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: plan,
            ),
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
          'Complete the Google Play purchase to unlock CrickNova Edge ${pack.minutes} min.',
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
                  colors: [Color(0xFF374151), Color(0xFF4B5563)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF1E2027), Color(0xFF181A21)],
                ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: selected
                ? const Color(0xFF64748B)
                : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
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
    final bool isCurrentPlan = _isCurrentPlan(planKey);
    final String displayTag = isCurrentPlan
        ? "Current Plan"
        : (rawTag.isEmpty ? "" : rawTag);

    final cardGradient = isCurrentPlan
        ? [
            const Color(0xFF282B34).withValues(alpha: 0.96),
            const Color(0xFF1E2027).withValues(alpha: 0.98),
            const Color(0xFF16181E),
          ]
        : [
            const Color(0xFF22252D).withValues(alpha: 0.92),
            const Color(0xFF1B1D23).withValues(alpha: 0.96),
            const Color(0xFF14151B),
          ];
    final goldColor = CrickXColors.limeSpark;
    final accentColor = isCurrentPlan ? goldColor : const Color(0xFF94A3B8);

    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 18),
            decoration: BoxDecoration(
              color: CrickXColors.graphite,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isCurrentPlan
                    ? CrickXColors.limeSpark.withValues(alpha: 0.85)
                    : CrickXColors.graphiteBorder,
                width: isCurrentPlan ? 1.5 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isCurrentPlan
                      ? CrickXColors.limeSpark.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.7),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
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
                            accentColor.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: GoogleFonts.poppins(
                            color: isCurrentPlan
                                ? CrickXColors.limeSpark
                                : const Color(0xFFE2E8F0),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          price,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 34,
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
                            gradient: const LinearGradient(
                              colors: [
                                CrickXColors.limeSpark,
                                CrickXColors.limeSparkDark,
                              ],
                            ),
                          ),
                        ),
                        if (planKey == "\$109.99")
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              "Elite international access for less than \$0.31 per day",
                              style: GoogleFonts.poppins(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (price == "₹1999")
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "Less than ₹5 per day",
                              style: GoogleFonts.poppins(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
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
                                                  ? CrickXColors.limeSpark.withValues(alpha: 0.12)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isHighlighted
                                                    ? CrickXColors.limeSpark.withValues(alpha: 0.45)
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
                                                  color: CrickXColors.limeSpark,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 14),
                                                Flexible(
                                                  child: Text(
                                                    features[i],
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: isHighlighted
                                                                ? 1.0
                                                                : 0.88,
                                                          ),
                                                      fontSize: 14,
                                                      fontWeight: isHighlighted
                                                          ? FontWeight.w700
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
                              _lastPlanPrice = planKey;
                              _lastPlanTitle = title;
                            });

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
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: isCurrentPlan
                                    ? CrickXColors.graphiteElevated
                                    : CrickXColors.limeSpark,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCurrentPlan
                                      ? CrickXColors.graphiteBorder
                                      : CrickXColors.limeSpark,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isCurrentPlan
                                            ? Colors.black
                                            : CrickXColors.limeSpark)
                                        .withValues(alpha: isCurrentPlan ? 0.35 : 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: isCurrentPlan
                                    ? Text(
                                        "Current Plan",
                                        style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          "Activate Plan",
                                          style: GoogleFonts.poppins(
                                            color: CrickXColors.onLime,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
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
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isCurrentPlan
                      ? CrickXColors.limeSpark
                      : CrickXColors.graphiteElevated,
                  border: Border.all(
                    color: isCurrentPlan
                        ? CrickXColors.limeSpark
                        : CrickXColors.limeSpark.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    if (isCurrentPlan)
                      BoxShadow(
                        color: CrickXColors.limeSpark.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    const BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
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
                          color: CrickXColors.onLime,
                        ),
                      ),
                    Text(
                      displayTag.toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: isCurrentPlan ? CrickXColors.onLime : CrickXColors.limeSpark,
                        fontWeight: isCurrentPlan
                            ? FontWeight.w900
                            : FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    // 👑 SEXY LIFETIME CARD
  }

  Widget lifetimeCardSexy({
    required String price,
    required List<String> features,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CrickXColors.graphite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CrickXColors.limeSpark, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: CrickXColors.limeSpark.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Lifetime VIP",
            style: GoogleFonts.poppins(color: CrickXColors.limeSpark, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            price,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          Text(
            "Lifetime Features:",
            style: GoogleFonts.poppins(
              color: Colors.white,
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
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
              ),
            ),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: CrickXColors.limeSpark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                "Buy Lifetime",
                style: GoogleFonts.poppins(
                  color: CrickXColors.onLime,
                  fontSize: 17,
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
