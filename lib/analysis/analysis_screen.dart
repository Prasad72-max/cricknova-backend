import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../premium/premium_screen.dart';

import 'analysis_result_screen.dart';
import '../ai_coach/ai_coach_screen.dart';

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

  // CHANGE THIS TO YOUR IP:
  final String backendUrl = "https://cricknova-backend.onrender.com/training/analyze";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          "Analysis",
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
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
                  ? (spinStrength != null && spinStrength != "NONE"
                      ? "${spinType!} • $spinStrength"
                      : spinType!)
                  : "NA",
              icon: Icons.autorenew,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (speedKmph == null && swingName == null && spinType == null && spinStrength == null)
                  ? null
                  : () async {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AICoachScreen(
                            initialQuestion: "Analyze my batting mistake on this delivery",
                            context: {
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
            (!_showTrajectoryAfterVideo || trajectory == null || trajectory!.isEmpty)
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
            )
          ],
        ),
      ),
    );
  }

  // --------------- PICK VIDEO -------------------
  Future<void> _pickVideo(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.video);

    if (picked == null) return;

    final file = File(picked.files.single.path!);

    setState(() => _loading = true);

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
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
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

    setState(() {
      // ---------- NORMALIZE SOURCE ----------
      final Map<String, dynamic> src =
          (responseData["data"] is Map<String, dynamic>)
              ? Map<String, dynamic>.from(responseData["data"])
              : responseData;

      // ---------- SPEED (FULLTRACK STYLE) ----------
      final speedVal = src["speed_kmph"];
      speedType = src["speed_type"];

      if (speedVal is num && speedVal > 0) {
        speedKmph = speedVal.toDouble();
      } else {
        speedKmph = null;
      }

      // ---------- SWING (USE BACKEND VALUE EXACTLY) ----------
      final rawSwing = src["swing"];
      if (rawSwing is String && rawSwing.trim().isNotEmpty) {
        swingName = rawSwing.trim();
      } else {
        swingName = null;
      }

      // ---------- SPIN (USE BACKEND VALUE EXACTLY) ----------
      final rawSpin = src["spin"];
      if (rawSpin is String && rawSpin.trim().isNotEmpty) {
        spinType = rawSpin.trim();
      } else {
        spinType = null;
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
          : [];

      _showTrajectoryAfterVideo = trajectory!.isNotEmpty;
    });
  }

  // --------------- SEND TO FASTAPI -------------------
  Future<Map<String, dynamic>?> _sendToBackend(File file) async {
    try {
      final request = http.MultipartRequest(
        "POST",
        Uri.parse(backendUrl),
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      final token = await user.getIdToken(true);
      if (token.isEmpty) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      // Canonical Authorization header
      request.headers["Authorization"] = "Bearer $token";

      request.files.add(
        await http.MultipartFile.fromPath("file", file.path),
      );

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
          )
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
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
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
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 18,
            color: Colors.black54,
          ),
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
            child: Image.asset(
              "assets/pitch_bg.png",
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.black,
                );
              },
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _TrajectoryPainter(trajectory!),
            ),
          ),
        ],
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
