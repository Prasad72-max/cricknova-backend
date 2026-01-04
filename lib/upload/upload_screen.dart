import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import '../services/premium_service.dart';
import '../premium/premium_screen.dart';

class TrajectoryPainter extends CustomPainter {
  final List<dynamic> points;

  TrajectoryPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    return; // ball path completely disabled
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? video;
  VideoPlayerController? controller;

  bool uploading = false;
  bool showTrajectory = false;

  double? speed;
  String? spin;
  String? swing;

  List<dynamic>? trajectory = const [];

  bool showDRS = false;
  String? drsResult;

  bool showCoach = false;
  String? coachReply;

  Future<void> pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);

    if (picked == null) return;

    video = File(picked.path);

    controller?.dispose();
    controller = VideoPlayerController.file(video!)
      ..initialize().then((_) {
        setState(() {});
        controller!.play();
      });

    setState(() {
      uploading = true;
      showTrajectory = false;
      showDRS = false;
      drsResult = null;
    });

    final uri = Uri.parse("https://cricknova-backend.onrender.com/training/analyze");
    final request = http.MultipartRequest("POST", uri);
    request.headers["Accept"] = "application/json";
    request.files.add(await http.MultipartFile.fromPath("file", video!.path));

    try {
      final response = await request.send();
      print("UPLOAD STATUS => ${response.statusCode}");
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        print("ANALYSIS RESPONSE => $data");
        setState(() {
          final analysis = data["analysis"] ?? data;
          print("ANALYSIS KEYS => ${analysis.keys}");

          final rawSpeed =
              analysis["speed_kmph"] ??
              analysis["speed_mph"] ??
              analysis["speed"];

          double? parsedSpeed;
          if (rawSpeed is num) {
            parsedSpeed = rawSpeed.toDouble();
          } else if (rawSpeed is String) {
            parsedSpeed = double.tryParse(rawSpeed);
          }
          speed = parsedSpeed;

          final swingVal = analysis["swing"]?.toString().toLowerCase();

          // SAFETY CAMERA-CORRECTION (display only)
          if (swingVal == "inswing") {
            swing = "OUTSWING";
          } else if (swingVal == "outswing") {
            swing = "INSWING";
          } else {
            swing = swingVal?.toUpperCase() ?? "NA";
          }

          final spinVal = analysis["spin"];
          spin = spinVal?.toString().toUpperCase() ?? "NA";

          trajectory = const [];
          showTrajectory = false;

          print("UI STATE => speed=$speed swing=$swing spin=$spin");
        });
      } else {
        final err = await response.stream.bytesToString();
        print("UPLOAD ERROR => $err");
      }
    } catch (e) {
      print("UPLOAD EXCEPTION => $e");
    }

    setState(() => uploading = false);
  }

  Future<void> runDRS() async {
    if (video == null) return;

    setState(() {
      showDRS = true;
      drsResult = "Reviewing decision...";
    });

    final uri = Uri.parse("https://cricknova-backend.onrender.com/training/drs");
    final request = http.MultipartRequest("POST", uri);
    request.headers["Accept"] = "application/json";
    request.files.add(await http.MultipartFile.fromPath("file", video!.path));

    try {
      final response = await request.send();
      print("DRS STATUS => ${response.statusCode}");
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);

        final drs = data["drs"];
        final decision = drs?["decision"]?.toString().toUpperCase() ?? "UNKNOWN";
        final reason = drs?["reason"]?.toString() ?? "";

        setState(() {
          drsResult = "$decision\n$reason";
        });
      } else {
        setState(() {
          drsResult = "DRS FAILED\nServer error";
        });
      }
    } catch (e) {
      setState(() {
        drsResult = "DRS FAILED\nConnection error";
      });
    }
  }

  Future<void> runCoach() async {
    final isPremium = await PremiumService.isPremium();
    if (!isPremium) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
      }
      return;
    }

    if (video == null) {
      setState(() {
        showCoach = true;
        coachReply = "No analysis data available yet.";
      });
      return;
    }
    if (uploading) {
      setState(() {
        showCoach = true;
        coachReply = "Analysis in progress. Please wait.";
      });
      return;
    }

    setState(() {
      showCoach = true;
      coachReply = "Analyzing your batting...";
    });

    final uri = Uri.parse("https://cricknova-backend.onrender.com/coach/analyze");

    try {
      final request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";

      // send video (REQUIRED by backend)
      request.files.add(
        await http.MultipartFile.fromPath("file", video!.path),
      );

      // optional metadata (safe)
      request.fields["speed_kmph"] = speed?.toString() ?? "";
      request.fields["swing"] = swing ?? "";
      request.fields["spin"] = spin ?? "";

      final response = await request.send();
      print("COACH STATUS => ${response.statusCode}");

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);

        setState(() {
          coachReply =
              data["coach_feedback"] ??
              "No coaching feedback received";
        });
      } else {
        setState(() {
          coachReply = "Coach unavailable. Server error.";
        });
      }
    } catch (e) {
      setState(() {
        coachReply = "Coach unavailable. Connection error.";
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Upload Training Video"),
      ),
      body: controller == null
          ? Center(
              child: GestureDetector(
                onTap: pickAndUpload,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.blueAccent, Colors.deepPurpleAccent],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "Upload Training Video",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: VideoPlayer(controller!),
                  ),
                ),

                // LEFT SIDEBAR
                Positioned(
                  left: 0,
                  top: 100,
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _metric("Speed", speed != null ? "${speed!.toStringAsFixed(1)} km/h" : "--"),
                        _metric(
                          "Swing",
                          swing != null ? swing!.toUpperCase() : "--",
                        ),
                        _metric("Spin", spin != null ? spin!.toUpperCase() : "--"),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: runDRS,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                "DRS",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: runCoach,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                "COACH",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (showDRS)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.75),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "DRS REVIEW",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              drsResult ?? "",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 30),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  showDRS = false;
                                });
                              },
                              child: const Text("Close"),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),

                if (showCoach)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "AI COACH REVIEW",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                coachReply ?? "",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(height: 30),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  showCoach = false;
                                });
                              },
                              child: const Text("Close"),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),

                if (uploading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
