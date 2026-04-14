import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import 'package:hive/hive.dart';
import '../services/weekly_stats_service.dart';

class AnalyseYourselfScreen extends StatefulWidget {
  final bool bowlingMode;

  const AnalyseYourselfScreen({super.key, this.bowlingMode = false});

  @override
  State<AnalyseYourselfScreen> createState() => _AnalyseYourselfScreenState();
}

class _AnalyseYourselfScreenState extends State<AnalyseYourselfScreen>
    with TickerProviderStateMixin {
  bool get _isBowlingMode => widget.bowlingMode;
  String get _analysisDiscipline => _isBowlingMode ? "bowling" : "batting";

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
    final compact = (lines.isNotEmpty ? lines : [cleaned]).join('\n');
    final words = compact
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length <= 700) return compact;
    return '${words.take(700).join(' ')}...';
  }

  _ParsedCompareReply _parseCompareReply(String raw) {
    final cleaned = raw.replaceAll('\r', '').trim();
    if (cleaned.isEmpty) return const _ParsedCompareReply.empty();

    final lines = cleaned.split('\n').map((l) => l.trim()).toList();
    String section = '';
    final v1 = _CompareVideoSummaryBuilder();
    final v2 = _CompareVideoSummaryBuilder();
    final drills = <String>[];

    bool isHeader(String l) {
      final s = l.toLowerCase();
      return s.startsWith('[video 1') ||
          s.startsWith('video 1') ||
          s.startsWith('[video1') ||
          s.startsWith('video1') ||
          s.startsWith('[video 2') ||
          s.startsWith('video 2') ||
          s.startsWith('[video2') ||
          s.startsWith('video2') ||
          s.startsWith('[drill 1') ||
          s.startsWith('drill 1') ||
          s.startsWith('[drill 2') ||
          s.startsWith('drill 2') ||
          s.startsWith('drills');
    }

    String headerKey(String l) {
      final s = l.toLowerCase();
      if (s.contains('video') && s.contains('1')) return 'v1';
      if (s.contains('video') && s.contains('2')) return 'v2';
      if (s.contains('drill')) return 'drill';
      return '';
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (isHeader(line)) {
        section = headerKey(line);
        continue;
      }

      // Strip common bullets/numbering for a cleaner card layout.
      final normalized = line.replaceFirst(RegExp(r'^\s*[-•]\s*'), '');
      final normalized2 = normalized.replaceFirst(
        RegExp(r'^\s*\d+[\).\]]\s*'),
        '',
      );

      if (section == 'v1') {
        v1.addLine(normalized2);
      } else if (section == 'v2') {
        v2.addLine(normalized2);
      } else if (section == 'drill') {
        drills.add(normalized2);
      }
    }

    // If the model ignored headers, fall back to the compact string.
    if (!v1.hasAny && !v2.hasAny && drills.isEmpty) {
      return _ParsedCompareReply.fallback(_formatCompareReply(cleaned));
    }

    // Keep it short and scannable.
    return _ParsedCompareReply(
      video1: v1.build(),
      video2: v2.build(),
      drills: drills.take(2).toList(),
      fallback: null,
    );
  }

  Future<void> _pickCompareVideo({required bool isLeft}) async {
    final title = isLeft ? "Select Video 1" : "Select Video 2";
    final subtitle =
        "Pick two different clips so CrickNova Coach can compare technique honestly.";

    final shouldContinue = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF020617)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: const Color(0xFF38BDF8).withOpacity(0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.18),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withOpacity(0.35),
                    ),
                  ),
                  child: const Text(
                    "CRICKNOVA COACH",
                    style: TextStyle(
                      color: Color(0xFFBAE6FD),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.16),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Not Now",
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Choose Video",
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldContinue != true || !mounted) return;
    await pickVideo(isLeft: isLeft);
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
      "Elite Tip: Watch the ball early and keep your head still at impact.",
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

      // Prevent choosing the same clip twice.
      final other = isLeft ? rightVideo : leftVideo;
      if (other != null) {
        final same = await _looksLikeSameVideo(file, other);
        if (same && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Please choose a different clip for Video 1 and Video 2.",
              ),
            ),
          );
          return;
        }
      }

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
    // Show a classy confirmation first, then open the gallery.
    _pickCompareVideo(isLeft: isLeft);
  }

  Future<bool> _looksLikeSameVideo(File a, File b) async {
    try {
      if (a.path == b.path) return true;
      final sa = await a.stat();
      final sb = await b.stat();
      if (sa.size != sb.size) return false;
      if (sa.modified.isAtSameMomentAs(sb.modified)) return true;
      // Fallback: compare a fast signature (first+last bytes).
      final sigA = await _videoSignature(a);
      final sigB = await _videoSignature(b);
      return sigA == sigB;
    } catch (_) {
      // If we can't decide, don't block.
      return false;
    }
  }

  Future<String> _videoSignature(File file) async {
    const chunk = 64 * 1024;
    int fnv1a64(int hash, List<int> bytes) {
      const int prime = 0x100000001B3;
      int h = hash;
      for (final b in bytes) {
        h ^= (b & 0xFF);
        h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
      }
      return h;
    }

    final stat = await file.stat();
    final raf = await file.open();
    try {
      final len = stat.size;
      final headLen = len < chunk ? len : chunk;
      final head = await raf.read(headLen);
      int h = 0xCBF29CE484222325; // offset basis
      h = fnv1a64(h, head);
      if (len > chunk) {
        await raf.setPosition(math.max(0, len - chunk));
        final tail = await raf.read(chunk);
        h = fnv1a64(h, tail);
      }
      h = fnv1a64(h, utf8.encode(len.toString()));
      return h.toUnsigned(64).toRadixString(16);
    } finally {
      await raf.close();
    }
  }

  Future<void> runCompare() async {
    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }

    // 🔒 Locked users see blur CTA (no popup/snackbar).
    if (!PremiumService.hasCompareAccess) {
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

    Future<http.MultipartRequest> _buildRequest() async {
      final request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";
      // Canonical Authorization header
      request.headers["Authorization"] = "Bearer $idToken";
      request.headers["X-USER-ID"] = user.uid;
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
      request.fields["user_id"] = user.uid;
      request.fields["prompt"] =
          """
You are CrickNova $_analysisDiscipline coach.

Compare these two $_analysisDiscipline clips honestly in natural coaching language.
Do not force Video 2 to look better than Video 1.
Keep it clip-specific and direct (no fixed headings/template).
Tell:
- what improved
- what is still weak
- what to do next
- exactly 2 practical drills
Do not mention speed, swing, or spin.
Do not give rating/score.
""";
      return request;
    }

    try {
      http.StreamedResponse? response;
      String body = "";
      Object? lastErr;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final req = await _buildRequest();
          response = await req.send().timeout(const Duration(seconds: 150));
          body = await response.stream.bytesToString();
          break;
        } catch (e) {
          lastErr = e;
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 850));
            continue;
          }
        }
      }
      if (response == null) {
        throw Exception(lastErr?.toString() ?? "REQUEST_FAILED");
      }

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
          if (detail == "PREMIUM_REQUIRED" || detail == "ACCESS_DENIED") {
            await PremiumService.ensureFreshState();
            if (!PremiumService.hasCompareAccess) {
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const PremiumScreen(entrySource: "compare_lock"),
                ),
              );
              return;
            }
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
        diffResult =
            "Compare is taking too long right now.\nPlease try again in 10 seconds.";
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
    final bool locked = !PremiumService.hasCompareAccess;

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
        title: Text(_isBowlingMode ? 'Bowling Analyse' : 'Analyse Yourself'),
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
                    child: _CompareResultView(
                      raw: diffResult!,
                      parsed: _parseCompareReply(diffResult!),
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
                      isLeft ? "VIDEO 1" : "VIDEO 2",
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
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          color: Colors.white70,
                          size: 42,
                        ),
                        SizedBox(height: 10),
                        Text(
                          isLeft ? "Add Video 1" : "Add Video 2",
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
                      children: [
                        Icon(
                          Icons.video_call_outlined,
                          color: Color(0xFF38BDF8),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          isLeft ? "Select 1" : "Select 2",
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

class _ParsedCompareReply {
  final _CompareVideoSummary video1;
  final _CompareVideoSummary video2;
  final List<String> drills;
  final String? fallback;

  const _ParsedCompareReply({
    required this.video1,
    required this.video2,
    required this.drills,
    required this.fallback,
  });

  const _ParsedCompareReply.empty()
    : video1 = const _CompareVideoSummary.empty(),
      video2 = const _CompareVideoSummary.empty(),
      drills = const [],
      fallback = null;

  const _ParsedCompareReply.fallback(this.fallback)
    : video1 = const _CompareVideoSummary.empty(),
      video2 = const _CompareVideoSummary.empty(),
      drills = const [];

  bool get hasStructured => video1.hasAny || video2.hasAny || drills.isNotEmpty;
}

class _CompareResultView extends StatelessWidget {
  final String raw;
  final _ParsedCompareReply parsed;

  const _CompareResultView({required this.raw, required this.parsed});

  @override
  Widget build(BuildContext context) {
    // If it's an error/status message, keep it simple.
    final lower = raw.toLowerCase();
    final looksLikeError =
        lower.contains('failed') ||
        lower.contains('denied') ||
        lower.contains('expired') ||
        lower.contains('error') ||
        lower.contains('connection');

    if (!parsed.hasStructured || looksLikeError) {
      return Row(
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
              parsed.fallback ?? raw,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17, // +2 points
                height: 1.5,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.smart_toy_outlined,
              color: Color(0xFF38BDF8),
              size: 22,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "Comparison Summary",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CompareColumnCard(
                title: "VIDEO 1",
                subtitle: "Clip 1",
                accent: const Color(0xFF38BDF8),
                summary: parsed.video1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CompareColumnCard(
                title: "VIDEO 2",
                subtitle: "Clip 2",
                accent: const Color(0xFF22D3EE),
                summary: parsed.video2,
              ),
            ),
          ],
        ),
        if (parsed.drills.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DrillsCard(drills: parsed.drills),
        ],
      ],
    );
  }
}

class _CompareColumnCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final _CompareVideoSummary summary;

  const _CompareColumnCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (!summary.hasAny)
            Text(
              "No notes returned.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.70),
                fontSize: 15,
                height: 1.45,
              ),
            )
          else
            ..._buildSummaryCards(),
        ],
      ),
    );
  }

  List<Widget> _buildSummaryCards() {
    final stance = summary.stance?.trim();
    final shot = summary.shotSelection?.trim();
    final key = summary.mistakeOrImprovement?.trim();

    // If we couldn't extract fields, show the first 2 big points like Mistake Detection.
    if ((stance == null || stance.isEmpty) &&
        (shot == null || shot.isEmpty) &&
        (key == null || key.isEmpty) &&
        summary.extraLines.isNotEmpty) {
      return [
        _MiniSectionCard(
          title: "KEY POINTS",
          accent: accent,
          bullets: summary.extraLines.take(2).toList(),
        ),
      ];
    }

    final widgets = <Widget>[];
    if (stance != null && stance.isNotEmpty) {
      widgets.add(
        _MiniSectionCard(
          title: "WHAT WORKED",
          accent: accent,
          bullets: [stance],
        ),
      );
    }
    if (shot != null && shot.isNotEmpty) {
      widgets.add(
        _MiniSectionCard(title: "WHAT TO FIX", accent: accent, bullets: [shot]),
      );
    }
    if (key != null && key.isNotEmpty) {
      widgets.add(
        _MiniSectionCard(title: "KEY NOTE", accent: accent, bullets: [key]),
      );
    }

    // Keep it compact: at most 3 cards.
    return [
      for (int i = 0; i < widgets.length; i++) ...[
        widgets[i],
        if (i != widgets.length - 1) const SizedBox(height: 10),
      ],
    ];
  }
}

