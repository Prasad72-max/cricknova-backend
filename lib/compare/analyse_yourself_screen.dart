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
import 'package:google_fonts/google_fonts.dart';
import '../services/weekly_stats_service.dart';
import '../services/xp_service.dart';
import '../theme/crickx_colors.dart';
import '../services/analysis_credit_service.dart';

class AnalyseYourselfScreen extends StatefulWidget {
  final bool bowlingMode;

  const AnalyseYourselfScreen({super.key, this.bowlingMode = false});

  @override
  State<AnalyseYourselfScreen> createState() => _AnalyseYourselfScreenState();
}

class _AnalyseYourselfScreenState extends State<AnalyseYourselfScreen>
    with TickerProviderStateMixin {
  static bool _hasShownUploadGuidanceThisSession = false;

  bool get _isBowlingMode => widget.bowlingMode;
  String get _analysisDiscipline => _isBowlingMode ? "bowling" : "batting";
  String get _disciplineGuard => _isBowlingMode
      ? "Bowling-only: talk about run-up, gather, front-foot landing, wrist/seam, release point, line/length, follow-through, and bowling drills. Never give batting mistakes, bat path, shot, stance, or batting footwork feedback."
      : "Batting-only: talk about stance, head position, balance, bat path, timing, shot control, and batting drills. Never give bowling mistakes, run-up, release point, seam/wrist, line/length, or bowling feedback.";

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
    String? v1;
    String? v2;
    String? diff;
    String? prog;
    String? finalVerdict;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();

      // Final Verdict
      if (lower.startsWith('final verdict') || lower.startsWith('**final verdict')) {
        final colonIdx = line.indexOf(':');
        final val = colonIdx != -1
            ? line.substring(colonIdx + 1).trim()
            : line.replaceFirst(RegExp(r'^(?:\*\*)?final verdict(?:\*\*)?[\s:-]*', caseSensitive: false), '').trim();
        finalVerdict = val;
        section = 'verdict';
        continue;
      }

      // Point 1: Video 1
      if (lower.startsWith('1.') || (lower.contains('video 1') && (lower.contains('technique') || lower.contains('execution') || lower.contains('good') || lower.contains('worked')))) {
        final colonIdx = line.indexOf(':');
        final val = colonIdx != -1
            ? line.substring(colonIdx + 1).trim()
            : line.replaceFirst(RegExp(r'^\s*1\.?\s*(?:video\s*1[^\:]*[\:\-])?', caseSensitive: false), '').trim();
        if (val.isNotEmpty) {
          v1 = val;
          section = 'v1';
          continue;
        }
      }

      // Point 2: Video 2
      if (lower.startsWith('2.') || (lower.contains('video 2') && (lower.contains('technique') || lower.contains('changes') || lower.contains('execution') || lower.contains('bad') || lower.contains('good')))) {
        final colonIdx = line.indexOf(':');
        final val = colonIdx != -1
            ? line.substring(colonIdx + 1).trim()
            : line.replaceFirst(RegExp(r'^\s*2\.?\s*(?:video\s*2[^\:]*[\:\-])?', caseSensitive: false), '').trim();
        if (val.isNotEmpty) {
          v2 = val;
          section = 'v2';
          continue;
        }
      }

      // Point 3: Key Technical Differences
      if (lower.startsWith('3.') || lower.contains('difference') || lower.contains('comparison') || lower.contains('contrast')) {
        final colonIdx = line.indexOf(':');
        final val = colonIdx != -1
            ? line.substring(colonIdx + 1).trim()
            : line.replaceFirst(RegExp(r'^\s*3\.?\s*(?:key technical differences[^\:]*[\:\-])?', caseSensitive: false), '').trim();
        if (val.isNotEmpty) {
          diff = val;
          section = 'diff';
          continue;
        }
      }

      // Point 4: Progression & Corrections
      if (lower.startsWith('4.') || lower.contains('progression') || lower.contains('correction') || lower.contains('adjustment')) {
        final colonIdx = line.indexOf(':');
        final val = colonIdx != -1
            ? line.substring(colonIdx + 1).trim()
            : line.replaceFirst(RegExp(r'^\s*4\.?\s*(?:progression[^\:]*[\:\-])?', caseSensitive: false), '').trim();
        if (val.isNotEmpty) {
          prog = val;
          section = 'prog';
          continue;
        }
      }

      final normalized = line
          .replaceFirst(RegExp(r'^\s*[-•]\s*'), '')
          .replaceFirst(RegExp(r'^\s*\d+[\).\]]\s*'), '')
          .trim();
      if (normalized.isEmpty) continue;

      if (section == 'verdict') {
        finalVerdict = (finalVerdict != null && finalVerdict.isNotEmpty)
            ? '$finalVerdict $normalized'
            : normalized;
      } else if (section == 'v1') {
        v1 = (v1 != null && v1.isNotEmpty) ? '$v1\n• $normalized' : normalized;
      } else if (section == 'v2') {
        v2 = (v2 != null && v2.isNotEmpty) ? '$v2\n• $normalized' : normalized;
      } else if (section == 'diff') {
        diff = (diff != null && diff.isNotEmpty) ? '$diff\n• $normalized' : normalized;
      } else if (section == 'prog') {
        prog = (prog != null && prog.isNotEmpty) ? '$prog\n• $normalized' : normalized;
      }
    }

    if (v1 == null && v2 == null && diff == null && prog == null && (finalVerdict == null || finalVerdict.isEmpty)) {
      return _ParsedCompareReply.fallback(_formatCompareReply(cleaned));
    }

    return _ParsedCompareReply(
      video1: v1,
      video2: v2,
      differences: diff,
      progression: prog,
      finalVerdict: finalVerdict,
      fallback: null,
    );
  }

  Future<void> _pickCompareVideo({required bool isLeft}) async {
    if (_hasShownUploadGuidanceThisSession) {
      await pickVideo(isLeft: isLeft);
      return;
    }
    _hasShownUploadGuidanceThisSession = true;

    final title = isLeft ? "Select Video 1" : "Select Video 2";
    final subtitle =
        "Choose two clear clips of your own cricket action. Similar camera angles and matching batting or bowling actions will give you a more useful comparison.";

    final shouldContinue = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: CrickXColors.graphiteBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: CrickXColors.graphiteBorder,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22),
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
                    color: CrickXColors.graphite,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: CrickXColors.graphiteBorder,
                      width: 1.1,
                    ),
                  ),
                  child: Text(
                    "BETTER COMPARISON GUIDE",
                    style: GoogleFonts.poppins(
                      color: CrickXColors.limeSpark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFA1A1AA),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CrickXColors.graphite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: CrickXColors.graphiteBorder,
                      width: 1.1,
                    ),
                  ),
                  child: Text(
                    "For the clearest result, use genuine cricket practice clips where your full action is visible. Avoid dark, shaky, cropped, or unrelated videos.",
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFE2E8F0),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                       child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: CrickXColors.graphiteBorder,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          "Not Now",
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFA1A1AA),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CrickXColors.limeSpark,
                          foregroundColor: CrickXColors.onLime,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          "Choose Video",
                          style: GoogleFonts.poppins(
                            color: CrickXColors.onLime,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
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
    AnalysisCreditService.instance.loadCredits();
    AnalysisCreditService.instance.battingCompareCreditsNotifier.addListener(_onCreditsUpdate);
    AnalysisCreditService.instance.bowlingCompareCreditsNotifier.addListener(_onCreditsUpdate);
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

      final XFile? picked = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 15),
      );
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
    int fnv1a32(int hash, List<int> bytes) {
      const int prime = 16777619;
      int h = hash;
      for (final b in bytes) {
        h ^= (b & 0xFF);
        h = (h * prime) & 0xFFFFFFFF;
      }
      return h;
    }

    final stat = await file.stat();
    final raf = await file.open();
    try {
      final len = stat.size;
      final headLen = len < chunk ? len : chunk;
      final head = await raf.read(headLen);
      int h = 2166136261; // FNV-1a 32-bit offset basis
      h = fnv1a32(h, head);
      if (len > chunk) {
        await raf.setPosition(math.max(0, len - chunk));
        final tail = await raf.read(chunk);
        h = fnv1a32(h, tail);
      }
      h = fnv1a32(h, utf8.encode(len.toString()));
      return h.toUnsigned(32).toRadixString(16);
    } finally {
      await raf.close();
    }
  }

  Future<bool> _showWatchAdForCompareDialog({required bool isBowling}) async {
    bool unlocked = false;
    final title = isBowling ? 'Bowling Compare' : 'Analyse Yourself Batting';
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: CrickXColors.graphiteBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
        title: Text(
          '🎬 Watch Ad to Unlock 2 Analyses',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Watch a short video ad to unlock 2 $title comparison analyses, or upgrade to Premium.',
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                label: const Text(
                  'Watch Ad (2 Free Analyses)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CrickXColors.limeSpark,
                  foregroundColor: CrickXColors.onLime,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  Navigator.of(dialogCtx).pop();
                  final result = isBowling
                      ? await AnalysisCreditService.instance.watchAdForBowlingCompare(amount: 2)
                      : await AnalysisCreditService.instance.watchAdForBattingCompare(amount: 2);

                  if (result == AdWatchResult.rewardEarned ||
                      result == AdWatchResult.premiumUser) {
                    unlocked = true;
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🎉 2 comparison credits added!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      setState(() {});
                    }
                  } else if (result == AdWatchResult.adNotAvailable) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Ad isn't available right now. Please try again in a moment."),
                        ),
                      );
                    }
                  } else if (result == AdWatchResult.adClosedEarly) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Watch the complete ad to get your 2 analyses."),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const PremiumScreen(entrySource: "compare_lock"),
                  ),
                );
              },
              child: const Text(
                'Get Premium (Unlimited Access)',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
    return unlocked;
  }

  Future<void> runCompare() async {
    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }

    final hasPremiumCompare = PremiumService.hasCompareAccess;
    if (!hasPremiumCompare) {
      final availableCredits = _isBowlingMode
          ? AnalysisCreditService.instance.bowlingCompareCredits
          : AnalysisCreditService.instance.battingCompareCredits;

      if (availableCredits <= 0) {
        final earned = await _showWatchAdForCompareDialog(isBowling: _isBowlingMode);
        if (!earned) {
          final nowCredits = _isBowlingMode
              ? AnalysisCreditService.instance.bowlingCompareCredits
              : AnalysisCreditService.instance.battingCompareCredits;
          if (nowCredits <= 0) return;
        }
      }

      // Consume 1 credit
      final consumed = _isBowlingMode
          ? await AnalysisCreditService.instance.consumeBowlingCompareCredit()
          : await AnalysisCreditService.instance.consumeBattingCompareCredit();
      if (!consumed && !PremiumService.hasCompareAccess) {
        await _showWatchAdForCompareDialog(isBowling: _isBowlingMode);
        return;
      }
    } else {
      final remaining = await PremiumService.getCompareLimit();
      if (remaining <= 0) {
        if (!mounted) return;

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: CrickXColors.graphiteBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
            ),
            title: const Text(
              "🚀 Analyse Limit Reached",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              "You've used all your CricX Analyse Yourself attempts.\n\nUpgrade your plan or watch an ad to continue.",
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
                  backgroundColor: CrickXColors.limeSpark,
                  foregroundColor: CrickXColors.onLime,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
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
                child: Text(
                  "Upgrade Now",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }
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
      request.fields["discipline"] = _analysisDiscipline;
      request.fields["prompt"] =
          """You are a professional, India-level cricket $_analysisDiscipline coach.
Compare the player's $_analysisDiscipline technique between Video 1 and Video 2.
Directly contrast both clips and highlight concrete technical differences, technique changes, and progression.

Return EXACTLY these 4 comparison points followed by a Final Verdict, and nothing else. No extra intro, no filler words:

1. Video 1 (Technique): [Technical execution and body posture in Video 1]
2. Video 2 (Technique): [Technical execution and adjustments seen in Video 2]
3. Key Technical Differences: [Direct head-to-head comparison highlighting the exact differences between both videos]
4. Progression & Corrections: [Analysis of technical improvement from Video 1 to Video 2 and remaining corrections]

Final Verdict: [Definite coaching verdict comparing both videos and declaring which clip showed better technique]

Do not add any other sentence, explanation, or heading.""";
      return request;
    }

    try {
      final req = await _buildRequest();
      final response = await req.send().timeout(const Duration(seconds: 90));
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        if (data is Map &&
            data["status"]?.toString().toLowerCase() == "non_cricket") {
          setState(() {
            diffResult =
                data["message"]?.toString() ??
                "This does not look like a cricket training clip. Please upload clear cricket practice videos for accurate CrickX analysis.";
          });
          return;
        }

        setState(() {
          diffResult = _formatCompareReply(
            (data["difference"] ?? "No difference returned.").toString(),
          );
        });
        try {
          await WeeklyStatsService.recordAnalyseAi(user.uid);
        } catch (_) {}
        await XpService.award(uid: user.uid, amount: 40, source: 'COMPARE');

        if (PremiumService.hasCompareAccess) {
          await PremiumService.consumeCompare();
          try {
            final usage = await PremiumService.fetchMonthlyUsage();
            await _maybeShowCompareLimitReached(usage.swingUsed);
          } catch (e) {
            debugPrint("USAGE TRACK ERROR (COMPARE) => $e");
          }
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
                backgroundColor: CrickXColors.graphiteBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
                ),
                title: Text(
                  "Analyse Limit Reached",
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                content: Text(
                  "Your CricX Analyse Yourself limit has ended.\n\nUpgrade your plan or watch an ad to continue.",
                  style: GoogleFonts.poppins(color: const Color(0xFFA1A1AA), height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Upgrade",
                      style: GoogleFonts.poppins(color: CrickXColors.limeSpark, fontWeight: FontWeight.w700),
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
        backgroundColor: CrickXColors.graphiteBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
        title: Text(
          "Analyse Limit Reached",
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "You've reached your monthly CrickX CricX Analyse Yourself limit.\n\nUpgrade to keep comparing your technique.",
          style: GoogleFonts.poppins(color: const Color(0xFFA1A1AA), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Later", style: GoogleFonts.poppins(color: const Color(0xFFA1A1AA))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CrickXColors.limeSpark,
              foregroundColor: CrickXColors.onLime,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
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
            child: Text(
              "Upgrade Now",
              style: GoogleFonts.poppins(
                color: CrickXColors.onLime,
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),
              // CricX AI Watermark (Enlarged + Slogan)
              Positioned(
                left: 12,
                bottom: 12,
                child: Opacity(
                  opacity: 0.95,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipOval(
                        child: Image.asset(
                          "assets/logo.png",
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Uploaded on CrickX AI",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            "Where Cricket Meets Intelligence",
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCreditsUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    AnalysisCreditService.instance.battingCompareCreditsNotifier.removeListener(_onCreditsUpdate);
    AnalysisCreditService.instance.bowlingCompareCreditsNotifier.removeListener(_onCreditsUpdate);
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
      backgroundColor: CrickXColors.graphiteBg,
      appBar: AppBar(
        backgroundColor: CrickXColors.graphiteBg,
        title: Text(
          _isBowlingMode ? 'Bowling Compare' : 'CricX Analyse Yourself',
        ),
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: _isBowlingMode
                ? AnalysisCreditService.instance.bowlingCompareCreditsNotifier
                : AnalysisCreditService.instance.battingCompareCreditsNotifier,
            builder: (context, credits, _) {
              final premium = PremiumService.hasCompareAccess;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: InkWell(
                    onTap: premium
                        ? null
                        : () => _showWatchAdForCompareDialog(
                              isBowling: _isBowlingMode,
                            ),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: premium
                            ? CrickXColors.limeSpark.withValues(alpha: 0.2)
                            : (credits > 0
                                ? CrickXColors.limeSpark.withValues(alpha: 0.15)
                                : Colors.orange.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: premium
                              ? CrickXColors.limeSpark
                              : (credits > 0
                                  ? CrickXColors.limeSpark
                                  : Colors.orangeAccent),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            premium
                                ? Icons.star_rounded
                                : Icons.analytics_outlined,
                            size: 14,
                            color: premium
                                ? CrickXColors.limeSpark
                                : (credits > 0
                                    ? CrickXColors.limeSpark
                                    : Colors.orangeAccent),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            premium ? "PRO" : "$credits left",
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          if (!premium) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.add_circle,
                              size: 14,
                              color: Colors.white70,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: CrickXColors.graphiteBg,
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
                  enabled: canCompare,
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
                              ? CrickXColors.limeSpark
                              : CrickXColors.graphiteElevated,
                          foregroundColor: isSynced
                              ? CrickXColors.onLime
                              : Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: toggleSync,
                        child: Text(
                          isSynced ? "SYNC ON" : "SYNC PLAY",
                          style: TextStyle(
                            color: isSynced
                                ? CrickXColors.onLime
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                if (comparing)
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: CrickXColors.graphiteBorder,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: const LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor: CrickXColors.graphiteElevated,
                            valueColor: AlwaysStoppedAnimation<Color>(CrickXColors.limeSpark),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          "AI is matching frames to find technique differences...",
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFA1A1AA),
                            fontSize: 13.5,
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
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 14.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
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
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: CrickXColors.graphiteBorder,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
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
              color: CrickXColors.graphite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(controller),
                        // CricX AI Watermark (Enlarged + Slogan)
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Opacity(
                            opacity: 0.95,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ClipOval(
                                  child: Image.asset(
                                    "assets/logo.png",
                                    width: 28,
                                    height: 28,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Uploaded on CrickX AI",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    Text(
                                      "Where Cricket Meets Intelligence",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 7.5,
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: CrickXColors.graphiteElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CrickXColors.graphiteBorder,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.video_call_outlined,
                          color: CrickXColors.limeSpark,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLeft ? "Select 1" : "Select 2",
                          style: GoogleFonts.poppins(
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
  final String? video1;
  final String? video2;
  final String? differences;
  final String? progression;
  final String? finalVerdict;
  final String? fallback;

  const _ParsedCompareReply({
    this.video1,
    this.video2,
    this.differences,
    this.progression,
    this.finalVerdict,
    this.fallback,
  });

  const _ParsedCompareReply.empty()
      : video1 = null,
        video2 = null,
        differences = null,
        progression = null,
        finalVerdict = null,
        fallback = null;

  const _ParsedCompareReply.fallback(this.fallback)
      : video1 = null,
        video2 = null,
        differences = null,
        progression = null,
        finalVerdict = null;

  bool get hasStructured =>
      (video1 != null && video1!.isNotEmpty) ||
      (video2 != null && video2!.isNotEmpty) ||
      (differences != null && differences!.isNotEmpty) ||
      (progression != null && progression!.isNotEmpty) ||
      (finalVerdict != null && finalVerdict!.isNotEmpty);
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
            Icons.sports_cricket_rounded,
            color: CrickXColors.limeSpark,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parsed.fallback ?? raw,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 15,
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
          children: [
            const Icon(
              Icons.compare_arrows_rounded,
              color: CrickXColors.limeSpark,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Comparison & Difference Analysis",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Side-by-side Video 1 vs Video 2 technique
        if ((parsed.video1 != null && parsed.video1!.isNotEmpty) ||
            (parsed.video2 != null && parsed.video2!.isNotEmpty)) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompareVideoCard(
                  title: "VIDEO 1",
                  subtitle: "Clip 1 Technique",
                  content: parsed.video1 ?? "Technique analyzed",
                  accent: CrickXColors.limeSpark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CompareVideoCard(
                  title: "VIDEO 2",
                  subtitle: "Clip 2 Technique",
                  content: parsed.video2 ?? "Technique analyzed",
                  accent: const Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],

        // Head-to-Head Technical Differences
        if (parsed.differences != null && parsed.differences!.isNotEmpty) ...[
          _ComparisonSectionCard(
            title: "KEY TECHNICAL DIFFERENCES",
            icon: Icons.swap_horiz_rounded,
            accent: CrickXColors.limeSpark,
            content: parsed.differences!,
          ),
          const SizedBox(height: 14),
        ],

        // Progression & Corrections
        if (parsed.progression != null && parsed.progression!.isNotEmpty) ...[
          _ComparisonSectionCard(
            title: "PROGRESSION & CORRECTIONS",
            icon: Icons.trending_up_rounded,
            accent: const Color(0xFF38BDF8),
            content: parsed.progression!,
          ),
          const SizedBox(height: 14),
        ],

        // Final Verdict
        if (parsed.finalVerdict != null && parsed.finalVerdict!.isNotEmpty)
          _FinalVerdictCard(verdict: parsed.finalVerdict!),
      ],
    );
  }
}

class _CompareVideoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String content;
  final Color accent;

  const _CompareVideoCard({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CrickXColors.graphiteBorder, width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
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
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              color: const Color(0xFFA1A1AA),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(0.92),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final String content;

  const _ComparisonSectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.5), width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalVerdictCard extends StatelessWidget {
  final String verdict;
  const _FinalVerdictCard({required this.verdict});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CrickXColors.limeSpark.withOpacity(0.6),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.gavel_rounded,
                color: CrickXColors.limeSpark,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                "FINAL VERDICT",
                style: GoogleFonts.poppins(
                  color: CrickXColors.limeSpark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            verdict,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CrickXColors.graphiteBorder, width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "DRILLS",
            style: GoogleFonts.poppins(
              color: CrickXColors.limeSpark,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          for (final d in drills.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                "• $d",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
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
          colors: [CrickXColors.graphiteElevated, CrickXColors.graphite],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.40 * intensity),
            blurRadius: 18,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: CrickXColors.limeSpark.withOpacity(0.35 * intensity),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CrickXColors.graphite,
            border: Border.all(color: CrickXColors.limeSpark.withOpacity(0.5)),
          ),
          alignment: Alignment.center,
          child: const Text(
            "VS",
            style: TextStyle(
              color: CrickXColors.limeSpark,
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
                      ? const [CrickXColors.limeSpark, CrickXColors.limeSpark]
                      : [
                          CrickXColors.limeSpark.withOpacity(0.35),
                          CrickXColors.limeSpark.withOpacity(0.20),
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: CrickXColors.limeSpark.withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                "COMPARE ANALYSIS",
                style: GoogleFonts.poppins(
                  color: enabled ? CrickXColors.onLime : CrickXColors.onLime.withOpacity(0.5),
                  fontWeight: FontWeight.w800,
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
      ..shader = LinearGradient(
        colors: [CrickXColors.limeSpark, CrickXColors.limeSpark.withOpacity(0.7), CrickXColors.limeSpark],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final pulsePaint = Paint()
      ..strokeWidth = baseWidth + 2.2
      ..color = CrickXColors.limeSpark.withOpacity(0.15 + (0.10 * glow))
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

