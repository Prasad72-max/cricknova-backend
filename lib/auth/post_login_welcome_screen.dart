import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/main_navigation.dart';

class PostLoginWelcomeScreen extends StatefulWidget {
  final String userName;

  const PostLoginWelcomeScreen({super.key, required this.userName});

  static String _seenKey(String userId) => "new_user_field_intro_seen_$userId";

  static bool isEligibleNewUser(User user, {bool? explicitIsNewUser}) {
    if (explicitIsNewUser != null) {
      return explicitIsNewUser;
    }

    final createdAt = user.metadata.creationTime;
    final lastSignInAt = user.metadata.lastSignInTime;
    if (createdAt == null || lastSignInAt == null) {
      return false;
    }

    return lastSignInAt.difference(createdAt).abs() <=
        const Duration(minutes: 2);
  }

  static Future<bool> shouldShowFor({
    required SharedPreferences prefs,
    required User user,
    bool? explicitIsNewUser,
  }) async {
    final seen = prefs.getBool(_seenKey(user.uid)) ?? false;
    if (seen) {
      return false;
    }

    return isEligibleNewUser(user, explicitIsNewUser: explicitIsNewUser);
  }

  static Future<void> markSeen(SharedPreferences prefs, String userId) async {
    await prefs.setBool(_seenKey(userId), true);
  }

  @override
  State<PostLoginWelcomeScreen> createState() => _PostLoginWelcomeScreenState();
}

