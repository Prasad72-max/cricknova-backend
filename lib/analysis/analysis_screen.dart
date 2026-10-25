import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../premium/premium_screen.dart';
import '../ai/ai_coach_screen.dart';
import '../services/analysis_credit_service.dart';
import '../services/premium_service.dart';
import '../services/admob_service.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _loading = false;
  bool _showTrajectoryAfterVideo = false;

  double? speedKmph;
  String? speedType;
  String? swingName;
  String? spinType;
  String? spinStrength;
  List<dynamic>? trajectory;
  String? drsDecision;
  double? stumpConfidence;

  // CHANGE THIS TO YOUR IP:
  final String backendUrl =
      "https://cricknova-backend.onrender.com/training/analyze";

  String? _normalizeSwingLabel(String? raw) {
    final s = (raw ?? "").toLowerCase();
    if (s.contains("out")) return "OUTSWING";
    if (s.contains("in")) return "INSWING";
    return null;
  }

  String? _normalizeSpinLabel(String? raw) {
    final s = (raw ?? "").toLowerCase();
    if (s.contains("leg")) return "LEG SPIN";
    if (s.contains("off")) return "OFF SPIN";
    return null;
  }

  List<Map<String, double>> _extractTrajectoryPoints(dynamic rawTrajectory) {
    if (rawTrajectory is! List) return const [];
    final points = <Map<String, double>>[];
    for (final item in rawTrajectory) {
      if (item is! Map) continue;
      final x = item["x"];
      final y = item["y"];
      if (x is num && y is num) {
        points.add({"x": x.toDouble(), "y": y.toDouble()});
      }
    }
    return points;
  }

  Map<String, String> _inferLabelsFromTrajectory(dynamic rawTrajectory) {
    final pts = _extractTrajectoryPoints(rawTrajectory);
    if (pts.length < 2) {
      return {"swing": "INSWING", "spin": "OFF SPIN"};
    }

    final dxTotal = pts.last["x"]! - pts.first["x"]!;
    final swingLabel = dxTotal >= 0 ? "OUTSWING" : "INSWING";

    int pivot = 0;
    double maxY = pts.first["y"]!;
    for (int i = 1; i < pts.length; i++) {
      final y = pts[i]["y"]!;
      if (y > maxY) {
        maxY = y;
        pivot = i;
      }
    }

    double spinDx;
    if (pivot > 0 && pivot < pts.length - 1) {
      final preX = pts[pivot]["x"]! - pts[0]["x"]!;
      final postX = pts.last["x"]! - pts[pivot]["x"]!;
      spinDx = postX - preX;
    } else {
      final mid = pts.length ~/ 2;
      final preMean =
          pts.sublist(0, mid).fold<double>(0, (a, p) => a + p["x"]!) /
          (mid == 0 ? 1 : mid);
      final postCount = pts.length - mid;
      final postMean =
          pts.sublist(mid).fold<double>(0, (a, p) => a + p["x"]!) /
          (postCount == 0 ? 1 : postCount);
      spinDx = postMean - preMean;
    }
    final spinLabel = spinDx >= 0 ? "LEG SPIN" : "OFF SPIN";

    return {"swing": swingLabel, "spin": spinLabel};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          "Analysis",
          style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _uploadButton(context),
            const SizedBox(height: 20),

            _metricBox(
              title: "Speed",
              value: speedKmph != null
                  ? ((speedType == "very_slow_estimate" ||
                            speedType == "camera_normalized" ||
                            speedType == "video_derived" ||
                            speedType == "derived_physics")
                        ? "~${speedKmph!.toStringAsFixed(1)} km/h"
                        : "${speedKmph!.toStringAsFixed(1)} km/h")
                  : "Unavailable",
              icon: Icons.speed,
              color: speedKmph != null ? Colors.blueAccent : Colors.grey,
            ),
            const SizedBox(height: 15),

            _metricBox(
              title: "Swing",
              value: swingName ?? "NA",
              icon: Icons.rotate_right,
              color: Colors.orange,
            ),
            const SizedBox(height: 15),

            _metricBox(
              title: "Spin",
              value: (spinType != null && spinType!.isNotEmpty)
                  ? spinType!
                  : "NA",
              icon: Icons.autorenew,
              color: Colors.green,
            ),
            const SizedBox(height: 15),

            _metricBox(
              title: "DRS Decision",
              value: drsDecision != null
                  ? (stumpConfidence != null
                        ? "$drsDecision (${(stumpConfidence! * 100).toStringAsFixed(0)}%)"
                        : drsDecision!)
                  : "NA",
              icon: Icons.gavel,
              color: drsDecision == "OUT"
                  ? Colors.red
                  : (drsDecision == "NOT OUT" ? Colors.green : Colors.grey),
            ),
            const SizedBox(height: 15),

            ElevatedButton(
              onPressed:
                  (speedKmph == null &&
                      swingName == null &&
                      spinType == null &&
                      spinStrength == null)
                  ? null
                  : () async {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AICoachScreen(
                            initialQuestion:
                                "Analyze my batting mistake on this delivery",
                            payloadContext: {
                              "speed_kmph": speedKmph,
                              "swing": swingName,
                              "spin": spinType,
                            },
                          ),
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                "COACH",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 25),
            (!_showTrajectoryAfterVideo ||
                    trajectory == null ||
                    trajectory!.isEmpty)
                ? _chartPlaceholder("Ball Trajectory")
                : _trajectoryView(),
            const SizedBox(height: 25),
            _chartPlaceholder("Pitch Map"),
            const SizedBox(height: 25),
            _chartPlaceholder("Release Point Map"),
          ],
        ),
      ),
    );
  }

  // --------------- UPLOAD BUTTON -------------------
  Widget _uploadButton(BuildContext context) {
    return GestureDetector(
      onTap: _loading
          ? null
          : () async {
              _pickVideo(context);
            },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _loading ? Colors.grey[700] : Colors.black,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.upload, color: Colors.white, size: 28),
            const SizedBox(width: 14),
            Text(
              _loading ? "Uploading..." : "Upload Training Video",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------- PICK VIDEO -------------------
  Future<void> _pickVideo(BuildContext context) async {
    // ── CREDIT GATE ─────────────────────────────────────────────────────────
    // For free users, check credits BEFORE picking video.
    // Consume credit only after a file is actually selected.
    if (!PremiumService.isPremiumActive) {
      final credits = AnalysisCreditService.instance.credits;
      if (credits <= 0) {
        // No credits — show Watch Ad dialog first, then retry
        if (!context.mounted) return;
        await _showWatchAdDialog(context);
        return;
      }
    }

    final picked = await FilePicker.platform.pickFiles(type: FileType.video);

    if (picked == null) return;

    // Consume 1 credit now that a file was actually selected
    if (!PremiumService.isPremiumActive) {
      final consumed = await AnalysisCreditService.instance.consumeCredit();
      if (!consumed) {
        // Rare race — credits ran out between check and consume; show dialog again
        if (!context.mounted) return;
        await _showWatchAdDialog(context);
        return;
      }
    }

    final file = File(picked.files.single.path!);

    setState(() {
      _loading = true;
    });

    Map<String, dynamic>? responseData;

    try {
      responseData = await _sendToBackend(file);
    } catch (e) {
      setState(() => _loading = false);

      if (e.toString().contains("USER_NOT_AUTHENTICATED")) {
        _showError(context, "Session expired. Please reopen the app.");
        return;
      }

      if (e.toString().contains("TRAINING_LIMIT_REACHED")) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
        return;
      }

      _showError(context, "Server error. Try again.");
      return;
    }

    setState(() => _loading = false);

    if (responseData == null) {
      _showError(context, "Server error. Try again.");
      return;
    }

    debugPrint("ANALYSIS RESPONSE => $responseData");
    final nonNullResponse = responseData!;

    setState(() {
      // ---------- NORMALIZE SOURCE ----------
      final Map<String, dynamic> src =
          (nonNullResponse["data"] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(nonNullResponse["data"])
          : Map<String, dynamic>.from(nonNullResponse);
      final inferred = _inferLabelsFromTrajectory(src["trajectory"]);

      // ---------- SPEED (FULLTRACK STYLE) ----------
      final speedVal = src["speed_kmph"];
      speedType = src["speed_type"];

      if (speedVal is num && speedVal > 0) {
        speedKmph = speedVal.toDouble();
      } else {
        speedKmph = null;
      }

      // ---------- SWING (Direct Backend Value) ----------
      final rawSwing = src["swing"];
      if (rawSwing is String && rawSwing.trim().isNotEmpty) {
        swingName = _normalizeSwingLabel(rawSwing) ?? inferred["swing"];
      } else {
        swingName = inferred["swing"];
      }

      // ---------- SPIN (Direct Backend Value) ----------
      final rawSpin = src["spin"];
      if (rawSpin is String && rawSpin.trim().isNotEmpty) {
        spinType = _normalizeSpinLabel(rawSpin) ?? inferred["spin"];
      } else {
        spinType = inferred["spin"];
      }

      // ---------- SPIN STRENGTH & TURN ----------
      final rawStrength = src["spin_strength"];
      if (rawStrength is String) {
        spinStrength = rawStrength.toUpperCase();
      } else {
        spinStrength = null;
      }

      // ---------- TRAJECTORY ----------
      trajectory = src["trajectory"] is List
          ? List<dynamic>.from(src["trajectory"])
          : null;
      _showTrajectoryAfterVideo = false;

      // ---------- DRS 2.0 (Projection Based) ----------
      if (src["drs"] is Map<String, dynamic>) {
        final drsMap = Map<String, dynamic>.from(src["drs"]);

        final decisionRaw = drsMap["decision"];
        final confidenceRaw = drsMap["stump_confidence"];

        if (decisionRaw != null) {
          final normalized = decisionRaw.toString().toLowerCase().trim();

          if (normalized.contains("not") && normalized.contains("out")) {
            drsDecision = "NOT OUT";
          } else if (normalized.contains("out")) {
            drsDecision = "OUT";
          } else {
            drsDecision = normalized.toUpperCase();
          }
        } else {
          drsDecision = null;
        }

        if (confidenceRaw is num) {
          stumpConfidence = confidenceRaw.toDouble().clamp(0.0, 1.0);
        } else {
          stumpConfidence = 0.0;
        }
      } else {
        drsDecision = null;
        stumpConfidence = 0.0;
      }
    });
    // Review prompt removed (manual rating only).
  }

  // --------------- SEND TO FASTAPI -------------------
  Future<Map<String, dynamic>?> _sendToBackend(File file) async {
    try {
      final request = http.MultipartRequest("POST", Uri.parse(backendUrl));

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final token = await user.getIdToken(true);
          if (token != null && token.isNotEmpty) {
            request.headers["Authorization"] = "Bearer $token";
          }
        } catch (_) {}
      }

      request.files.add(await http.MultipartFile.fromPath("file", file.path));

      final streamed = await request.send();
      final responseString = await streamed.stream.bytesToString();

      print("=========== BACKEND RESPONSE START ===========");
      print(responseString);
      print("=========== BACKEND RESPONSE END ===========");
      debugPrint("RAW LENGTH => ${responseString.length}");

      if (streamed.statusCode == 200) {
        return json.decode(responseString);
      } else if (streamed.statusCode == 401) {
        throw Exception("USER_NOT_AUTHENTICATED");
      } else if (streamed.statusCode == 403) {
        throw Exception("TRAINING_LIMIT_REACHED");
      } else {
        debugPrint("SERVER ERROR: ${streamed.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("UPLOAD ERROR: $e");
      return null;
    }
  }

  // --------------- ERROR POPUP -------------------
  void _showError(BuildContext context, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // --------------- METRIC BOX -------------------
  Widget _metricBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------- CHART PLACEHOLDER -------------------
  Widget _chartPlaceholder(String title) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Center(
        child: Text(
          title,
          style: GoogleFonts.poppins(fontSize: 18, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _trajectoryView() {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _TrajectoryPainter(trajectory!)),
          ),
        ],
      ),
    );
  }

  // --------------- WATCH AD DIALOG -------------------
  Future<void> _showWatchAdDialog(BuildContext ctx) async {
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => _WatchAdDialog(
        onCreditGranted: () {
          Navigator.of(dialogCtx).pop();
          // Re-trigger pick after credit granted
          _pickVideo(ctx);
        },
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  final List<dynamic> points;

  _TrajectoryPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();

    final xs = points.map((p) => (p["x"] as num).toDouble()).toList();
    final ys = points.map((p) => (p["y"] as num).toDouble()).toList();

    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);

    final dxRange = (maxX - minX) == 0 ? 1 : (maxX - minX);
    final dyRange = (maxY - minY) == 0 ? 1 : (maxY - minY);

    for (int i = 0; i < points.length; i++) {
      final dx = ((xs[i] - minX) / dxRange) * size.width;
      final dy = size.height - ((ys[i] - minY) / dyRange) * size.height;

      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ── Watch Ad Dialog ──────────────────────────────────────────────────────────
class _WatchAdDialog extends StatefulWidget {
  const _WatchAdDialog({required this.onCreditGranted});
  final VoidCallback onCreditGranted;
  @override
  State<_WatchAdDialog> createState() => _WatchAdDialogState();
}

class _WatchAdDialogState extends State<_WatchAdDialog> {
  bool _loading = false;
  String? _message;

  Future<void> _handleWatchAd() async {
    if (_loading) return;
    debugPrint('[AdMob] Watch Ad button tapped (analysis_screen)');
    debugPrint('[AdMob] Ad ready: ${AdMobService.instance.isRewardedAdReady}');
    setState(() {
      _loading = true;
      _message = null;
    });
    final result = await AnalysisCreditService.instance.watchAdForCredit();
    debugPrint('[AdMob] watchAdForCredit result: $result');
    if (!mounted) return;
    setState(() => _loading = false);
    switch (result) {
      case AdWatchResult.rewardEarned:
        debugPrint('[AI] Credit granted — proceeding with analysis');
        widget.onCreditGranted();
        break;
      case AdWatchResult.adNotAvailable:
        debugPrint('[AdMob] Ad not available — showing retry message');
        setState(() => _message = "Ad isn't available right now. Please try again.");
        break;
      case AdWatchResult.adClosedEarly:
        debugPrint('[AdMob] Ad closed early — no reward');
        setState(() => _message = 'Watch the complete ad to earn your analysis.');
        break;
      case AdWatchResult.premiumUser:
        debugPrint('[Premium] Premium user in Watch Ad dialog — closing');
        Navigator.of(context).pop();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0E1621),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '🎬 Watch Ad to Unlock',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Watch a short ad to unlock 4 AI Bowling Analyses.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _message!.startsWith("Ad isn")
                      ? Colors.redAccent
                      : Colors.orangeAccent,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _loading ? null : _handleWatchAd,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'Watch Ad 🎬',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const PremiumScreen(entrySource: 'ad_unlock_premium'),
              ),
            );
          },
          child: const Text(
            'Upgrade to Premium',
            style: TextStyle(
                color: Color(0xFFFFAA00), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
