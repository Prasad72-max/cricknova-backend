import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';

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
  double? speedKmph;
  String speedType = "unavailable";
  String speedNote = "";

  String swing = "NA";
  String spin = "NA";

  String spinStrength = "NONE";
  double spinTurnDeg = 0.0;
  @override
  void initState() {
    super.initState();
    debugPrint("UPLOAD_SCREEN initState");
    final user = FirebaseAuth.instance.currentUser;
    debugPrint("UPLOAD_SCREEN user=${user?.uid}");
    PremiumService.premiumNotifier.addListener(() {
      if (mounted) setState(() {});
    });
  }
  File? video;
  VideoPlayerController? controller;

  bool uploading = false;
  bool showTrajectory = false;

  List<dynamic>? trajectory = const [];

  bool showDRS = false;
  String? drsResult;
  bool drsLoading = false;

  bool showCoach = false;
  String? coachReply;

  void _showVideoRulesThenPick() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "🎥 Video Recording Guidelines",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "• Record in normal speed (no slow motion)\n"
                "• Ball must be clearly visible\n"
                "• Keep camera stable\n"
                "• Full pitch & batsman visible\n"
                "• Prefer side-on or behind bowler angle\n"
                "• Avoid heavy zoom or filters\n\n"
                "⚠️ AI accuracy depends on video quality.",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    debugPrint("UPLOAD_SCREEN → pickAndUpload triggered");
                    pickAndUpload();
                  },
                  child: const Text(
                    "Next",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  Future<void> pickAndUpload() async {
    debugPrint("UPLOAD_SCREEN → pickAndUpload start");

    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    video = File(picked.path);

    controller?.dispose();
    controller = VideoPlayerController.file(video!)
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });

    if (mounted) {
      setState(() {
        uploading = true;
        showTrajectory = false;
        showDRS = false;
        drsResult = null;
      });
    }

    final uri = Uri.parse(
      "https://cricknova-backend.onrender.com/training/analyze",
    );

    try {
      final request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("USER_NOT_AUTHENTICATED");

      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      request.headers["Authorization"] = "Bearer $token";
      request.files.add(
        await http.MultipartFile.fromPath("file", video!.path),
      );

      final response = await request.send()
          .timeout(const Duration(seconds: 40));

      final respStr = await response.stream.bytesToString();
      debugPrint("UPLOAD RESPONSE ${response.statusCode} => $respStr");

      if (response.statusCode != 200) {
        throw Exception("UPLOAD_FAILED");
      }

      final decoded = jsonDecode(respStr);
      final analysis = decoded["analysis"] ?? decoded;

      final dynamic speedVal =
          analysis["speed_kmph"] ?? decoded["speed_kmph"];

      final dynamic speedTypeVal =
          analysis["speed_type"] ?? decoded["speed_type"];

      final dynamic speedNoteVal =
          analysis["speed_note"] ?? decoded["speed_note"];

      if (speedVal is num && speedVal > 0) {
        speedKmph = speedVal.toDouble();
        speedType = speedTypeVal?.toString() ?? "estimated";
        speedNote = speedNoteVal?.toString() ?? "";
      } else {
        speedKmph = null;
        speedType = "unavailable";
        speedNote = speedNoteVal?.toString() ?? "";
      }
      if (!mounted) return;

      setState(() {
        // -------- SWING (DIRECT FROM BACKEND) --------
        final rawSwing = analysis["swing"];
        if (rawSwing is String && rawSwing.isNotEmpty) {
          swing = rawSwing.toUpperCase();
        } else {
          swing = "OUTSWING";
        }

        // -------- SPIN (DIRECT FROM BACKEND) --------
        final rawSpin = analysis["spin"];
        if (rawSpin is String && rawSpin.isNotEmpty) {
          spin = rawSpin.toUpperCase();
        } else {
          spin = "OFF SPIN";
        }

        // -------- SPIN STRENGTH & TURN (BACKEND: NUMERIC STRENGTH 0–1) --------
        final rawStrength = analysis["spin_strength"];
        if (rawStrength is num) {
          // Backend now returns numeric strength (0–1)
          spinStrength = "${(rawStrength * 100).toStringAsFixed(0)}%";
        } else if (rawStrength is String && rawStrength.isNotEmpty) {
          spinStrength = rawStrength.toUpperCase();
        } else {
          spinStrength = "0%";
        }

        // Spin turn degree no longer shown in UI
        spinTurnDeg = 0.0;

        trajectory = const [];
        showTrajectory = false;

        controller?.play();
      });
    } catch (e) {
      debugPrint("UPLOAD ERROR => $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Analysis failed. Please try again."),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          uploading = false;
        });
      }
    }
  }

  Future<void> runDRS() async {
    if (video == null || drsLoading) return;

    setState(() {
      showDRS = true;
      drsLoading = true;
      drsResult = "Reviewing decision...";
    });

    final uri =
        Uri.parse("https://cricknova-backend.onrender.com/training/drs");

    final request = http.MultipartRequest("POST", uri);
    request.headers["Accept"] = "application/json";

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        drsResult = "USER NOT AUTHENTICATED";
        drsLoading = false;
      });
      return;
    }

    final String? idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      setState(() {
        drsResult = "USER NOT AUTHENTICATED";
        drsLoading = false;
      });
      return;
    }

    request.headers["Authorization"] = "Bearer $idToken";
    request.files.add(
        await http.MultipartFile.fromPath("file", video!.path));

    try {
      final response =
          await request.send().timeout(const Duration(seconds: 40));

      final respStr = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        setState(() {
          drsResult = "DRS FAILED\nServer error";
          drsLoading = false;
        });
        return;
      }

      final data = jsonDecode(respStr);
      final drs = data["drs"];

      if (drs == null || drs is! Map) {
        setState(() {
          drsResult = "DRS DATA INVALID";
          drsLoading = false;
        });
        return;
      }

      final rawDecision = drs["decision"];
      final rawConfidence = drs["stump_confidence"];
      final rawReason = drs["reason"];

      String decisionText =
          rawDecision?.toString().toUpperCase() ?? "UNKNOWN";

      String confidenceText = "";
      if (rawConfidence is num) {
        final percent = rawConfidence.toDouble() * 100;
        confidenceText = " (${percent.toStringAsFixed(0)}%)";
      }

      String reasonText = "";
      if (rawReason is String && rawReason.isNotEmpty) {
        reasonText = "\n$rawReason";
      }

      setState(() {
        drsResult = "$decisionText$confidenceText$reasonText";
        drsLoading = false;
      });
    } catch (e) {
      setState(() {
        drsResult = "DRS FAILED\nConnection error";
        drsLoading = false;
      });
    }
  }

  Future<void> runCoach() async {
    debugPrint("UPLOAD_SCREEN → runCoach start");
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

      // ✅ Send Firebase ID token so backend can identify user & plan
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      final String? token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      request.headers["Authorization"] = "Bearer $token";

      // send video (REQUIRED by backend)
      request.files.add(
        await http.MultipartFile.fromPath("file", video!.path),
      );

      // optional metadata (safe)
      if (speedKmph != null) {
        request.fields["speed_kmph"] = speedKmph!.toString();
      }
      request.fields["swing"] = swing;
      request.fields["spin"] = spin;

      final response = await request.send();
      print("COACH STATUS => ${response.statusCode}");

      final respStr = await response.stream.bytesToString();
      print("COACH RAW RESPONSE => $respStr");

      final data = jsonDecode(respStr);

      // 🔒 Handle premium / limit errors explicitly
      if (response.statusCode == 403) {
        final detail = data["detail"]?.toString() ?? "";

        if (detail.contains("PREMIUM_REQUIRED") ||
            detail.contains("MISTAKE_LIMIT_REACHED") ||
            detail.contains("LIMIT")) {
          if (!mounted) return;

          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) {
              return AlertDialog(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  "Plan Limit Reached 🔒",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: const Text(
                  "Your AI mistake detection limit has ended.\n\nUpgrade to Premium to continue getting advanced AI feedback.",
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        showCoach = false;
                      });
                    },
                    child: const Text(
                      "Later",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const PremiumScreen(entrySource: "mistake_limit"),
                        ),
                      );
                    },
                    child: const Text(
                      "Buy Premium",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          );
          return;
        }
      }

      // 🔐 Redirect ONLY if backend explicitly blocks access
      final bool premiumRequired = data["premium_required"] == true;
      final bool success = data["success"] == true;

      if (premiumRequired && !success) {
        if (!mounted) return;

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Premium Feature 🔒",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: const Text(
                "AI Coach is a premium feature.\n\nUpgrade your plan to unlock personalised batting & bowling analysis from our AI coach.",
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      showCoach = false;
                    });
                  },
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const PremiumScreen(entrySource: "coach"),
                      ),
                    );
                  },
                  child: const Text(
                    "Upgrade",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );

        return;
      }

      if (response.statusCode == 200) {
        // Normal successful coaching reply
        if (data["success"] == true && data["reply"] != null) {
          setState(() {
            coachReply = data["reply"];
          });
        }
        // Vision / tracking failed but coach feedback exists
        else if (data["coach_feedback"] != null) {
          setState(() {
            coachReply = data["coach_feedback"];
          });
        }
        // Fallback when no usable fields are present
        else {
          setState(() {
            coachReply =
                "Analysis completed, but no clear coaching feedback was generated.";
          });
        }
      } else {
        setState(() {
          coachReply =
              "Analysis could not be completed.\nIf this keeps happening, please try again later.";
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
    return WillPopScope(
      onWillPop: () async {
        // Always go back to previous screen, never jump to Home
        Navigator.of(context).pop();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text("Upload Training Video"),
        ),
        body: controller == null
          ? Center(
              child: GestureDetector(
                onTap: _showVideoRulesThenPick,
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
                      _metric(
                        "Speed",
                        speedKmph != null
                            ? ((speedType == "very_slow_estimate" ||
                                    speedType == "camera_normalized" ||
                                    speedType == "video_derived" ||
                                    speedType == "derived_physics")
                                ? "${speedKmph!.toStringAsFixed(1)} km/h"
                                : "${speedKmph!.toStringAsFixed(1)} km/h")
                            : "----",
                      ),
                      if (speedKmph != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            speedType == "measured_release"
                                ? "Measured speed"
                                : speedType == "very_slow_estimate"
                                    ? "Very slow delivery"
                                    : speedType == "camera_normalized"
                                        ? "Estimated from camera motion"
                                        : speedType == "video_derived"
                                            ? "Estimated from video motion"
                                            : speedType == "derived_physics"
                                                ? "Physics fallback estimate"
                                                : "Speed unavailable",
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _metric("Swing", swing),
                        _metric(
                          "Spin",
                          spinStrength != "0%"
                              ? "$spin • $spinStrength"
                              : spin,
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: drsLoading ? null : runDRS,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: drsLoading ? Colors.grey : Colors.redAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: drsLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
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
                          onTap: () async {
                            // Step 1: show preparation message
                            setState(() {
                              showCoach = true;
                              coachReply =
                                  "This may take 1–2 minutes...\nPlease keep the app open ⏳";
                            });

                            // Artificial delay so user understands processing time
                            await Future.delayed(const Duration(seconds: 6));

                            if (!mounted) return;

                            // Step 2: show actual analyzing message
                            setState(() {
                              coachReply = "Analyzing your batting... 🏏";
                            });

                            // Step 3: start backend coach analysis
                            await runCoach();
                          },
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
                              style: TextStyle(
                                color: drsResult != null &&
                                        drsResult!.contains("OUT") &&
                                        !drsResult!.contains("NOT OUT")
                                    ? Colors.red
                                    : drsResult != null &&
                                            drsResult!.contains("NOT OUT")
                                        ? Colors.green
                                        : Colors.orange,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
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
                  Positioned(
                    top: 20,
                    right: 20,
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
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