class _PostLoginWelcomeScreenState extends State<PostLoginWelcomeScreen>
    with TickerProviderStateMixin {
  static const _fallbackAudioAsset = "audio/onboarding_whoosh.wav";

  late final AnimationController _timelineController;
  late final AnimationController _badgeController;
  final AudioPlayer _crowdPlayer = AudioPlayer();
  final AudioPlayer _fxPlayer = AudioPlayer();
  final List<Timer> _timers = <Timer>[];

  bool _showCard = false;
  bool _showBadge = false;
  bool _showBatting = false;
  bool _showBowling = false;
  bool _showCoaching = false;
  bool _showEnterButton = false;
  bool _overlayDismissed = false;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _timelineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..forward();
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _scheduleSequence();
    _startAudioTimeline();
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timelineController.dispose();
    _badgeController.dispose();
    _crowdPlayer.dispose();
    _fxPlayer.dispose();
    super.dispose();
  }

  void _scheduleSequence() {
    _timers.add(
      Timer(const Duration(milliseconds: 360), () {
        if (!mounted) return;
        setState(() {
          _showCard = true;
          _showBadge = true;
        });
      }),
    );

    _timers.add(
      Timer(const Duration(milliseconds: 980), () {
        _revealCalibrationStep(update: () => _showBatting = true);
      }),
    );
    _timers.add(
      Timer(const Duration(milliseconds: 1450), () {
        _revealCalibrationStep(update: () => _showBowling = true);
      }),
    );
    _timers.add(
      Timer(const Duration(milliseconds: 1900), () {
        _revealCalibrationStep(update: () => _showCoaching = true);
      }),
    );
    _timers.add(
      Timer(const Duration(milliseconds: 2280), () {
        if (!mounted) return;
        setState(() => _showEnterButton = true);
      }),
    );
  }

  void _revealCalibrationStep({required VoidCallback update}) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(update);
  }

  Future<void> _startAudioTimeline() async {
    try {
      await _crowdPlayer.setReleaseMode(ReleaseMode.loop);
      await _crowdPlayer.setVolume(0.16);
      try {
        await _crowdPlayer.play(AssetSource("audio/stadium_crowd_cheer.wav"));
      } catch (_) {
        await _crowdPlayer.play(AssetSource(_fallbackAudioAsset));
      }

      for (var step = 1; step <= 8; step++) {
        _timers.add(
          Timer(Duration(milliseconds: 250 * step), () async {
            final volume = 0.16 + (step * 0.06);
            try {
              await _crowdPlayer.setVolume(volume.clamp(0.0, 0.78));
            } catch (_) {}
          }),
        );
      }

      _timers.add(
        Timer(const Duration(milliseconds: 2100), () async {
          try {
            await _fxPlayer.setVolume(0.92);
            await _fxPlayer.play(AssetSource("audio/stadium_whistle.wav"));
          } catch (_) {
            try {
              await _fxPlayer.setVolume(0.82);
              await _fxPlayer.play(AssetSource(_fallbackAudioAsset));
            } catch (_) {}
          }
        }),
      );
    } catch (_) {}
  }

  Future<void> _enterField() async {
    if (_isDismissing) return;
    HapticFeedback.heavyImpact();
    setState(() => _isDismissing = true);

    try {
      await _crowdPlayer.stop();
      await _fxPlayer.stop();
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    setState(() => _overlayDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _overlayDismissed,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AbsorbPointer(
              absorbing: !_overlayDismissed,
              child: MainNavigation(userName: widget.userName),
            ),
            if (!_overlayDismissed)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 380),
                opacity: _isDismissing ? 0.0 : 1.0,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _timelineController,
                    _badgeController,
                  ]),
                  builder: (context, _) {
                    final timeline = _timelineController.value;
                    final badgeSpin = _badgeController.value;
                    final blurProgress = _interval(
                      timeline,
                      start: 0.06,
                      end: 0.24,
                      curve: Curves.easeOut,
                    );
                    final blackCurtain = timeline < 0.09
                        ? 1.0
                        : lerpDouble(
                                1.0,
                                0.44,
                                _interval(
                                  timeline,
                                  start: 0.09,
                                  end: 0.22,
                                  curve: Curves.easeOut,
                                ),
                              ) ??
                              0.44;

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 6 + (blurProgress * 12),
                              sigmaY: 6 + (blurProgress * 12),
                            ),
                            child: Container(
                              color: Color.lerp(
                                Colors.black,
                                const Color(0xFF020611).withValues(alpha: 0.6),
                                1 - blackCurtain,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _StadiumSpotlightPainter(
                                intensity: _spotlightIntensity(timeline),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: MediaQuery.of(context).padding.top + 92,
                          child: Center(
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 520),
                              curve: Curves.easeOutCubic,
                              offset: _showBadge
                                  ? Offset.zero
                                  : const Offset(0, -0.2),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 420),
                                opacity: _showBadge ? 1.0 : 0.0,
                                child: _RankBadge(rotationTurns: badgeSpin),
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                            child: Column(
                              children: [
                                const Spacer(),
                                AnimatedSlide(
                                  duration: const Duration(milliseconds: 680),
                                  curve: Curves.easeOutCubic,
                                  offset: _showCard
                                      ? Offset.zero
                                      : const Offset(0, 0.22),
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 420),
                                    opacity: _showCard ? 1.0 : 0.0,
                                    child: _WelcomeGlassCard(
                                      userName: widget.userName,
                                      showBatting: _showBatting,
                                      showBowling: _showBowling,
                                      showCoaching: _showCoaching,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                AnimatedSlide(
                                  duration: const Duration(milliseconds: 520),
                                  curve: Curves.easeOutBack,
                                  offset: _showEnterButton
                                      ? Offset.zero
                                      : const Offset(0, 0.2),
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 320),
                                    opacity: _showEnterButton ? 1.0 : 0.0,
                                    child: _EnterFieldButton(
                                      breathingValue: badgeSpin,
                                      onPressed: _enterField,
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
              ),
          ],
        ),
      ),
    );
  }

  double _interval(
    double value, {
    required double start,
    required double end,
    Curve curve = Curves.linear,
  }) {
    if (value <= start) return 0.0;
    if (value >= end) return 1.0;
    final normalized = (value - start) / (end - start);
    return curve.transform(normalized.clamp(0.0, 1.0));
  }

  double _spotlightIntensity(double timeline) {
    if (timeline < 0.1) {
      return 0.0;
    }
    if (timeline >= 0.28) {
      return 1.0;
    }

    final flickerT = (timeline - 0.1) / 0.18;
    final raw =
        0.34 +
        (0.66 * math.sin(flickerT * math.pi * 14).abs()) +
        (0.18 * math.cos(flickerT * math.pi * 23));
    return raw.clamp(0.0, 1.0);
  }
}

class _WelcomeGlassCard extends StatelessWidget {
  final String userName;
  final bool showBatting;
  final bool showBowling;
  final bool showCoaching;

