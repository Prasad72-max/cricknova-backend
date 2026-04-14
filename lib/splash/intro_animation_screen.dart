import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/login_screen.dart';

class IntroAnimationScreen extends StatefulWidget {
  const IntroAnimationScreen({super.key});

  @override
  State<IntroAnimationScreen> createState() => _IntroAnimationScreenState();
}

class _IntroAnimationScreenState extends State<IntroAnimationScreen>
    with TickerProviderStateMixin {
  static const int _slideCount = 5;
  static const Duration _slideDuration = Duration(milliseconds: 4200);

  late final AnimationController _progressController;
  late final AnimationController _ambientController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  int _index = 0;
  bool _paused = false;
  bool _textVisible = false;

  final List<_StorySlide> _slides = const [
    _StorySlide(
      title: "The Raw Reality",
      body:
          "Millions of dreams are born in narrow lanes, but they deserve the world’s biggest stages. CrickNova AI: Turning potential into performance, globally.",
      audioAsset: "audio/story_ambient_gully.wav",
      mood: _SlideMood.gully,
    ),
    _StorySlide(
      title: "The Missing Link",
      body:
          "Talent is everywhere, but professional coaching is expensive. We saw greatness getting lost in the crowd.",
      audioAsset: "audio/story_piano_chord.wav",
      mood: _SlideMood.missing,
    ),
    _StorySlide(
      title: "The AI Vision",
      body:
          "Precision in every pixel. Our AI tracks what the human eye misses.",
      audioAsset: "audio/story_digital_powerup.wav",
      mood: _SlideMood.aiVision,
    ),
    _StorySlide(
      title: "The Data Revolution",
      body: "Turn your sweat into data. Know your strengths, fix your flaws.",
      audioAsset: "audio/story_orchestral_swell.wav",
      mood: _SlideMood.dataRevolution,
    ),
    _StorySlide(
      title: "The Ultimate Goal",
      body: "The world is watching. Are you ready to lead the scoreboard?",
      audioAsset: "audio/story_orchestral_swell.wav",
      mood: _SlideMood.launch,
      cta: "LAUNCH CRICKNOVA",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _slideDuration,
    )..addStatusListener(_handleProgressStatus);
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _startSlide();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _ambientController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _handleProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_index < _slideCount - 1) {
      _goToSlide(_index + 1);
    } else {
      _progressController.stop();
    }
  }

  Future<void> _startSlide({bool haptic = true}) async {
    final int slideIndex = _index;
    _progressController.stop();
    _progressController.value = 0;
    _textVisible = false;
    setState(() {});
    await _playAudioForSlide(_index);
    if (haptic) {
      HapticFeedback.lightImpact();
    }
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _index != slideIndex) return;
      if (!_paused) {
        setState(() => _textVisible = true);
      }
    });
    if (!_paused) {
      _progressController.forward();
    }
  }

  Future<void> _playAudioForSlide(int index) async {
    try {
      await _audioPlayer.stop();
      if (index == 0) {
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.setVolume(0.35);
      } else {
        await _audioPlayer.setReleaseMode(ReleaseMode.stop);
        await _audioPlayer.setVolume(1.0);
      }
      await _audioPlayer.play(AssetSource(_slides[index].audioAsset));
    } catch (_) {}
  }

  void _goToSlide(int target) {
    if (target < 0 || target >= _slideCount) return;
    _index = target;
    _startSlide();
  }

  void _handleTapUp(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    if (details.localPosition.dx < width * 0.35) {
      _goToSlide(_index - 1);
    } else {
      if (_index < _slideCount - 1) {
        _goToSlide(_index + 1);
      }
    }
  }

  void _pauseStory() {
    if (_paused) return;
    _paused = true;
    _progressController.stop();
    _ambientController.stop();
    try {
      _audioPlayer.pause();
    } catch (_) {}
  }

  void _resumeStory() {
    if (!_paused) return;
    _paused = false;
    _ambientController.repeat();
    try {
      _audioPlayer.resume();
    } catch (_) {}
    if (!_textVisible) {
      setState(() => _textVisible = true);
    }
    if (_progressController.value < 1.0) {
      _progressController.forward();
    }
  }

  Future<void> _completeOnboarding() async {
    _progressController.stop();
    _ambientController.stop();
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("is_first_launch", false);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final textTopInset = math.max(120.0, viewportSize.height * 0.2);
            final ctaBottomInset = 50.0;
            final textBottomInset = slide.cta == null ? 104.0 : 156.0;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleTapUp,
              onLongPressStart: (_) => _pauseStory(),
              onLongPressEnd: (_) => _resumeStory(),
              child: ClipRect(
                child: SizedBox(
                  width: viewportSize.width,
                  height: viewportSize.height,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _progressController,
                      _ambientController,
                    ]),
                    builder: (context, _) {
                      final slideProgress = _progressController.value;
                      final ambientProgress = _ambientController.value;

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 500),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) {
                                final fade = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOut,
                                );
                                return FadeTransition(
                                  opacity: fade,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.98,
                                      end: 1.0,
                                    ).animate(fade),
                                    child: child,
                                  ),
                                );
                              },
                              child: _StoryBackdrop(
                                key: ValueKey(_index),
                                mood: slide.mood,
                                progress: slideProgress,
                                motion: ambientProgress,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 14,
                            left: 16,
                            right: 16,
                            child: Column(
                              children: [
                                _StoryProgressBar(
                                  count: _slideCount,
                                  currentIndex: _index,
                                  progress: slideProgress,
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _completeOnboarding,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                    ),
                                    child: const Text("Skip"),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                22,
                                textTopInset,
                                22,
                                textBottomInset,
                              ),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: viewportSize.width - 44,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AnimatedOpacity(
                                        opacity: _textVisible ? 1.0 : 0.0,
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        child: Text(
                                          slide.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      AnimatedOpacity(
                                        opacity: _textVisible ? 1.0 : 0.0,
                                        duration: const Duration(
                                          milliseconds: 360,
                                        ),
                                        child: Text(
                                          slide.body,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.78,
                                            ),
                                            fontSize: 15,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (slide.cta != null)
                            Positioned(
                              left: 22,
                              right: 22,
                              bottom: ctaBottomInset,
                              child: slide.mood == _SlideMood.launch
                                  ? _LaunchCtaButton(
                                      label: slide.cta!,
                                      motion: ambientProgress,
                                      onPressed: () {
                                        HapticFeedback.heavyImpact();
                                        _completeOnboarding();
                                      },
                                    )
                                  : ElevatedButton(
                                      onPressed: () {
                                        HapticFeedback.heavyImpact();
                                        _completeOnboarding();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF22C55E,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        slide.cta!,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StorySlide {
  final String title;
  final String body;
  final String audioAsset;
  final _SlideMood mood;
  final String? cta;

  const _StorySlide({
    required this.title,
    required this.body,
    required this.audioAsset,
    required this.mood,
    this.cta,
  });
}

enum _SlideMood { gully, missing, aiVision, dataRevolution, launch }

class _StoryProgressBar extends StatelessWidget {
  final int count;
  final int currentIndex;
  final double progress;

  const _StoryProgressBar({
    required this.count,
    required this.currentIndex,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (index) {
        final value = index < currentIndex
            ? 1.0
            : index == currentIndex
            ? progress
            : 0.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 3.5,
                color: Colors.white24,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(color: Colors.white),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _StoryBackdrop extends StatelessWidget {
  final _SlideMood mood;
  final double progress;
  final double motion;

  const _StoryBackdrop({
    super.key,
    required this.mood,
    required this.progress,
    required this.motion,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(gradient: _backgroundGradientForMood(mood)),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _StoryPainter(
              mood: mood,
              progress: progress,
              motion: motion,
            ),
          ),
        ),
        if (mood == _SlideMood.dataRevolution)
          Positioned.fill(
            child: _DataCardsScene(progress: progress, motion: motion),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.58),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.72),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryPainter extends CustomPainter {
  final _SlideMood mood;
  final double progress;
  final double motion;

  _StoryPainter({
    required this.mood,
    required this.progress,
    required this.motion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (mood) {
      case _SlideMood.gully:
        _drawGully(canvas, size);
        break;
      case _SlideMood.missing:
        _drawMissing(canvas, size);
        break;
      case _SlideMood.aiVision:
        _drawAiVision(canvas, size, motion);
        break;
      case _SlideMood.dataRevolution:
        _drawDataRevolution(canvas, size, progress, motion);
        break;
      case _SlideMood.launch:
        _drawLaunch(canvas, size, progress, motion);
        break;
    }
  }

  void _drawGully(Canvas canvas, Size size) {
    final lanePaint = Paint()
      ..color = const Color(0xFF8B5E34).withValues(alpha: 0.7)
      ..strokeWidth = 3;
    final laneBottom = size.height * 0.9;
    final laneTop = size.height * 0.45;
    canvas.drawLine(
      Offset(size.width * 0.2, laneBottom),
      Offset(size.width * 0.45, laneTop),
      lanePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.8, laneBottom),
      Offset(size.width * 0.55, laneTop),
      lanePaint,
    );
    final kidPaint = Paint()..color = const Color(0xFF111111);
    final center = Offset(size.width * 0.52, size.height * 0.65);
    canvas.drawCircle(center.translate(0, -60), 14, kidPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, -30),
          width: 26,
          height: 54,
        ),
        const Radius.circular(8),
      ),
      kidPaint,
    );
    final legPaint = Paint()..color = const Color(0xFF0A0A0A);
    canvas.drawRect(Rect.fromLTWH(center.dx - 16, center.dy, 12, 30), legPaint);
    canvas.drawRect(Rect.fromLTWH(center.dx + 4, center.dy, 12, 30), legPaint);
    final batPaint = Paint()
      ..color = const Color(0xFFC69C6D)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(10, -40),
      center.translate(52, -12),
      batPaint,
    );
  }

  void _drawMissing(Canvas canvas, Size size) {
    final paperPaint = Paint()
      ..color = const Color(0xFF1F2937).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCenter(
      center: Offset(size.width * 0.6, size.height * 0.45),
      width: 140,
      height: 190,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paperPaint,
    );
    final linePaint = Paint()
      ..color = const Color(0xFF6B7280)
      ..strokeWidth = 2;
    for (int i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(rect.left + 16, rect.top + 30 + (i * 28)),
        Offset(rect.right - 16, rect.top + 30 + (i * 28)),
        linePaint,
      );
    }
    final shoePaint = Paint()..color = const Color(0xFF2C2C2C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.25, size.height * 0.65, 80, 26),
        const Radius.circular(8),
      ),
      shoePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.35, size.height * 0.7, 80, 26),
        const Radius.circular(8),
      ),
      shoePaint,
    );
  }

  void _drawAiVision(Canvas canvas, Size size, double t) {
    final shortestSide = math.min(size.width, size.height);
    final pulse = 0.5 + (0.5 * math.sin(t * math.pi * 2));
    final center = Offset(size.width * 0.5, size.height * 0.35);
    final outerRadius = shortestSide * 0.28;
    final innerRadius = outerRadius * 0.72;
    final centerGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF38BDF8).withValues(alpha: 0.42 + (pulse * 0.16)),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: outerRadius * 1.1),
          );
    canvas.drawCircle(center, outerRadius * 1.1, centerGlow);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = const Color(0xFF6EE7F9).withValues(alpha: 0.8);
    canvas.drawCircle(center, outerRadius, ringPaint);
    canvas.drawCircle(
      center,
      innerRadius,
      ringPaint..color = const Color(0xFF38BDF8).withValues(alpha: 0.42),
    );

    final crosshairPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - outerRadius * 1.2, center.dy),
      Offset(center.dx + outerRadius * 1.2, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - outerRadius * 1.2),
      Offset(center.dx, center.dy + outerRadius * 1.2),
      crosshairPaint,
    );

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF7DD3FC).withValues(alpha: 0.95);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * math.pi * 2);
    final arcRect = Rect.fromCircle(
      center: Offset.zero,
      radius: outerRadius * 0.92,
    );
    canvas.drawArc(arcRect, -1.0, 1.25, false, arcPaint);
    canvas.drawArc(
      arcRect,
      1.7,
      0.9,
      false,
      arcPaint..color = const Color(0xFF22D3EE).withValues(alpha: 0.78),
    );
    canvas.restore();

    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: innerRadius));
    final scanY = center.dy - innerRadius + (innerRadius * 2 * t);
    canvas.save();
    canvas.clipPath(clipPath);
    final scanPaint = Paint()
      ..shader =
          LinearGradient(
            colors: [
              Colors.transparent,
              const Color(0xFF67E8F9).withValues(alpha: 0.0),
              const Color(0xFF67E8F9).withValues(alpha: 0.9),
              const Color(0xFF67E8F9).withValues(alpha: 0.0),
              Colors.transparent,
            ],
            stops: const [0.0, 0.36, 0.5, 0.64, 1.0],
          ).createShader(
            Rect.fromLTWH(
              center.dx - innerRadius,
              scanY - 16,
              innerRadius * 2,
              32,
            ),
          );
    canvas.drawRect(
      Rect.fromLTWH(center.dx - innerRadius, scanY - 16, innerRadius * 2, 32),
      scanPaint,
    );
    canvas.restore();

    final ballRadius = shortestSide * 0.085;
    final ballPaint = Paint()
      ..color = const Color(0xFF09111D)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, ballRadius, ballPaint);
    final seamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawArc(
      Rect.fromCircle(
        center: center.translate(-ballRadius * 0.16, 0),
        radius: ballRadius * 0.75,
      ),
      -1.2,
      2.4,
      false,
      seamPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: center.translate(ballRadius * 0.16, 0),
        radius: ballRadius * 0.75,
      ),
      1.9,
      2.4,
      false,
      seamPaint,
    );

    final drift = shortestSide * 0.02;
    _drawHudCallout(
      canvas,
      dot: center.translate(ballRadius * 0.4, -ballRadius * 0.7),
      labelTopLeft: Offset(
        center.dx + outerRadius * 0.44,
        center.dy - outerRadius * 0.54 + (math.sin(t * math.pi * 2) * drift),
      ),
      text: "X  12.4",
    );
    _drawHudCallout(
      canvas,
      dot: center.translate(-ballRadius * 0.7, 0),
      labelTopLeft: Offset(
        center.dx - outerRadius * 0.92,
        center.dy - 12 - (math.cos(t * math.pi * 2) * drift),
      ),
      text: "Y  -3.1",
    );
    _drawHudCallout(
      canvas,
      dot: center.translate(ballRadius * 0.2, ballRadius * 0.75),
      labelTopLeft: Offset(
        center.dx + outerRadius * 0.24,
        center.dy +
            outerRadius * 0.5 +
            (math.sin((t + 0.18) * math.pi * 2) * drift),
      ),
      text: "Z  08.9",
    );
  }

  void _drawDataRevolution(
    Canvas canvas,
    Size size,
    double progress,
    double t,
  ) {
    final shortestSide = math.min(size.width, size.height);
    final entry = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final beamPaint = Paint()
      ..color = const Color(0xFF67E8F9).withValues(alpha: 0.09 + (entry * 0.08))
      ..strokeWidth = 1.2;
    for (int i = 0; i < 6; i++) {
      final y = size.height * 0.14 + (i * size.height * 0.07);
      canvas.drawLine(
        Offset(size.width * 0.1, y),
        Offset(size.width * 0.9, y),
        beamPaint,
      );
    }

    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(
        0xFF22D3EE,
      ).withValues(alpha: 0.18 + (entry * 0.14));
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.47)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * (0.3 + (math.sin(t * math.pi * 2) * 0.03)),
        size.width * 0.56,
        size.height * 0.44,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.56,
        size.width * 0.9,
        size.height * 0.36,
      );
    canvas.drawPath(path, pathPaint);

    final nodePaint = Paint()
      ..color = const Color(0xFF7DD3FC).withValues(alpha: 0.82)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    for (final point in <Offset>[
      Offset(size.width * 0.18, size.height * 0.45),
      Offset(size.width * 0.44, size.height * 0.36),
      Offset(size.width * 0.62, size.height * 0.48),
      Offset(size.width * 0.84, size.height * 0.38),
    ]) {
      canvas.drawCircle(
        point.translate(0, math.sin((t + point.dx) * math.pi * 2) * 2),
        shortestSide * 0.014,
        nodePaint,
      );
    }
  }

  void _drawLaunch(Canvas canvas, Size size, double progress, double t) {
    final shortestSide = math.min(size.width, size.height);
    final zoom =
        1.0 + (Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0)) * 0.16);
    final shimmer = 0.5 + (0.5 * math.sin((t * math.pi * 2) + 0.6));
    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.44);
    canvas.scale(zoom);
    canvas.translate(-size.width * 0.5, -size.height * 0.44);

    final skyGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.4),
        radius: 0.95,
        colors: [
          const Color(0xFF1D4ED8).withValues(alpha: 0.34),
          const Color(0xFF0A1628).withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, skyGlow);

    final bowlPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = Colors.white.withValues(alpha: 0.08 + (shimmer * 0.04));
    for (int i = 0; i < 3; i++) {
      final rect = Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * (0.7 - (i * 0.06))),
        width: size.width * (0.96 - (i * 0.14)),
        height: size.height * (0.52 - (i * 0.1)),
      );
      canvas.drawArc(rect, math.pi * 0.17, math.pi * 0.66, false, bowlPaint);
    }

    final fieldRect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.82),
      width: size.width * 0.76,
      height: shortestSide * 0.3,
    );
    final fieldPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.15),
        radius: 0.92,
        colors: [
          const Color(0xFF4ADE80).withValues(alpha: 0.82),
          const Color(0xFF166534).withValues(alpha: 0.95),
        ],
      ).createShader(fieldRect);
    canvas.drawOval(fieldRect, fieldPaint);

    final lightGlowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    for (int i = 0; i < 8; i++) {
      final x = size.width * (0.12 + (i * 0.11));
      final y =
          size.height * (0.22 + (math.sin((t * math.pi * 2) + i) * 0.012));
      lightGlowPaint.color = Colors.white.withValues(
        alpha: 0.22 + (shimmer * 0.18),
      );
      canvas.drawCircle(Offset(x, y), shortestSide * 0.045, lightGlowPaint);
    }

    final scoreboardRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.28),
        width: math.min(size.width * 0.46, 220),
        height: shortestSide * 0.15,
      ),
      const Radius.circular(20),
    );
    final boardPaint = Paint()
      ..color = const Color(0xFF07111E).withValues(alpha: 0.82)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(scoreboardRect, boardPaint);
    canvas.drawRRect(
      scoreboardRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF7DD3FC).withValues(alpha: 0.34),
    );

    final barPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.72)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final boardWidth = scoreboardRect.outerRect.width;
    final boardLeft = scoreboardRect.outerRect.left + 22;
    final barTop = scoreboardRect.outerRect.top + 18;
    for (int i = 0; i < 4; i++) {
      final x = boardLeft + (i * ((boardWidth - 44) / 3));
      final barHeight =
          shortestSide * (0.018 + (i.isEven ? shimmer * 0.018 : 0.035));
      canvas.drawLine(
        Offset(x, barTop + 28),
        Offset(x, barTop + 28 - barHeight),
        barPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StoryPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.progress != progress ||
        oldDelegate.motion != motion;
  }
}

