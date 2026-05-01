import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cricknova_game_plan_screen.dart';
import 'onboarding_ui_tokens.dart';

class CricknovaPaywallTransitionScreen extends StatefulWidget {
  final String userName;

  const CricknovaPaywallTransitionScreen({super.key, required this.userName});

  @override
  State<CricknovaPaywallTransitionScreen> createState() =>
      _CricknovaPaywallTransitionScreenState();
}

class _CricknovaPaywallTransitionScreenState
    extends State<CricknovaPaywallTransitionScreen>
    with TickerProviderStateMixin {
  late final AnimationController _appear;
  late final AnimationController _pulse;
  late final AnimationController _scan;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _navTimer = Timer(const Duration(milliseconds: 1200), _goPaywall);
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _appear.dispose();
    _pulse.dispose();
    _scan.dispose();
    super.dispose();
  }

  void _goPaywall() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(_paywallRoute());
  }

  PageRoute<void> _paywallRoute() {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return CricknovaGamePlanScreen(userName: widget.userName);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: OnboardingUiTokens.motionEaseOut,
          reverseCurve: OnboardingUiTokens.motionEaseIn,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final curved = CurvedAnimation(
      parent: _appear,
      curve: OnboardingUiTokens.motionEaseOut,
    );

    return Scaffold(
      backgroundColor: OnboardingColors.bgBase,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnboardingUiTokens.maxContentWidth,
            ),
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(curved),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _scan]),
                  builder: (context, _) {
                    final pulseT = reduceMotion ? 0.0 : _pulse.value;
                    final scanT = reduceMotion ? 0.0 : _scan.value;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          _AiAcknowledgeMark(pulseT: pulseT, scanT: scanT),
                          const SizedBox(height: 22),
                          Text(
                            'Thanks for trusting CrickNova.',
                            textAlign: TextAlign.center,
                            style: OnboardingTextStyles.uiSans(
                              color: OnboardingColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "We’ve analyzed your game.\nYour personalized plan is ready.",
                            textAlign: TextAlign.center,
                            style: OnboardingTextStyles.uiSans(
                              color: OnboardingColors.textSecondary.withValues(
                                alpha: 0.70,
                              ),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              height: 1.55,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'The next 30 days will decide your game.',
                            textAlign: TextAlign.center,
                            style: OnboardingTextStyles.uiSans(
                              color: OnboardingColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiAcknowledgeMark extends StatelessWidget {
  final double pulseT;
  final double scanT;

  const _AiAcknowledgeMark({required this.pulseT, required this.scanT});

  @override
  Widget build(BuildContext context) {
    final glow = 0.12 + (0.10 * pulseT);
    return SizedBox(
      width: 76,
      height: 76,
      child: CustomPaint(
        painter: _AiAcknowledgePainter(glow: glow, scanT: scanT),
      ),
    );
  }
}

class _AiAcknowledgePainter extends CustomPainter {
  final double glow;
  final double scanT;

  const _AiAcknowledgePainter({required this.glow, required this.scanT});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;

    final outerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = OnboardingColors.accent.withValues(alpha: glow);
    canvas.drawCircle(c, r - 2, outerGlow);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = OnboardingColors.accent.withValues(alpha: 0.35);
    canvas.drawCircle(c, r - 6, ring);

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = OnboardingColors.accent.withValues(alpha: 0.55);

    final start = (-math.pi / 2) + (scanT * math.pi * 2);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 10),
      start,
      math.pi / 2.8,
      false,
      sweep,
    );

    canvas.drawCircle(
      c,
      3.0,
      Paint()..color = OnboardingColors.accent.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _AiAcknowledgePainter oldDelegate) {
    return oldDelegate.glow != glow || oldDelegate.scanT != scanT;
  }
}
