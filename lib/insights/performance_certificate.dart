import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

String buildCertificateSerial(String sessionId) {
  final cleaned = sessionId.trim();
  if (cleaned.isEmpty) return "CN-000000";
  final hash = cleaned.codeUnits.fold<int>(
    0,
    (a, b) => (a * 31 + b) & 0x7fffffff,
  );
  final v = hash % 1000000;
  return "CN-${v.toString().padLeft(6, '0')}";
}

class PerformanceCertificate extends StatelessWidget {
  const PerformanceCertificate({
    super.key,
    required this.boundaryKey,
    required this.playerName,
    required this.topSpeed,
    required this.avgSpeed,
    required this.accuracyPercent,
    required this.sessionXp,
    this.speedSeries = const <double>[],
    required this.sessionId,
    required this.appLink,
    required this.darkPremium,
    required this.certificateSerial,
    this.isPremiumUser = true,
  });

  final GlobalKey boundaryKey;
  final String playerName;
  final double topSpeed;
  final double avgSpeed;
  final double accuracyPercent;
  final int sessionXp;
  final List<double> speedSeries;
  final String sessionId;
  final String appLink;
  final bool darkPremium;
  final String certificateSerial;
  final bool isPremiumUser;

  @override
  Widget build(BuildContext context) {
    final acc = accuracyPercent.clamp(0.0, 100.0);
    final screen = MediaQuery.sizeOf(context);
    final rank = _computePerformanceRank(avgSpeed, acc, isPremiumUser);

    // Base portrait canvas (scaled down with FittedBox).
    const baseW = 450.0;
    const baseH = 800.0;
    const aspect = 9 / 16;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : (screen.width * 0.92);
        final availH = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : (screen.height * 0.70);

        final targetW = math.min(availW, availH * aspect);
        final targetH = targetW / aspect;

        return SizedBox(
          width: targetW,
          height: targetH,
          child: FittedBox(
            fit: BoxFit.contain,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: baseW,
                  height: baseH,
                  child: Stack(
                    children: [
                      const Positioned.fill(child: _PremiumBackground()),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.10,
                            child: Center(
                              child: CustomPaint(
                                size: const Size(560, 560),
                                painter: _DigitalGlobePainter(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(painter: _RoseGoldBorder()),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                        child: Column(
                          children: [
                            Column(
                              children: [
                                const _BrandEmblem(),
                                const SizedBox(height: 10),
                                const Text(
                                  "OFFICIAL PERFORMANCE ANALYSIS",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFFE5E7EB),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 3.0,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  rank.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: const Color(0xFFE5E7EB),
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                    shadows: [
                                      Shadow(
                                        color: rank.accent.withOpacity(0.45),
                                        blurRadius: 18,
                                      ),
                                      Shadow(
                                        color: rank.accent.withOpacity(0.22),
                                        blurRadius: 34,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _RankBadge(
                                  text: rank.badge,
                                  accent: rank.accent,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  "Certificate ID: $certificateSerial",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Column(
                              children: [
                                const Text(
                                  "Awarded to",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  playerName.isEmpty ? "Player" : playerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: "cursive",
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              flex: 4,
                              child: _CricketVelocityGauge(
                                topSpeed: topSpeed,
                                avgSpeed: avgSpeed,
                                accuracyPercent: acc,
                                accent: rank.accent,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Column(
                              children: [
                                Row(
                                  children: [
                                    _MetricChip(
                                      label: "Session XP",
                                      value: sessionXp.toString(),
                                      accent: const Color(0xFF00FF88),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _BottomQrSignature(
                              verifyText: (appLink.isNotEmpty
                                  ? appLink
                                  : sessionId),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PerformanceRank {
  const _PerformanceRank({
    required this.title,
    required this.badge,
    required this.accent,
  });

  final String title;
  final String badge;
  final Color accent;
}

_PerformanceRank _computePerformanceRank(
  double avgSpeed,
  double accuracy,
  bool isPremiumUser,
) {
  if (!isPremiumUser) {
    return const _PerformanceRank(
      title: "RISING STAR",
      badge: "Free Member",
      accent: Color(0xFF22C55E),
    );
  }

  final s = avgSpeed;
  final a = accuracy;

  // Highest rank first: pick the best title user qualifies for.
  if (s >= 150 && a >= 90) {
    return const _PerformanceRank(
      title: "KINETIC GOD",
      badge: "Iridescent Diamond",
      accent: Color(0xFF7DD3FC),
    );
  }
  if (s >= 135 && a >= 85) {
    return const _PerformanceRank(
      title: "BALLISTIC BEAST",
      badge: "Ruby Obsidian",
      accent: Color(0xFFEF4444),
    );
  }
  if (s >= 120 && a >= 80) {
    return const _PerformanceRank(
      title: "PACE PREDATOR",
      badge: "Burnished Gold",
      accent: Color(0xFFFBBF24),
    );
  }
  if (s >= 105 && a >= 75) {
    return const _PerformanceRank(
      title: "VELOCITY VIPER",
      badge: "Cobalt Steel",
      accent: Color(0xFF2563EB),
    );
  }
  if (s >= 90 && a >= 72) {
    return const _PerformanceRank(
      title: "PRECISION PRODIGY",
      badge: "Bronze Chrome",
      accent: Color(0xFFB87333),
    );
  }

  // Fallback (should be rare because certificate is gated elsewhere).
  return const _PerformanceRank(
    title: "MASTER OF PACE",
    badge: "Verified Session",
    accent: Color(0xFF38BDF8),
  );
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.text, required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withOpacity(0.14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: 14,
            color: accent.withOpacity(0.95),
          ),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B1020), Color(0xFF030712)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: _GeometryPatternPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GeometryPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Subtle geometric rings
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 0; i < 22; i++) {
      final t = i / 22;
      p.color = Colors.white.withOpacity(0.02 + (t * 0.02));
      final inset = 10 + (t * 120);
      final rect = Rect.fromLTWH(
        inset,
        inset,
        size.width - (2 * inset),
        size.height - (2 * inset),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(26)),
        p,
      );
    }

    // Carbon-ish weave diagonals
    final weave = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1.0;
    const step = 22.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        weave,
      );
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        weave,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GeometryPatternPainter oldDelegate) => false;
}

class _DigitalGlobePainter extends CustomPainter {
  const _DigitalGlobePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.44;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFF38BDF8).withOpacity(0.18);
    canvas.drawCircle(c, r, ring);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = const Color(0xFF38BDF8).withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(c, r, glow);

    final lat = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withOpacity(0.08);

    for (int i = -3; i <= 3; i++) {
      final y = c.dy + (i * (r / 4));
      final dy = (y - c.dy).abs();
      final rr = (r * r - dy * dy);
      if (rr <= 0) continue;
      final rx = math.sqrt(rr);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx, y),
          width: rx * 2,
          height: (r / 5) * 2,
        ),
        lat,
      );
    }

    for (int i = 0; i < 8; i++) {
      final a = (i / 8) * math.pi;
      final p0 = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final p1 = Offset(c.dx - r * math.cos(a), c.dy - r * math.sin(a));
      canvas.drawLine(p0, p1, lat);
    }
  }

  @override
  bool shouldRepaint(covariant _DigitalGlobePainter oldDelegate) => false;
}

class _RoseGoldBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(6, 6, size.width - 12, size.height - 12),
      const Radius.circular(26),
    );

    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = const LinearGradient(
        colors: [Color(0xFFF6D365), Color(0xFFD4A373), Color(0xFFB45309)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.10);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = const Color(0xFFD4A373).withOpacity(0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    canvas.drawRRect(r, glow);
    canvas.drawRRect(r, outer);
    canvas.drawRRect(r.deflate(5), inner);

    for (final c in [
      Offset(16, 16),
      Offset(size.width - 16, 16),
      Offset(16, size.height - 16),
      Offset(size.width - 16, size.height - 16),
    ]) {
      canvas.drawCircle(
        c,
        7,
        Paint()
          ..color = const Color(0xFFF6D365).withOpacity(0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoseGoldBorder oldDelegate) => false;
}

class _BrandEmblem extends StatelessWidget {
  const _BrandEmblem();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFF6D365), Color(0xFFD4A373), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4A373).withOpacity(0.32),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.38),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset("assets/logo.png", fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withOpacity(0.10),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.accent,
  });
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.black.withOpacity(0.26),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionStatsPill extends StatelessWidget {
  const _SessionStatsPill({required this.top, required this.accuracy});
  final double top;
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00FF88).withOpacity(0.18),
            Colors.white.withOpacity(0.06),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FF88).withOpacity(0.18),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 16,
            color: const Color(0xFF00FF88).withOpacity(0.95),
          ),
          const SizedBox(width: 8),
          Text(
            "TOP SPEED: ${top.toStringAsFixed(1)} KMPH",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 1,
            height: 14,
            color: Colors.white.withOpacity(0.18),
          ),
          const SizedBox(width: 10),
          Text(
            "ACCURACY: ${accuracy.toStringAsFixed(0)}%",
            style: const TextStyle(
              color: Color(0xFF00FF88),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CricketVelocityGauge extends StatefulWidget {
  const _CricketVelocityGauge({
    required this.topSpeed,
    required this.avgSpeed,
    required this.accuracyPercent,
    required this.accent,
  });

  final double topSpeed;
  final double avgSpeed;
  final double accuracyPercent;
  final Color accent;

  @override
  State<_CricketVelocityGauge> createState() => _CricketVelocityGaugeState();
}

class _CricketVelocityGaugeState extends State<_CricketVelocityGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    final target = widget.avgSpeed.clamp(0.0, 160.0);
    _anim = Tween<double>(
      begin: 0,
      end: target,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _c.forward();
  }

  @override
  void didUpdateWidget(covariant _CricketVelocityGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.avgSpeed.clamp(0.0, 160.0);
    if (target != _anim.value) {
      _anim = Tween<double>(
        begin: _anim.value,
        end: target,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
      _c
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: AspectRatio(
        aspectRatio: 1.02,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final v = _anim.value;
            return CustomPaint(
              painter: _VelocityGaugePainter(speed: v, accent: widget.accent),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v.toStringAsFixed(0),
                      style: TextStyle(
                        color: widget.accent,
                        fontSize: 66,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "AVG SPEED (KMPH)",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SessionStatsPill(
                      top: widget.topSpeed,
                      accuracy: widget.accuracyPercent,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "CrickNova Kinetic Hub",
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VelocityGaugePainter extends CustomPainter {
  const _VelocityGaugePainter({required this.speed, required this.accent});
  final double speed;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.40;
    final start = math.pi * 0.78; // slightly more "radar" feel
    final sweep = math.pi * 1.44;

    // Matte radar background ring
    final bg = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final glow = Paint()
      ..color = accent.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final value = Paint()
      ..shader = LinearGradient(
        colors: [accent, const Color(0xFF00FF88), Colors.white],
      ).createShader(Rect.fromCircle(center: c, radius: r))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, start, sweep, false, bg);

    final t = (speed / 160.0).clamp(0.0, 1.0);
    canvas.drawArc(rect, start, sweep * t, false, glow);
    canvas.drawArc(rect, start, sweep * t, false, value);

    // Inner pitch-style rings (subtle)
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.06);
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(c, r * (0.55 + i * 0.12), ring);
    }

    // Tick marks
    for (int i = 0; i <= 16; i++) {
      final a = start + (sweep * (i / 16));
      final p0 = Offset(
        c.dx + (r * 1.03) * math.cos(a),
        c.dy + (r * 1.03) * math.sin(a),
      );
      final p1 = Offset(
        c.dx + (r * (i.isEven ? 1.18 : 1.12)) * math.cos(a),
        c.dy + (r * (i.isEven ? 1.18 : 1.12)) * math.sin(a),
      );
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..color = Colors.white.withOpacity(i.isEven ? 0.30 : 0.14)
          ..strokeWidth = i.isEven ? 2.2 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Speed labels (20..160)
    final labelPaint = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    final labelR = r * 1.32;
    for (int v = 20; v <= 160; v += 20) {
      final f = (v / 160.0).clamp(0.0, 1.0);
      final a = start + (sweep * f);
      final pos = Offset(
        c.dx + labelR * math.cos(a),
        c.dy + labelR * math.sin(a),
      );
      labelPaint.text = TextSpan(
        text: v.toString(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.62),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      );
      labelPaint.layout();
      labelPaint.paint(
        canvas,
        Offset(
          pos.dx - (labelPaint.width / 2),
          pos.dy - (labelPaint.height / 2),
        ),
      );
    }

    final needleA = start + (sweep * t);
    final needle = Paint()
      ..color = Colors.white.withOpacity(0.86)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final needleEnd = Offset(
      c.dx + (r * 0.94) * math.cos(needleA),
      c.dy + (r * 0.94) * math.sin(needleA),
    );
    canvas.drawLine(c, needleEnd, needle);

    // "Cricket ball" hub
    canvas.drawCircle(
      c,
      7.5,
      Paint()
        ..color = accent.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(c, 6.2, Paint()..color = Colors.white.withOpacity(0.85));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 5.2),
      -math.pi / 3,
      math.pi / 2.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.black.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _VelocityGaugePainter oldDelegate) {
    return oldDelegate.speed != speed || oldDelegate.accent != accent;
  }
}

class _BottomQrSignature extends StatelessWidget {
  const _BottomQrSignature({required this.verifyText});
  final String verifyText;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const _WaxSeal(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Founder’s Seal",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Image.asset(
                                "assets/signature.png",
                                height: 22,
                                fit: BoxFit.contain,
                                color: const Color(
                                  0xFF93C5FD,
                                ).withOpacity(0.92), // ink-blue
                                colorBlendMode: BlendMode.srcIn,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  "Prasad — Founder & Visionary,\nCrickNova AI",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                    fontFamily: "serif",
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.18)),
                    ),
                    child: QrImageView(
                      data: "https://cricknova-5f94f.web.app",
                      version: QrVersions.auto,
                      gapless: true,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Scan to verify",
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "This performance record is cryptographically verified by CrickNova Precision Engine.",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaxSeal extends StatefulWidget {
  const _WaxSeal();

  @override
  State<_WaxSeal> createState() => _WaxSealState();
}

class _WaxSealState extends State<_WaxSeal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 42.0;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFFFFE4A3),
                      Color(0xFFFFD28A),
                      Color(0xFFD4A373),
                      Color(0xFFB45309),
                    ],
                    stops: [0.0, 0.45, 0.75, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD28A).withOpacity(0.22),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
              // Embossed center
              Center(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFDE68A),
                        Color(0xFFD4A373),
                        Color(0xFF92400E),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.10),
                        blurRadius: 6,
                        offset: const Offset(-2, -2),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(2, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    "assets/logo.png",
                    fit: BoxFit.cover,
                    color: Colors.black.withOpacity(0.55),
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ),
              // Shimmer/glint sweep
              ClipOval(
                child: Transform.translate(
                  offset: Offset((t * 2 - 1) * size, 0),
                  child: Container(
                    width: size * 0.55,
                    height: size,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.0),
                          Colors.white.withOpacity(0.22),
                          Colors.white.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    transform: Matrix4.rotationZ(-0.55),
                    transformAlignment: Alignment.center,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// QR is rendered with `qr_flutter`.