class _DataCardsScene extends StatelessWidget {
  final double progress;
  final double motion;

  const _DataCardsScene({required this.progress, required this.motion});

  @override
  Widget build(BuildContext context) {
    final entry = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final cardWidth = math.min(width * 0.44, 196.0);

          return Stack(
            children: [
              Positioned(
                left: width * 0.1,
                top: height * 0.17 + _floatOffset(motion, 0.0, 12),
                child: _DataStatCard(
                  width: cardWidth,
                  label: "SPEED",
                  value: "135 km/h",
                  accent: const Color(0xFF7DD3FC),
                  opacity: 0.62 + (entry * 0.38),
                  rotation: -0.03 + (math.sin(motion * math.pi * 2) * 0.012),
                ),
              ),
              Positioned(
                right: width * 0.08,
                top: height * 0.26 + _floatOffset(motion, 0.24, 16),
                child: _DataStatCard(
                  width: cardWidth * 0.94,
                  label: "SWING",
                  value: "3.2° late shape",
                  accent: const Color(0xFF67E8F9),
                  opacity: 0.58 + (entry * 0.42),
                  rotation: 0.035 + (math.cos(motion * math.pi * 2) * 0.012),
                ),
              ),
              Positioned(
                left: width * 0.18,
                top: height * 0.41 + _floatOffset(motion, 0.52, 14),
                child: _DataStatCard(
                  width: cardWidth * 1.08,
                  label: "LINE",
                  value: "Good Length",
                  accent: const Color(0xFF34D399),
                  opacity: 0.55 + (entry * 0.45),
                  rotation:
                      -0.015 + (math.sin((motion + 0.15) * math.pi * 2) * 0.01),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _floatOffset(double progress, double phase, double amplitude) {
    return math.sin((progress + phase) * math.pi * 2) * amplitude;
  }
}

class _DataStatCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final Color accent;
  final double opacity;
  final double rotation;

  const _DataStatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.accent,
    required this.opacity,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: rotation,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF102336).withValues(alpha: 0.9),
                const Color(0xFF0A1625).withValues(alpha: 0.78),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: accent.withValues(alpha: 0.36)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.14),
                blurRadius: 26,
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
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.15),
                        accent.withValues(alpha: 0.9),
                      ],
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

class _LaunchCtaButton extends StatelessWidget {
  final String label;
  final double motion;
  final VoidCallback onPressed;

