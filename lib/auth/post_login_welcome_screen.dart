import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../navigation/main_navigation.dart';

class PostLoginWelcomeScreen extends StatefulWidget {
  final String userName;
  final bool showSkip;

  const PostLoginWelcomeScreen({
    super.key,
    required this.userName,
    this.showSkip = false,
  });

  static String _seenKey(String userId) => 'new_user_field_intro_seen_$userId';
  static const String _installIntroPendingKey = 'install_intro_pending';

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

  static Future<({bool shouldShow, bool showSkip})> shouldShowFor({
    required SharedPreferences prefs,
    required User user,
    bool? explicitIsNewUser,
  }) async {
    final seen = prefs.getBool(_seenKey(user.uid)) ?? false;
    final isNewUser = isEligibleNewUser(
      user,
      explicitIsNewUser: explicitIsNewUser,
    );
    final isFreshInstall = prefs.getBool(_installIntroPendingKey) ?? true;

    if (seen) {
      return (shouldShow: false, showSkip: false);
    }

    final shouldShow = isNewUser || isFreshInstall;
    final showSkip = !isNewUser;
    return (shouldShow: shouldShow, showSkip: showSkip);
  }

  static Future<void> markSeen(SharedPreferences prefs, String userId) async {
    await prefs.setBool(_seenKey(userId), true);
    await prefs.setBool(_installIntroPendingKey, false);
  }

  @override
  State<PostLoginWelcomeScreen> createState() => _PostLoginWelcomeScreenState();
}

class _PostLoginWelcomeScreenState extends State<PostLoginWelcomeScreen> {
  VideoPlayerController? _videoController;
  final TextEditingController _nicknameController = TextEditingController();
  bool _isReady = false;
  bool _videoMissing = false;
  bool _completed = false;
  bool _enteringApp = false;
  bool _identityComplete = false;
  String _resolvedUserName = "Player";

  @override
  void initState() {
    super.initState();
    _resolvedUserName = _defaultFirstName(widget.userName);
    _nicknameController.text = _resolvedUserName;
  }

