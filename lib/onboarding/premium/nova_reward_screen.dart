import 'dart:math' as math;
import 'dart:ui';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import 'nova_step_scaffold.dart';
import 'nova_tokens.dart';

class NovaRewardScreen extends StatefulWidget {
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final String title;
  final String subtitle;
  final int xp;
  final String ctaLabel;
  final VoidCallback onContinue;

  const NovaRewardScreen({
    super.key,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.title,
    required this.subtitle,
    required this.xp,
    required this.ctaLabel,
    required this.onContinue,
  });

  @override
  State<NovaRewardScreen> createState() => _NovaRewardScreenState();
}

class _NovaRewardScreenState extends State<NovaRewardScreen>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _count;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(milliseconds: 520));
    _count = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!NovaMotion.reduceMotionOf(context)) _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    final target = widget.xp;
    return Stack(
      children: [
        NovaStepScaffold(
          onBack: widget.onBack,
          progress: widget.progress,
          progressText: 'Building your player profile',
          stepText: widget.stepText,
          categoryLabel: 'Reward',
          title: widget.title,
          subtitle: widget.subtitle,
          body: Center(
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  decoration: BoxDecoration(
                    color: NovaColors.bgElevated,
                    borderRadius: BorderRadius.circular(NovaTokens.rXl),
                    border: Border.all(color: NovaColors.borderSubtle),
                    boxShadow: [
                      BoxShadow(
                        color: NovaColors.accentGlow(0.20),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: AnimatedBuilder(
                    animation: _count,
                    builder: (context, _) {
                      final t = reduceMotion
                          ? 1.0
                          : Curves.easeOutCubic.transform(_count.value);
                      final shown = (target * t).round().clamp(0, target);
                      final scale = reduceMotion
                          ? 1.0
                          : lerpDouble(0.98, 1.02, math.sin(t * math.pi))!;
                      return Transform.scale(
                        scale: scale,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: NovaColors.accentGlow(0.14),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: NovaColors.accentGlow(0.55),
                                ),
                              ),
                              child: const Icon(
                                Icons.stars_rounded,
                                color: NovaColors.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '+$shown XP',
                              style: NovaTypography.title(
                                size: 22,
                                weight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1.0,
                                color: NovaColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Unlocked: first coaching insights',
                  textAlign: TextAlign.center,
                  style: NovaTypography.body(
                    size: 13,
                    height: 1.35,
                    color: NovaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          ctaLabel: widget.ctaLabel,
          ctaEnabled: true,
          onCta: widget.onContinue,
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.06,
            numberOfParticles: 16,
            maxBlastForce: 10,
            minBlastForce: 6,
            gravity: 0.22,
            colors: const [NovaColors.accent],
            shouldLoop: false,
            createParticlePath: _tinyConfetti,
          ),
        ),
      ],
    );
  }
}

Path _tinyConfetti(Size size) {
  final p = Path();
  final w = size.width;
  final h = size.height;
  p.addRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w / 2, h / 2), width: w, height: h),
      Radius.circular(math.min(w, h) / 2.6),
    ),
  );
  return p;
}