  const _LaunchCtaButton({
    required this.label,
    required this.motion,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = 0.5 + (0.5 * math.sin(motion * math.pi * 2));
    final scale = 0.98 + (pulse * 0.035);
    final glow = 16.0 + (pulse * 18.0);

    return Transform.scale(
      scale: scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF22C55E,
              ).withValues(alpha: 0.26 + (pulse * 0.2)),
              blurRadius: glow,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF67E8F9), Color(0xFF22C55E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.rocket_launch_rounded,
                    color: Color(0xFF03130A),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF03130A),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

LinearGradient _backgroundGradientForMood(_SlideMood mood) {
  switch (mood) {
    case _SlideMood.gully:
      return const LinearGradient(
        colors: [Color(0xFF2B1B10), Color(0xFF0F0A06)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    case _SlideMood.missing:
      return const LinearGradient(
        colors: [Color(0xFF111827), Color(0xFF0F172A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    case _SlideMood.aiVision:
      return const LinearGradient(
        colors: [Color(0xFF030914), Color(0xFF07192A), Color(0xFF02070F)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    case _SlideMood.dataRevolution:
      return const LinearGradient(
        colors: [Color(0xFF04111D), Color(0xFF0A2237), Color(0xFF03101A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    case _SlideMood.launch:
      return const LinearGradient(
        colors: [Color(0xFF031018), Color(0xFF0A2232), Color(0xFF020A11)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
  }
}

void _drawHudCallout(
  Canvas canvas, {
  required Offset dot,
  required Offset labelTopLeft,
  required String text,
}) {
  const accent = Color(0xFF67E8F9);
  final linePaint = Paint()
    ..color = accent.withValues(alpha: 0.7)
    ..strokeWidth = 1.3;
  final dotPaint = Paint()..color = accent;
  canvas.drawCircle(dot, 3.2, dotPaint);
  final elbow = Offset(labelTopLeft.dx - 10, dot.dy);
  canvas.drawLine(dot, elbow, linePaint);
  canvas.drawLine(
    elbow,
    Offset(labelTopLeft.dx, labelTopLeft.dy + 12),
    linePaint,
  );

  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.86),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final boxRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(
      labelTopLeft.dx,
      labelTopLeft.dy,
      painter.width + 14,
      painter.height + 10,
    ),
    const Radius.circular(12),
  );
  canvas.drawRRect(
    boxRect,
    Paint()..color = const Color(0xFF071522).withValues(alpha: 0.84),
  );
  canvas.drawRRect(
    boxRect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: 0.34),
  );
  painter.paint(canvas, Offset(labelTopLeft.dx + 7, labelTopLeft.dy + 5));
}
