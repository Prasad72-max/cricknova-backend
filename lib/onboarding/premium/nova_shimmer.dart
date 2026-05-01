import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nova_tokens.dart';

class NovaShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const NovaShimmer({super.key, required this.child, required this.enabled});

  @override
  State<NovaShimmer> createState() => _NovaShimmerState();
}

class _NovaShimmerState extends State<NovaShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    final enabled = widget.enabled && !reduceMotion;
    if (!enabled) return widget.child;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final x = (t * 2.0) - 0.5;
        return ShaderMask(
          shaderCallback: (rect) {
            final w = rect.width;
            return LinearGradient(
              begin: Alignment(-1 + x, -1),
              end: Alignment(1 + x, 1),
              colors: [
                Colors.transparent,
                NovaColors.accentGlow(0.30),
                Colors.transparent,
              ],
              stops: const [0.40, 0.52, 0.64],
              transform: _Skew(math.pi / 14),
            ).createShader(Rect.fromLTWH(0, 0, w, rect.height));
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

class _Skew extends GradientTransform {
  final double radians;
  const _Skew(this.radians);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final m = Matrix4.identity();
    // ignore: deprecated_member_use
    m.translate(bounds.width / 2, bounds.height / 2, 0);
    // SkewX: x' = x + tan(a) * y
    m.setEntry(0, 1, math.tan(radians));
    // ignore: deprecated_member_use
    m.translate(-bounds.width / 2, -bounds.height / 2, 0);
    return m;
  }
}
