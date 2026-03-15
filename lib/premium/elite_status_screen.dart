import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import '../ai/ai_coach_screen.dart';
import '../navigation/main_navigation.dart';
import '../services/premium_service.dart';
import '../upload/upload_screen.dart';
import 'elite_analytics_screen.dart';

const String eliteStatusHeroTag = 'elite-status-hero-tag';

class EliteStatusHeroBadge extends StatelessWidget {
  final VoidCallback? onTap;
  final bool expanded;

  const EliteStatusHeroBadge({super.key, this.onTap, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final radius = expanded ? 24.0 : 18.0;
    final badge = _EliteBadgeFrame(expanded: expanded);

    return Hero(
      tag: eliteStatusHeroTag,
      placeholderBuilder: (context, size, child) {
        return SizedBox(width: size.width, height: size.height);
      },
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            flightDirection,
            fromHeroContext,
            toHeroContext,
          ) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return AnimatedBuilder(
              animation: curved,
              builder: (context, child) {
                final progress = flightDirection == HeroFlightDirection.push
                    ? curved.value
                    : 1.0 - curved.value;
                final shuttleExpanded = progress > 0.52;
                final label = progress > 0.78
                    ? "ELITE STATUS"
                    : progress > 0.18
                    ? "ELITE"
                    : "ELITE USER";
                return Material(
                  color: Colors.transparent,
                  child: SizedBox.expand(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Transform.scale(
                            scale: lerpDouble(0.96, 1.0, progress)!,
                            child: _EliteBadgeFrame(
                              expanded: shuttleExpanded,
                              labelText: label,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
      child: Material(
        color: Colors.transparent,
        child: onTap == null
            ? badge
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: badge,
              ),
      ),
    );
  }
}

class _EliteBadgeFrame extends StatelessWidget {
  final bool expanded;
  final String? labelText;

  const _EliteBadgeFrame({required this.expanded, this.labelText});

  @override
  Widget build(BuildContext context) {
    final radius = expanded ? 24.0 : 18.0;
    final horizontal = expanded ? 18.0 : 12.0;
    final vertical = expanded ? 10.0 : 6.0;
    final fontSize = expanded ? 14.0 : 12.0;
    final iconSize = expanded ? 18.0 : 15.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF201405).withValues(alpha: 0.95),
            const Color(0xFF3B2508).withValues(alpha: 0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.4),
            blurRadius: expanded ? 16 : 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            color: const Color(0xFFFFD700),
            size: iconSize,
          ),
          const SizedBox(width: 8),
          Text(
            labelText ?? (expanded ? "ELITE STATUS" : "ELITE USER"),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              color: const Color(0xFFFFD700),
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class EliteStatusScreen extends StatefulWidget {
  final String userName;

  const EliteStatusScreen({super.key, required this.userName});

  @override
  State<EliteStatusScreen> createState() => _EliteStatusScreenState();
}

class _EliteStatusScreenState extends State<EliteStatusScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  bool _loadingMetrics = true;
  double _powerLevel = 0;
  double _consistencyScore = 0;
  double _maxSpeed = 0;
  double _recentAvg = 0;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _loadSpeedMetrics();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  Future<void> _loadSpeedMetrics() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "guest";
    final box = await Hive.openBox('speedBox');
    final stored = box.get('allSpeeds_$uid') as List?;

    var speeds = <double>[];
    if (stored != null) {
      speeds = stored.map((e) => (e as num).toDouble()).toList();
    }

    if (speeds.length > 30) {
      speeds = speeds.sublist(speeds.length - 30);
    }

    if (speeds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _recentAvg = 0;
        _consistencyScore = 0;
        _powerLevel = 0;
        _maxSpeed = 0;
        _loadingMetrics = false;
      });
      return;
    }

    final recent = speeds.length > 6
        ? speeds.sublist(speeds.length - 6)
        : speeds;
    final previous = speeds.length > 12
        ? speeds.sublist(speeds.length - 12, speeds.length - 6)
        : speeds.length > 6
        ? speeds.sublist(0, speeds.length - 6)
        : <double>[];

    final recentAvg = _average(recent);
    final prevAvg = _average(previous);
    final trendPercent = prevAvg > 0
        ? ((recentAvg - prevAvg) / prevAvg) * 100
        : 0.0;
    final consistencyScore = _consistencyFrom(recent);
    final improvementScore = (50 + trendPercent).clamp(0.0, 100.0);
    final powerLevel = ((consistencyScore * 0.6) + (improvementScore * 0.4))
        .clamp(0.0, 100.0);

    if (!mounted) return;
    setState(() {
      _recentAvg = recentAvg;
      _consistencyScore = consistencyScore;
      _powerLevel = powerLevel;
      _maxSpeed = speeds.isEmpty ? 0 : speeds.reduce(math.max);
      _loadingMetrics = false;
    });
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _consistencyFrom(List<double> values) {
    if (values.length < 2) return 0;
    final mean = _average(values);
    if (mean == 0) return 0;
    final variance =
        values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    final stdDev = math.sqrt(variance);
    final coefficient = stdDev / mean;
    return (100 - (coefficient * 100)).clamp(0.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final expressTarget = 140.0;
    final gapToExpress = (expressTarget - _maxSpeed).clamp(0.0, expressTarget);
    final milestoneText = _maxSpeed <= 0
        ? "Log your first delivery to set a pace target."
        : gapToExpress <= 0
        ? "Express Pace unlocked. Time to chase the 'Thunderbolt' badge!"
        : "You are ${gapToExpress.toStringAsFixed(1)} KMPH away from reaching the 'Express Pace' Badge!";

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _ambientController,
        builder: (context, _) {
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF030718),
                        Color(0xFF081427),
                        Color(0xFF111C35),
                        Color(0xFF040A18),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: const _CarbonFiberPainter()),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EliteAuraPainter(
                      progress: _ambientController.value,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        child: SizedBox(
                          height: 52,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: const EliteStatusHeroBadge(expanded: true),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: Column(
                          children: [
                            _EliteCrest(
                              progress: _ambientController.value,
                              userName: widget.userName,
                              photoUrl: currentUser?.photoURL,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              "Elite Commander: ${widget.userName}",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cormorantGaramond(
                                color: const Color(0xFFFFE9A8),
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Priority access. Elevated insights. Championship-grade AI.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                        child: _CurrentPlanCard(
                          planName: _planDisplayName(PremiumService.plan),
                          expiryLabel: _expiryLabel(PremiumService.expiryDate),
                          startedLabel: PremiumService.startedDate == null
                              ? null
                              : "Activated ${_monthYear(PremiumService.startedDate!)}",
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                        child: _ElitePowerSection(
                          powerLevel: _powerLevel,
                          consistencyScore: _consistencyScore,
                          recentAvg: _recentAvg,
                          loading: _loadingMetrics,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        child: _MilestoneCard(
                          milestoneText: milestoneText,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const UploadScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                        child: _SectionTitle(
                          title: "Elite Perks",
                          subtitle: "Tap to activate elite-only modes",
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                        child: _ElitePerkGrid(
                          onChatTap: _openCoachTab,
                          onReportTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const EliteAnalyticsScreen(),
                              ),
                            );
                          },
                          onVideosTap: _showTrainingVideosInfo,
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

  void _showTrainingVideosInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            "Exclusive Training Videos",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            "Elite-only training drops are being curated. You'll receive a notification when the next session unlocks.",
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                "Got it",
                style: TextStyle(color: Color(0xFFFFD86B)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openCoachTab() {
    final nav = MainNavigation.of(context);
    if (nav != null) {
      nav.setTab(2);
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AICoachScreen()));
  }
}

class _EliteCrest extends StatelessWidget {
  final double progress;
  final String userName;
  final String? photoUrl;

  const _EliteCrest({
    required this.progress,
    required this.userName,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final shimmer = 0.5 + (0.5 * math.sin(progress * math.pi * 2));
    final rotateY = math.sin(progress * math.pi * 2) * 0.22;
    final rotateZ = math.cos(progress * math.pi * 2) * 0.04;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(rotateY)
        ..rotateZ(rotateZ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 238,
            height: 238,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFFFFD86B,
                  ).withValues(alpha: 0.14 + (shimmer * 0.12)),
                  blurRadius: 42,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size.square(230),
            painter: _CrestPainter(progress: progress),
          ),
          ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final sweep = (progress + 0.15) % 1.0;
              return LinearGradient(
                begin: Alignment(-1.2 + (sweep * 2.4), -1),
                end: Alignment(-0.2 + (sweep * 2.4), 1),
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.65),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.34, 0.5, 0.72],
              ).createShader(bounds);
            },
            child: CustomPaint(
              size: const Size.square(230),
              painter: _CrestPainter(progress: progress, strokeOnly: true),
            ),
          ),
          _ProfileCoreAvatar(userName: userName, photoUrl: photoUrl),
        ],
      ),
    );
  }
}

class _ProfileCoreAvatar extends StatelessWidget {
  final String userName;
  final String? photoUrl;

  const _ProfileCoreAvatar({required this.userName, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final initials = userName.trim().isEmpty
        ? "P"
        : userName
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part.isEmpty ? "" : part[0].toUpperCase())
              .join();

    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE08A), Color(0xFFB8860B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD86B).withValues(alpha: 0.28),
            blurRadius: 22,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.trim().isNotEmpty
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _fallbackAvatar(initials),
              )
            : _fallbackAvatar(initials),
      ),
    );
  }

  Widget _fallbackAvatar(String initials) {
    return Container(
      color: const Color(0xFF09121E),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.cormorantGaramond(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final String planName;
  final String expiryLabel;
  final String? startedLabel;

  const _CurrentPlanCard({
    required this.planName,
    required this.expiryLabel,
    this.startedLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.1),
                const Color(0xFF11203A).withValues(alpha: 0.28),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: const Color(0xFFFFD86B).withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFD86B).withValues(alpha: 0.14),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFFFD86B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Current Plan",
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                planName,
                style: GoogleFonts.cormorantGaramond(
                  color: const Color(0xFFFFE7A0),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                expiryLabel,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (startedLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  startedLabel!,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

class _ElitePowerSection extends StatelessWidget {
  final double powerLevel;
  final double consistencyScore;
  final double recentAvg;
  final bool loading;

  const _ElitePowerSection({
    required this.powerLevel,
    required this.consistencyScore,
    required this.recentAvg,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF121826).withValues(alpha: 0.92),
            const Color(0xFF1C263A).withValues(alpha: 0.88),
          ],
        ),
        border: Border.all(color: const Color(0xFFFFD86B), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD86B).withValues(alpha: 0.18),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "Elite Power Level",
            style: GoogleFonts.poppins(
              color: const Color(0xFFFFE7A0),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _ElitePowerGauge(value: loading ? 0 : powerLevel),
          const SizedBox(height: 12),
          Row(
            children: [
              _PowerStat(
                label: "Consistency",
                value:
                    "${loading ? "--" : consistencyScore.toStringAsFixed(0)}%",
              ),
              const SizedBox(width: 12),
              _PowerStat(
                label: "Avg Speed",
                value: "${loading ? "--" : recentAvg.toStringAsFixed(1)} km/h",
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PowerStat extends StatelessWidget {
  final String label;
  final String value;

  const _PowerStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11.5),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElitePowerGauge extends StatelessWidget {
  final double value;

  const _ElitePowerGauge({required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0, 100)),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        final progress = (animatedValue / 100).clamp(0.0, 1.0);
        return SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(240, 140),
                painter: _PowerGaugePainter(progress: progress),
              ),
              Positioned(
                bottom: 26,
                child: Column(
                  children: [
                    Text(
                      animatedValue.toStringAsFixed(0),
                      style: GoogleFonts.cormorantGaramond(
                        color: const Color(0xFFFFE7A0),
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      "POWER",
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PowerGaugePainter extends CustomPainter {
  final double progress;

  _PowerGaugePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.height * 0.9;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.12);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      basePaint,
    );

    if (progress <= 0) return;
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: math.pi,
        endAngle: math.pi + (math.pi * progress),
        colors: const [Color(0xFFFFD86B), Color(0xFFFFF3B0), Color(0xFFB3881A)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi * progress,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PowerGaugePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _MilestoneCard extends StatelessWidget {
  final String milestoneText;
  final VoidCallback onTap;

  const _MilestoneCard({required this.milestoneText, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: const Color(0xFFFFD86B), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Next Milestone",
            style: GoogleFonts.poppins(
              color: const Color(0xFFFFE7A0),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            milestoneText,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD86B),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onTap,
              child: const Text(
                "Challenge Mode",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElitePerkGrid extends StatelessWidget {
  final VoidCallback onChatTap;
  final VoidCallback onReportTap;
  final VoidCallback onVideosTap;

  const _ElitePerkGrid({
    required this.onChatTap,
    required this.onReportTap,
    required this.onVideosTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: [
        _ElitePerkTile(
          title: "CHAT WITH COACH",
          icon: Icons.chat_bubble_rounded,
          accent: const Color(0xFFFFD86B),
          onTap: onChatTap,
        ),
        _ElitePerkTile(
          title: "GENERATE WEEKLY\nPDF REPORT",
          icon: Icons.picture_as_pdf_rounded,
          accent: const Color(0xFF7DD3FC),
          onTap: onReportTap,
        ),
        _ElitePerkTile(
          title: "EXCLUSIVE\nTRAINING VIDEOS",
          icon: Icons.play_circle_fill_rounded,
          accent: const Color(0xFFF59E0B),
          onTap: onVideosTap,
        ),
      ],
    );
  }
}

class _ElitePerkTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _ElitePerkTile({
    required this.title,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0E1626).withValues(alpha: 0.95),
                const Color(0xFF1B253A).withValues(alpha: 0.9),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.2),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 28),
              const Spacer(),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarbonFiberPainter extends CustomPainter {
  const _CarbonFiberPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    const spacing = 18.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }

    final overlay = Paint()
      ..color = const Color(0xFFFFD86B).withValues(alpha: 0.02)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width + size.height; x += spacing * 1.5) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        overlay,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CarbonFiberPainter oldDelegate) => false;
}

class _EliteAuraPainter extends CustomPainter {
  final double progress;

  _EliteAuraPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final auraCenters = <Offset>[
      Offset(
        size.width * (0.18 + (0.06 * math.sin(progress * math.pi * 2))),
        size.height * 0.18,
      ),
      Offset(
        size.width * (0.82 + (0.05 * math.cos(progress * math.pi * 2))),
        size.height * 0.22,
      ),
      Offset(
        size.width *
            (0.42 + (0.07 * math.cos((progress + 0.35) * math.pi * 2))),
        size.height * 0.62,
      ),
    ];

    final colors = <Color>[
      const Color(0xFFFFD86B).withValues(alpha: 0.18),
      const Color(0xFFFFC44D).withValues(alpha: 0.13),
      const Color(0xFF7DD3FC).withValues(alpha: 0.08),
    ];

    for (var i = 0; i < auraCenters.length; i++) {
      final center = auraCenters[i];
      final radius = size.shortestSide * (0.28 + (i * 0.05));
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [colors[i], Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EliteAuraPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _CrestPainter extends CustomPainter {
  final double progress;
  final bool strokeOnly;

  _CrestPainter({required this.progress, this.strokeOnly = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width * 0.46;
    final innerRadius = size.width * 0.36;

    final shieldPath = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (-math.pi / 2) + ((math.pi * 2 / 8) * i);
      final radius = i.isEven ? outerRadius : innerRadius;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        shieldPath.moveTo(point.dx, point.dy);
      } else {
        shieldPath.lineTo(point.dx, point.dy);
      }
    }
    shieldPath.close();

    if (!strokeOnly) {
      final fillPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFFFE5A3),
            const Color(0xFFD8A01A),
            const Color(0xFF7B5310),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size);
      canvas.drawShadow(shieldPath, const Color(0x99000000), 18, true);
      canvas.drawPath(shieldPath, fillPaint);
    }

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeOnly ? 10 : 2.5
      ..color = strokeOnly
          ? Colors.white.withValues(
              alpha: 0.22 + (0.12 * math.sin(progress * math.pi * 2)),
            )
          : const Color(0xFFFFF0C1).withValues(alpha: 0.95);
    canvas.drawPath(shieldPath, outlinePaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFFFFF0C1).withValues(alpha: 0.26);
    canvas.drawCircle(center, size.width * 0.39, orbitPaint);
    canvas.drawCircle(center, size.width * 0.31, orbitPaint);
  }

  @override
  bool shouldRepaint(covariant _CrestPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeOnly != strokeOnly;
  }
}

String _planDisplayName(String planId) {
  switch (planId) {
    case 'IN_99':
    case 'INTL_MONTHLY':
      return 'Elite Monthly Pro';
    case 'IN_299':
    case 'INTL_6M':
      return 'Elite Six-Month Pro';
    case 'IN_499':
    case 'INTL_YEARLY':
      return 'Legendary Yearly Pro';
    case 'IN_1999':
    case 'INTL_ULTRA':
      return 'Legendary Ultra Command';
    default:
      return 'Elite Access';
  }
}

String _expiryLabel(DateTime? date) {
  if (date == null) {
    return 'Valid while your premium access remains active';
  }
  return 'Valid until ${_monthYear(date)}';
}

String _monthYear(DateTime date) {
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}
