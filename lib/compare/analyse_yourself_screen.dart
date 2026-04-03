import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import 'package:hive/hive.dart';
import '../services/weekly_stats_service.dart';
import '../ai/elite_coach_prompt.dart';

class AnalyseYourselfScreen extends StatefulWidget {
  const AnalyseYourselfScreen({super.key});

  @override
  State<AnalyseYourselfScreen> createState() => _AnalyseYourselfScreenState();
}

class _AnalyseYourselfScreenState extends State<AnalyseYourselfScreen>
    with TickerProviderStateMixin {
  File? leftVideo;
  File? rightVideo;

  VideoPlayerController? leftController;
  VideoPlayerController? rightController;

  final ImagePicker picker = ImagePicker();

  bool _pickingLeft = false;
  bool _pickingRight = false;

  bool comparing = false;
  String? diffResult;

  bool isSynced = false;
  int _currentFactIndex = 0;
  late List<String> cricketFacts;
  Timer? _factTimer;
  late final AnimationController _vsPulseController;
  late final AnimationController _shimmerController;
  bool _redirected = false;

  String _formatCompareReply(String raw) {
    final cleaned = raw.replaceAll('\r', '').trim();
    final lines = cleaned
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final limitedLines = lines.take(6).toList();
    final compact = (limitedLines.isNotEmpty ? limitedLines : [cleaned]).join('\n');
    final words = compact.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 280) return compact;
    return '${words.take(280).join(' ')}...';
  }

  @override
  void initState() {
    super.initState();
    // 🔥 Ensure premium state is loaded before using limits
    Future.microtask(() async {
      await PremiumService.restoreOnLaunch();
      if (mounted) setState(() {});
    });
    cricketFacts = [
      "Did you know? The first international cricket match was USA vs Canada in 1844.",
      "Elite Tip: A stable head position improves shot timing drastically.",
      "Fun Fact: Sachin Tendulkar used one of the heaviest bats in cricket.",
      "Did you know? The fastest recorded delivery is over 161 km/h.",
      "Elite Tip: Balance at release defines bowling accuracy.",
      // Add your full 50 facts list here
    ];

    _vsPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  Future<void> pickVideo({required bool isLeft}) async {
    try {
      if (isLeft) {
        if (_pickingLeft) return;
        _pickingLeft = true;
      } else {
        if (_pickingRight) return;
        _pickingRight = true;
      }

      final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;

      final File file = File(picked.path);

      if (isLeft) {
        leftController?.dispose();
        leftController = VideoPlayerController.file(file)
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {});
            leftController?.play();
          });
        leftVideo = file;
      } else {
        rightController?.dispose();
        rightController = VideoPlayerController.file(file)
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {});
            rightController?.play();
          });
        rightVideo = file;
      }

      if (!mounted) return;
      setState(() {});
    } finally {
      if (isLeft) {
        _pickingLeft = false;
      } else {
        _pickingRight = false;
      }
    }
  }

  void _startPick(bool isLeft) {
    if ((isLeft && _pickingLeft) || (!isLeft && _pickingRight)) return;
    // Open gallery immediately (no UI changes).
    pickVideo(isLeft: isLeft);
  }

  Future<void> runCompare() async {
    // 🔒 Locked users see blur CTA (no popup/snackbar).
    if (!PremiumService.isLoaded ||
        !PremiumService.isPremium ||
        (PremiumService.plan != "IN_499" && PremiumService.plan != "IN_1999")) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PremiumScreen(entrySource: "compare_lock"),
        ),
      );
      return;
    }

    final remaining = await PremiumService.getCompareLimit();
    if (remaining <= 0) {
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF020617),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "🚀 Analyse Limit Reached",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "You've used all your Analyse Yourself attempts.\n\nUnlock advanced comparison again with ₹499 or ₹1999 plans.",
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Later",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const PremiumScreen(entrySource: "compare_limit"),
                  ),
                );
              },
              child: const Text(
                "Upgrade Now",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

      return;
    }

    if (leftVideo == null || rightVideo == null) return;

    setState(() {
      comparing = true;
      diffResult = null;
    });
    _factTimer?.cancel();
    _factTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      setState(() {
        _currentFactIndex = (_currentFactIndex + 1) % cricketFacts.length;
      });
    });

    final uri = Uri.parse("https://cricknova-backend.onrender.com/coach/diff");
    final request = http.MultipartRequest("POST", uri);
    request.headers["Accept"] = "application/json";

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        diffResult = "User not logged in. Please reopen the app.";
      });
      comparing = false;
      return;
    }

    final String? idToken = await user.getIdToken(true);

    if (idToken == null || idToken.isEmpty) {
      setState(() {
        diffResult = "Session expired. Please log in again.";
        comparing = false;
      });
      return;
    }

    // Canonical Authorization header
    request.headers["Authorization"] = "Bearer $idToken";
    if (PremiumService.isElite) {
      request.headers["X-Priority"] = "elite";
      request.headers["X-Speed"] = "2x";
    }

    request.files.add(
      await http.MultipartFile.fromPath("left", leftVideo!.path),
    );
    request.files.add(
      await http.MultipartFile.fromPath("right", rightVideo!.path),
    );
    request.fields["prompt"] = EliteCoachPrompt.forComparison();

    try {
      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);

        setState(() {
          diffResult = _formatCompareReply(
            (data["difference"] ?? "No difference returned.").toString(),
          );
        });
        try {
          await WeeklyStatsService.recordAnalyseAi(user.uid);
        } catch (_) {}
        // 🎯 XP update → Always stored locally in Hive
        final uid = user.uid;
        final box = await Hive.openBox("local_stats_$uid");

        int currentXp = box.get('xp', defaultValue: 0);
        int newXp = currentXp + 40; // Compare XP reward

        await box.put('xp', newXp);

        debugPrint("🔥 HIVE XP UPDATED (COMPARE) → $newXp");

        await PremiumService.consumeCompare();
        try {
          final usage = await PremiumService.fetchMonthlyUsage();
          await _maybeShowCompareLimitReached(usage.swingUsed);
        } catch (e) {
          debugPrint("USAGE TRACK ERROR (COMPARE) => $e");
        }
      } else if (response.statusCode == 401) {
        setState(() {
          diffResult = "Session expired. Please log in again.";
        });
      } else if (response.statusCode == 403) {
        try {
          final data = jsonDecode(body);
          final detail = data["detail"]?.toString() ?? "";

          if (detail == "COMPARE_LIMIT_REACHED" ||
              detail == "PREMIUM_EXPIRED") {
            if (!mounted) return;

            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF020617),
                title: const Text(
                  "Analyse Limit Reached",
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  "Your Analyse Yourself limit has ended.\n\nUpgrade to ₹499 or ₹1999 to continue.",
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Upgrade",
                      style: TextStyle(color: Color(0xFF38BDF8)),
                    ),
                  ),
                ],
              ),
            );

            if (!mounted) return;

            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const PremiumScreen(entrySource: "compare_limit"),
              ),
            );
            return;
          }
        } catch (_) {}

        setState(() {
          diffResult = "Access denied.";
        });
      } else {
        final data = jsonDecode(body);
        setState(() {
          diffResult =
              data["detail"] ?? data["difference"] ?? "Compare failed.";
        });
      }
    } catch (e) {
      setState(() {
        diffResult = "Compare failed. Connection error: $e";
      });
      // XP block must not be inside catch
    } finally {
      _factTimer?.cancel();
      setState(() {
        comparing = false;
      });
    }
  }

  Future<void> _maybeShowCompareLimitReached(int current) async {
    if (!mounted) return;
    final limit = PremiumService.compareLimit;
    if (!PremiumService.isPremium || limit <= 0) return;
    if (current < limit || (current - 1) >= limit) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF020617),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Analyse Limit Reached",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "You've reached your monthly Analyse Yourself limit.\n\nUpgrade to keep comparing your technique.",
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const PremiumScreen(entrySource: "compare_limit"),
                ),
              );
            },
            child: const Text(
              "Upgrade Now",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget safeVideo(VideoPlayerController controller) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  @override
  void dispose() {
    leftController?.dispose();
    rightController?.dispose();
    _factTimer?.cancel();
    _vsPulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canCompare = leftVideo != null && rightVideo != null;
    final bool locked =
        !PremiumService.isLoaded ||
        !PremiumService.isPremium ||
        (PremiumService.plan != "IN_499" && PremiumService.plan != "IN_1999");

    if (locked && !_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const PremiumScreen(entrySource: "analyse"),
          ),
        );
      });
    }

    void toggleSync() {
      if (leftController == null || rightController == null) return;
      setState(() {
        isSynced = !isSynced;
      });
      if (isSynced) {
        leftController!.seekTo(Duration.zero);
        rightController!.seekTo(Duration.zero);
        leftController!.play();
        rightController!.play();
      } else {
        leftController!.pause();
        rightController!.pause();
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E11),
        title: const Text('Analyse Yourself'),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0B0E11), Color(0xFF060A12)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                lineColor: Colors.white.withOpacity(0.05),
                majorLineColor: Colors.white.withOpacity(0.07),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(child: videoCard(isLeft: true)),
                        const SizedBox(width: 16),
                        Expanded(child: videoCard(isLeft: false)),
                      ],
                    ),
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _vsPulseController,
                        _shimmerController,
                      ]),
                      builder: (context, _) {
                        return Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _LaserPainter(
                                enabled: canCompare,
                                t: _shimmerController.value,
                                glow: _vsPulseController.value,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    AnimatedBuilder(
                      animation: _vsPulseController,
                      builder: (context, _) {
                        final pulse = 0.95 + (0.10 * _vsPulseController.value);
                        return Transform.scale(
                          scale: pulse,
                          child: _NeonVsBadge(intensity: pulse),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                _ShimmerCompareButton(
                  enabled: canCompare && !locked,
                  shimmer: _shimmerController,
                  onTap: runCompare,
                ),
                const SizedBox(height: 18),

                if (leftController != null && rightController != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Center(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSynced
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: toggleSync,
                        child: Text(
                          isSynced ? "SYNC ON" : "SYNC PLAY",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                if (comparing)
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      children: [
                        const LinearProgressIndicator(minHeight: 3),
                        const SizedBox(height: 16),
                        const Text(
                          "AI is matching frames to find technique differences...",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          child: Text(
                            cricketFacts[_currentFactIndex],
                            key: ValueKey(_currentFactIndex),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (diffResult != null)
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF38BDF8),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.smart_toy_outlined,
                          color: Color(0xFF38BDF8),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Difference: ${diffResult!}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget videoCard({required bool isLeft}) {
    final VideoPlayerController? controller = isLeft
        ? leftController
        : rightController;
    final bool hasVideo = controller != null && controller.value.isInitialized;

    return GestureDetector(
      onTapDown: (_) => _startPick(isLeft),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.10),
                  blurRadius: 22,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!hasVideo)
                  Opacity(
                    opacity: 0.22,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Image.asset(
                        "assets/images/pitch.png",
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                if (controller != null && controller.value.isInitialized)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: VideoPlayer(controller),
                  ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                    ),
                    child: Text(
                      isLeft ? "VIDEO A" : "VIDEO B",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    opacity: hasVideo ? 0.0 : 1.0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.add_circle_outline,
                          color: Colors.white70,
                          size: 42,
                        ),
                        SizedBox(height: 10),
                        Text(
                          "Add Video",
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.video_call_outlined,
                          color: Color(0xFF38BDF8),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Add",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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

class _NeonVsBadge extends StatelessWidget {
  final double intensity;
  const _NeonVsBadge({required this.intensity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withOpacity(0.35 * intensity),
            blurRadius: 22,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.30 * intensity),
            blurRadius: 26,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0B0E11).withOpacity(0.65),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          alignment: Alignment.center,
          child: const Text(
            "VS",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerCompareButton extends StatelessWidget {
  final bool enabled;
  final AnimationController shimmer;
  final VoidCallback onTap;

  const _ShimmerCompareButton({
    required this.enabled,
    required this.shimmer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Container(
              height: 58,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: enabled
                      ? const [Color(0xFF8B5CF6), Color(0xFF22D3EE)]
                      : [
                          const Color(0xFF8B5CF6).withOpacity(0.35),
                          const Color(0xFF22D3EE).withOpacity(0.25),
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22D3EE).withOpacity(0.22),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.22),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                "COMPARE ANALYSIS",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  fontSize: 16,
                ),
              ),
            ),
            if (enabled)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: shimmer,
                  builder: (context, _) {
                    return FractionallySizedBox(
                      widthFactor: 0.28,
                      alignment: Alignment(-1 + (2 * shimmer.value), 0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.white.withOpacity(0.55),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color lineColor;
  final Color majorLineColor;

  const _GridPainter({required this.lineColor, required this.majorLineColor});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 22.0;
    const majorEvery = 4;

    for (int i = 0; i <= (size.width / gap).ceil(); i++) {
      final x = i * gap;
      final paint = Paint()
        ..color = (i % majorEvery == 0) ? majorLineColor : lineColor
        ..strokeWidth = (i % majorEvery == 0) ? 1.0 : 0.6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (int i = 0; i <= (size.height / gap).ceil(); i++) {
      final y = i * gap;
      final paint = Paint()
        ..color = (i % majorEvery == 0) ? majorLineColor : lineColor
        ..strokeWidth = (i % majorEvery == 0) ? 1.0 : 0.6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.majorLineColor != majorLineColor;
  }
}

class _LaserPainter extends CustomPainter {
  final bool enabled;
  final double t;
  final double glow;

  const _LaserPainter({
    required this.enabled,
    required this.t,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;

    final center = Offset(size.width / 2, 110);
    final leftTarget = Offset(size.width * 0.25, 110);
    final rightTarget = Offset(size.width * 0.75, 110);

    final baseWidth = 1.6 + (1.2 * glow);
    final paint = Paint()
      ..strokeWidth = baseWidth
      ..style = PaintingStyle.stroke
      ..shader = const LinearGradient(
        colors: [Color(0xFF22D3EE), Color(0xFF60A5FA), Color(0xFF8B5CF6)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final pulsePaint = Paint()
      ..strokeWidth = baseWidth + 2.2
      ..color = const Color(0xFF38BDF8).withOpacity(0.12 + (0.10 * glow))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawLine(center, leftTarget, pulsePaint);
    canvas.drawLine(center, rightTarget, pulsePaint);

    canvas.drawLine(center, leftTarget, paint);
    canvas.drawLine(center, rightTarget, paint);

    // Moving highlight dot.
    final dotXLeft = center.dx + (leftTarget.dx - center.dx) * t;
    final dotXRight = center.dx + (rightTarget.dx - center.dx) * t;
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(dotXLeft, center.dy), 2.6, dotPaint);
    canvas.drawCircle(Offset(dotXRight, center.dy), 2.6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _LaserPainter oldDelegate) {
    return oldDelegate.enabled != enabled ||
        oldDelegate.t != t ||
        oldDelegate.glow != glow;
  }
}
