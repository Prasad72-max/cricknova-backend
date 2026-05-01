import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'nova_tokens.dart';

/// Minimal, premium background: near-black base with a subtle drifting aurora/glow.
/// Respects reduced motion via [NovaMotion.reduceMotionOf].
class NovaAuroraBackground extends StatefulWidget {
  final Widget child;

  const NovaAuroraBackground({super.key, required this.child});

  @override
  State<NovaAuroraBackground> createState() => _NovaAuroraBackgroundState();
}

class _NovaAuroraBackgroundState extends State<NovaAuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: NovaTokens.dBg)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    if (reduceMotion) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: NovaColors.bgBase),
        child: _staticGlow(child: widget.child),
      );
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final x = lerpDouble(-0.10, 0.16, t)!;
        final y = lerpDouble(0.20, -0.08, t)!;
        final x2 = lerpDouble(0.22, -0.14, t)!;
        final y2 = lerpDouble(0.04, 0.26, t)!;

        return DecoratedBox(
          decoration: const BoxDecoration(color: NovaColors.bgBase),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _glowBlob(
                alignment: Alignment(x, y),
                color: NovaColors.accentGlow(0.20),
                radius: 420,
              ),
              _glowBlob(
                alignment: Alignment(x2, y2),
                color: NovaColors.accentGlow(0.12),
                radius: 560,
              ),
              // Micro speckle (barely visible).
              IgnorePointer(
                child: Opacity(
                  opacity: 0.06,
                  child: CustomPaint(
                    painter: _SpecklePainter(seed: (t * 10000).floor()),
                  ),
                ),
              ),
              widget.child,
            ],
          ),
        );
      },
    );
  }

  Widget _staticGlow({required Widget child}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _glowBlob(
          alignment: const Alignment(-0.04, 0.12),
          color: NovaColors.accentGlow(0.18),
          radius: 480,
        ),
        _glowBlob(
          alignment: const Alignment(0.18, -0.06),
          color: NovaColors.accentGlow(0.10),
          radius: 620,
        ),
        child,
      ],
    );
  }

  static Widget _glowBlob({
    required Alignment alignment,
    required Color color,
    required double radius,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: radius,
        height: radius,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

class _SpecklePainter extends CustomPainter {
  final int seed;

  _SpecklePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()
      ..color = NovaColors.textPrimary.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final count = (size.shortestSide / 9).clamp(18, 54).floor();
    for (int i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = (rnd.nextDouble() * 1.1) + 0.25;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpecklePainter oldDelegate) =>
      oldDelegate.seed != seed;
}
