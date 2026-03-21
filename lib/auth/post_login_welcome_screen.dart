import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
  bool _isReady = false;
  bool _videoMissing = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _setupVideo();
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

  Future<void> _showWelcomePopup() async {
    if (!mounted) return;

    await _videoController?.pause();
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Welcome',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.86,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x50000000),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.celebration_rounded,
                    color: Color(0xFFFACC15),
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Welcome to CrickNova',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hi ${widget.userName}, your cricket AI journey starts now.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFACC15),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Start',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );

    _enterApp();
  }

  void _enterApp() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigation(userName: widget.userName),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoProgress);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
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