  const _WelcomeGlassCard({
    required this.userName,
    required this.showBatting,
    required this.showBowling,
    required this.showCoaching,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.18),
                const Color(0xFF0D1A2E).withValues(alpha: 0.3),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7DD3FC).withValues(alpha: 0.12),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome to the Academy, $userName!",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Your journey from Gully to Global starts today.",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              _CalibrationRow(
                visible: showBatting,
                icon: Icons.sports_cricket_rounded,
                title: "Batting DNA",
                status: "Initializing... 100%",
                accent: const Color(0xFF7DD3FC),
              ),
              const SizedBox(height: 12),
              _CalibrationRow(
                visible: showBowling,
                icon: Icons.speed_rounded,
                title: "Bowling Speed",
                status: "Calibrating... 100%",
                accent: const Color(0xFF60A5FA),
              ),
              const SizedBox(height: 12),
              _CalibrationRow(
                visible: showCoaching,
                icon: Icons.psychology_alt_rounded,
                title: "AI Coaching",
                status: "Online.",
                accent: const Color(0xFF4ADE80),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalibrationRow extends StatelessWidget {
  final bool visible;
  final IconData icon;
  final String title;
  final String status;
  final Color accent;

  const _CalibrationRow({
    required this.visible,
    required this.icon,
    required this.title,
    required this.status,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0.08, 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: visible ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: accent),
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (visible) Icon(Icons.check_circle_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final double rotationTurns;

  const _RankBadge({required this.rotationTurns});

  @override
  Widget build(BuildContext context) {
    final pulse = 0.5 + (0.5 * math.sin(rotationTurns * math.pi * 2));
    final scale = 0.96 + (pulse * 0.08);

    return Transform.scale(
      scale: scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: rotationTurns * math.pi * 2,
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    const Color(0xFF67E8F9).withValues(alpha: 0.0),
                    const Color(0xFF67E8F9).withValues(alpha: 0.9),
                    const Color(0xFF4ADE80).withValues(alpha: 0.22),
                    const Color(0xFF67E8F9).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF7DD3FC,
                  ).withValues(alpha: 0.18 + (pulse * 0.18)),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ],
              gradient: const RadialGradient(
                colors: [Color(0xFF12314C), Color(0xFF09131F)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "ROOKIE",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFF7DD3FC),
                  size: 28,
                ),
                const SizedBox(height: 8),
                const Text(
                  "BEGINNER",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EnterFieldButton extends StatelessWidget {
  final double breathingValue;
  final VoidCallback onPressed;

  const _EnterFieldButton({
    required this.breathingValue,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = 0.5 + (0.5 * math.sin(breathingValue * math.pi * 2));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF22C55E,
            ).withValues(alpha: 0.18 + (pulse * 0.22)),
            blurRadius: 22 + (pulse * 16),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFF67E8F9), Color(0xFF22C55E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.stadium_rounded, color: Color(0xFF03120A)),
                SizedBox(width: 12),
                Text(
                  "ENTER THE FIELD",
                  style: TextStyle(
                    color: Color(0xFF03120A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StadiumSpotlightPainter extends CustomPainter {
  final double intensity;

  _StadiumSpotlightPainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final lampPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.54 + (intensity * 0.36));
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28)
      ..color = Colors.white.withValues(alpha: 0.08 + (intensity * 0.24));
    final conePaint = Paint();
    final lampY = size.height * 0.09;
    final coneLength = size.height * 0.42;

    for (int i = 0; i < 4; i++) {
      final dx = size.width * (0.16 + (i * 0.23));
      final lampCenter = Offset(dx, lampY);

      canvas.drawCircle(lampCenter, 15, glowPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: lampCenter, width: 24, height: 14),
          const Radius.circular(7),
        ),
        lampPaint,
      );

      conePaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.16 + (intensity * 0.22)),
          Colors.white.withValues(alpha: 0.06 + (intensity * 0.08)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(dx - 70, lampY, 140, coneLength));

      final conePath = Path()
        ..moveTo(dx - 10, lampY + 4)
        ..lineTo(dx + 10, lampY + 4)
        ..lineTo(dx + 78, lampY + coneLength)
        ..lineTo(dx - 78, lampY + coneLength)
        ..close();
      canvas.drawPath(conePath, conePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StadiumSpotlightPainter oldDelegate) {
    return oldDelegate.intensity != intensity;
  }
}