  String _defaultFirstName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return "Player";
    return trimmed.split(RegExp(r'\s+')).first;
  }

  Future<void> _setupVideo() async {
    final controller = await _buildVideoController();
    if (!mounted) {
      await controller?.dispose();
      return;
    }

    if (controller == null) {
      setState(() {
        _videoMissing = true;
        _isReady = true;
      });
      await _showWelcomePopup();
      return;
    }

    _videoController = controller;
    _videoController!.addListener(_onVideoProgress);

    setState(() {
      _isReady = true;
    });

    await _videoController!.play();
  }

  Future<VideoPlayerController?> _buildVideoController() async {
    const candidates = <String>['assets/sign_in.mp4', 'asset/sign_in.mp4'];

    for (final assetPath in candidates) {
      final controller = VideoPlayerController.asset(assetPath);
      try {
        await controller.initialize();
        controller.setLooping(false);
        return controller;
      } catch (_) {
        await controller.dispose();
      }
    }

    return null;
  }

  void _onVideoProgress() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized || _completed) {
      return;
    }

    final position = controller.value.position;
    final duration = controller.value.duration;

    if (duration > Duration.zero && position >= duration) {
      _completed = true;
      _showWelcomePopup();
    }
  }

  Future<void> _saveNicknameAndContinue() async {
    final nickname = _nicknameController.text.trim().isEmpty
        ? _defaultFirstName(widget.userName)
        : _nicknameController.text.trim();

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final prefs = await SharedPreferences.getInstance();
    final box = await Hive.openBox("local_stats_$uid");
    await box.put("profileName", nickname);
    await prefs.setString("profileName", nickname);
    await prefs.setString("userName", nickname);

    if (!mounted) return;
    setState(() {
      _resolvedUserName = nickname;
      _identityComplete = true;
      _isReady = false;
      _videoMissing = false;
    });
    await _setupVideo();
  }

  Future<void> _showWelcomePopup() async {
    if (!mounted) return;

    await _videoController?.pause();
    if (!mounted) return;
    HapticFeedback.selectionClick();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Welcome',
      barrierColor: Colors.black.withValues(alpha: 0.82),
      transitionDuration: const Duration(milliseconds: 650),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _EliteOnboardingWelcomeDialog(userName: _resolvedUserName);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved), child: child),
          ),
        );
      },
    );

    await _releaseIntroVideo();
    await _enterApp();
  }

  Future<void> _releaseIntroVideo() async {
    final controller = _videoController;
    if (controller == null) return;
    controller.removeListener(_onVideoProgress);
    _videoController = null;
    try {
      await controller.pause();
    } catch (_) {}
    await controller.dispose();
    if (!mounted) return;
    setState(() {
      _videoMissing = true;
    });
  }

  Future<void> _enterApp() async {
    if (!mounted) return;
    setState(() {
      _enteringApp = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, animation, secondaryAnimation) =>
            MainNavigation(userName: _resolvedUserName),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _videoController?.removeListener(_onVideoProgress);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;

    if (_enteringApp) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: !_identityComplete
            ? _buildIdentitySetup()
            : Stack(
                children: [
                  Positioned.fill(
                    child: _isReady
                        ? _buildBody(controller)
                        : const Center(child: CircularProgressIndicator()),
                  ),
                  if (_isReady && !_videoMissing && widget.showSkip)
                    Positioned(
                      top: 8,
                      right: 12,
                      child: TextButton(
                        onPressed: () {
                          if (_completed) return;
                          _completed = true;
                          _showWelcomePopup();
                        },
                        child: const Text(
                          'Skip',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildIdentitySetup() {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final hasName = _nicknameController.text.trim().isNotEmpty;
        return Container(
          color: const Color(0xFF000000),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What should we call you on the field?',
                    style: TextStyle(
                      color: Color(0xFFF5FAFF),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 34),
                  TextField(
                    controller: _nicknameController,
                    autofocus: true,
                    style: TextStyle(
                      color: const Color(0xFFF7E7CE),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      shadows: hasName
                          ? [
                              Shadow(
                                color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
                                blurRadius: 14,
                              ),
                            ]
                          : null,
                    ),
                    cursorColor: const Color(0xFFD4AF37),
                    decoration: const InputDecoration(
                      hintText: 'Enter your Nickname (e.g., Champ, Captain, Smithy)',
                      hintStyle: TextStyle(
                        color: Color(0xFF7E8995),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0x44D4AF37), width: 1.2),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                      ),
                    ),
                    onChanged: (_) => setLocalState(() {}),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (_nicknameController.text.trim().isEmpty) return;
                      _saveNicknameAndContinue();
                    },
                  ),
                  const SizedBox(height: 26),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedOpacity(
                      opacity: hasName ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 180),
                      child: TextButton(
                        onPressed: hasName ? _saveNicknameAndContinue : null,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          backgroundColor: hasName
                              ? const Color(0x18D4AF37)
                              : Colors.white.withValues(alpha: 0.03),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(
                              color: hasName
                                  ? const Color(0x66D4AF37)
                                  : Colors.white10,
                            ),
                          ),
                        ),
                        child: Text(
                          'Continue',
                          style: TextStyle(
                            color: hasName
                                ? const Color(0xFFF7E7CE)
                                : const Color(0xFF89929C),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
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

  Widget _buildBody(VideoPlayerController? controller) {
    if (_videoMissing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Intro video not found. Continuing...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _EliteOnboardingWelcomeDialog extends StatefulWidget {
  final String userName;

  const _EliteOnboardingWelcomeDialog({required this.userName});

  @override
  State<_EliteOnboardingWelcomeDialog> createState() =>
      _EliteOnboardingWelcomeDialogState();
}

class _EliteOnboardingWelcomeDialogState
    extends State<_EliteOnboardingWelcomeDialog>
    with TickerProviderStateMixin {
  late final AnimationController _masterController;
  late final AnimationController _pulseController;
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _masterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _masterController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  double _segment(double start, double end) {
    return ((_masterController.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.userName.trim().isEmpty ? 'Player' : widget.userName.trim();

    return AnimatedBuilder(
      animation: Listenable.merge([
        _masterController,
        _pulseController,
        _floatController,
      ]),
      builder: (context, _) {
        final breathe = 0.86 + (_pulseController.value * 0.18);
        final floatDy = (_floatController.value - 0.5) * 8;
        final logoReveal = Curves.easeOutCubic.transform(_segment(0.18, 0.40));
        final titleReveal = Curves.easeOutCubic.transform(_segment(0.38, 0.62));
        final nameReveal = Curves.easeOutCubic.transform(_segment(0.58, 0.80));
        final subtitleReveal = Curves.easeOutCubic.transform(_segment(0.78, 0.96));

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: const Color(0xFF0A0B0D).withValues(alpha: 0.88)),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _LuxuryParticlePainter(progress: _floatController.value),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: 420,
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          const Color(0xFF12161C).withValues(alpha: 0.96),
                          const Color(0xFF0B0E11).withValues(alpha: 0.98),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.10),
                          blurRadius: 36,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.46),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _LuxurySweepPainter(
                                progress: _masterController.value,
                              ),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),
                            Transform.translate(
                              offset: Offset(0, floatDy),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 112 * breathe,
                                    height: 112 * breathe,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          const Color(0xFFF7E7CE).withValues(alpha: 0.18),
                                          const Color(0xFFD4AF37).withValues(alpha: 0.08),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Opacity(
                                    opacity: logoReveal,
                                    child: ShaderMask(
                                      shaderCallback: (bounds) {
                                        return const LinearGradient(
                                          colors: [Color(0xFFD4AF37), Color(0xFFF7E7CE)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ).createShader(bounds);
                                      },
                                      child: const Text(
                                        'CN',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 42,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Opacity(
                              opacity: titleReveal,
                              child: Transform.translate(
                                offset: Offset(20 * (1 - titleReveal), 0),
                                child: const Text(
                                  'Welcome to the Elite,',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFFF4EFE7),
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Opacity(
                              opacity: nameReveal,
                              child: Text(
                                name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFFF8FCFF),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFFD4AF37).withValues(alpha: 0.12 * breathe),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Opacity(
                              opacity: subtitleReveal,
                              child: const Text(
                                'Your journey to the legendary status begins here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFB9C0C9),
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  HapticFeedback.mediumImpact();
                                  Navigator.of(context).pop();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.zero,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFE4C46A), Color(0xFFB98A22)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                                        blurRadius: 18,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    child: Center(
                                      child: Text(
                                        'Enter CrickNova',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
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
            ],
          ),
        );
      },
    );
  }
}

class _LuxuryParticlePainter extends CustomPainter {
  final double progress;

  _LuxuryParticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final points = [
      Offset(size.width * 0.18, size.height * 0.22),
      Offset(size.width * 0.78, size.height * 0.18),
      Offset(size.width * 0.22, size.height * 0.78),
      Offset(size.width * 0.82, size.height * 0.72),
      Offset(size.width * 0.52, size.height * 0.16),
      Offset(size.width * 0.60, size.height * 0.84),
    ];

    for (var i = 0; i < points.length; i++) {
      final drift = ((progress + (i * 0.13)) % 1.0) - 0.5;
      paint.color = const Color(0xFFF7E7CE).withValues(
        alpha: i.isEven ? 0.14 : 0.08,
      );
      canvas.drawCircle(points[i] + Offset(0, drift * 18), i.isEven ? 2.0 : 1.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LuxuryParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _LuxurySweepPainter extends CustomPainter {
  final double progress;

  _LuxurySweepPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final sweep = Rect.fromLTWH(
      (size.width + 120) * progress - 120,
      0,
      84,
      size.height,
    );
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x00FFFFFF),
          Color(0x22F7E7CE),
          Color(0x00FFFFFF),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(sweep);
    canvas.save();
    canvas.rotate(-0.14);
    canvas.drawRect(sweep.shift(const Offset(0, -20)), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LuxurySweepPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