class _MiniSectionCard extends StatelessWidget {
  final String title;
  final Color accent;
  final List<String> bullets;

  const _MiniSectionCard({
    required this.title,
    required this.accent,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.32)),
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
                title,
                style: TextStyle(
                  color: accent.withOpacity(0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final b in bullets.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                "• $b",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DrillsCard extends StatelessWidget {
  final List<String> drills;
  const _DrillsCard({required this.drills});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "DRILLS",
            style: TextStyle(
              color: Color(0xFF86EFAC),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          for (final d in drills.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                "• $d",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompareVideoSummary {
  final String? stance;
  final String? shotSelection;
  final String? mistakeOrImprovement;
  final List<String> extraLines;

  const _CompareVideoSummary({
    required this.stance,
    required this.shotSelection,
    required this.mistakeOrImprovement,
    required this.extraLines,
  });

  const _CompareVideoSummary.empty()
    : stance = null,
      shotSelection = null,
      mistakeOrImprovement = null,
      extraLines = const [];

  bool get hasAny =>
      (stance != null && stance!.trim().isNotEmpty) ||
      (shotSelection != null && shotSelection!.trim().isNotEmpty) ||
      (mistakeOrImprovement != null &&
          mistakeOrImprovement!.trim().isNotEmpty) ||
      extraLines.isNotEmpty;
}

class _CompareVideoSummaryBuilder {
  String? stance;
  String? shotSelection;
  String? mistakeOrImprovement;
  final List<String> extraLines = [];

  bool get hasAny =>
      (stance != null && stance!.trim().isNotEmpty) ||
      (shotSelection != null && shotSelection!.trim().isNotEmpty) ||
      (mistakeOrImprovement != null &&
          mistakeOrImprovement!.trim().isNotEmpty) ||
      extraLines.isNotEmpty;

  void addLine(String line) {
    final l = line.trim();
    if (l.isEmpty) return;

    // Handle "run-up, release, mistake" on one line.
    final commaParts = l
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (commaParts.length >= 3 &&
        (stance == null ||
            shotSelection == null ||
            mistakeOrImprovement == null)) {
      stance ??= commaParts[0];
      shotSelection ??= commaParts[1];
      mistakeOrImprovement ??= commaParts[2];
      return;
    }

    final parts = l.split(':');
    if (parts.length >= 2) {
      final key = parts.first.trim().toLowerCase();
      final value = parts.sublist(1).join(':').trim();
      if (value.isEmpty) return;

      if (key.startsWith('what worked') ||
          key.startsWith('strength') ||
          key.startsWith('positive') ||
          key.startsWith('good')) {
        stance ??= value;
        return;
      }
      if (key.startsWith('what needs work') ||
          key.startsWith('needs work') ||
          key.startsWith('issue') ||
          key.startsWith('problem') ||
          key.startsWith('fix')) {
        shotSelection ??= value;
        return;
      }
      if (key.startsWith('key note') ||
          key.startsWith('key') ||
          key.startsWith('note') ||
          key.startsWith('difference')) {
        mistakeOrImprovement ??= value;
        return;
      }
    }

    // Handle common inline patterns like "Run-up - ..." or "Release - ..."
    final dashParts = l.split(RegExp(r'\s*-\s*'));
    if (dashParts.length >= 2) {
      final key = dashParts.first.trim().toLowerCase();
      final value = dashParts.sublist(1).join(' - ').trim();
      if (key.startsWith('what worked') ||
          key.startsWith('strength') ||
          key.startsWith('positive') ||
          key.startsWith('good')) {
        stance ??= value;
        return;
      }
      if (key.startsWith('what needs work') ||
          key.startsWith('needs work') ||
          key.startsWith('issue') ||
          key.startsWith('problem') ||
          key.startsWith('fix')) {
        shotSelection ??= value;
        return;
      }
      if (key.startsWith('key note') ||
          key.startsWith('key') ||
          key.startsWith('note') ||
          key.startsWith('difference')) {
        mistakeOrImprovement ??= value;
        return;
      }
    }

    // No label: fill in order so the UI still shows the 3 cards clearly.
    if (stance == null) {
      stance = l;
      return;
    }
    if (shotSelection == null) {
      shotSelection = l;
      return;
    }
    if (mistakeOrImprovement == null) {
      mistakeOrImprovement = l;
      return;
    }

    extraLines.add(l);
  }

  _CompareVideoSummary build() {
    return _CompareVideoSummary(
      stance: stance,
      shotSelection: shotSelection,
      mistakeOrImprovement: mistakeOrImprovement,
      extraLines: extraLines.take(4).toList(),
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
