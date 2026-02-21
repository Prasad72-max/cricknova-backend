import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
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
  // 🔥 Button Animation Helpers
  double _drsScale = 1.0;
  double _coachScale = 1.0;
  double _uploadScale = 1.0;
  double _drsRotation = 0.0;
  double _coachRotation = 0.0;
  double _uploadRotation = 0.0;

  // Safety: Only give XP once per upload
  bool _uploadXpGiven = false;
  // 🔥 Cost Optimization: Batch Firestore writes
  int _pendingXp = 0;
  int _pendingVideoCount = 0;

  void _pressDown(Function setScale, Function setRotation) {
    HapticFeedback.mediumImpact();
    setState(() {
      setScale(0.92);
      setRotation(0.02);
    });
  }

  void _pressUp(Function setScale, Function setRotation) {
    setState(() {
      setScale(1.0);
      setRotation(0.0);
    });
  }
  double? speedKmph;
  String speedType = "unavailable";
  String speedNote = "";

  String swing = "";
  String spin = "";
  bool analysisLoading = false;

  // 🧠 Rotating Cricket Facts
  final List<String> _cricketFacts = [
    "Did you know? Sachin Tendulkar's bat weighed around 3.2 lbs!",
    "Fun Fact: The first-ever international cricket match was USA vs Canada in 1844.",
    "Elite Tip: A stable head position is the secret to 90% of successful shots.",
    "Fast Fact: Shoaib Akhtar bowled the fastest delivery ever recorded at 161.3 km/h.",
    "Cricket Insight: Yorkers are most effective in the last 4 overs of a T20 match.",
    "Did you know? Muttiah Muralitharan has 800 Test wickets.",
    "Elite Tip: Watch the seam position to read swing early.",
    "Fun Fact: MS Dhoni has the fastest stumping record at 0.08 seconds.",
    "Cricket Insight: Wrist position defines swing direction.",
    "Did you know? Don Bradman averaged 99.94 in Test cricket.",
    "Elite Tip: Strong core muscles improve bowling speed.",
    "Fun Fact: The longest Test match lasted 12 days in 1939.",
    "Cricket Insight: Backlift height influences shot power.",
    "Did you know? Lasith Malinga took 4 wickets in 4 balls twice.",
    "Elite Tip: Landing foot alignment controls bowling direction.",
    "Fun Fact: India won the 1983 World Cup as underdogs.",
    "Cricket Insight: Reverse swing starts when the ball gets rough.",
    "Did you know? AB de Villiers scored the fastest ODI 100 in 31 balls.",
    "Elite Tip: Keep your elbow high during drives.",
    "Fun Fact: Chris Gayle scored the first T20I century.",
    "Cricket Insight: Consistency beats raw pace.",
    "Did you know? Jacques Kallis scored 10,000+ runs and took 250+ wickets.",
    "Elite Tip: Follow through fully to avoid injuries.",
    "Fun Fact: The Ashes started in 1882.",
    "Cricket Insight: Balance at release improves accuracy.",
    "Did you know? Virat Kohli has 70+ international centuries.",
    "Elite Tip: Soft hands help in defensive shots.",
    "Fun Fact: An over once had 8 balls in some countries.",
    "Cricket Insight: Length is more important than speed.",
    "Did you know? Kumar Sangakkara scored four consecutive ODI hundreds in a World Cup.",
    "Elite Tip: Focus on rhythm, not just power.",
    "Fun Fact: Cricket was once played in the Olympics in 1900.",
    "Cricket Insight: Bat speed generates boundary power.",
    "Did you know? Wasim Akram took two hat-tricks in ODIs.",
    "Elite Tip: Keep your eyes level while batting.",
    "Fun Fact: The highest Test total is 952/6 declared.",
    "Cricket Insight: Short run-up can improve control.",
    "Did you know? Ben Stokes played one of the greatest innings in 2019 Ashes.",
    "Elite Tip: Grip pressure affects spin turn.",
    "Fun Fact: The pink ball is used in day-night Tests.",
    "Cricket Insight: Field placement defines bowling strategy.",
    "Did you know? Rohit Sharma has three ODI double centuries.",
    "Elite Tip: Practice under pressure situations.",
    "Fun Fact: The first Cricket World Cup was in 1975.",
    "Cricket Insight: Seam upright means better swing.",
    "Did you know? Glenn McGrath took 563 Test wickets.",
    "Elite Tip: Mental strength wins close matches.",
    "Fun Fact: Brendon McCullum scored 158 in the first IPL match.",
    "Cricket Insight: Footwork is the foundation of batting.",
    "Elite Tip: Recovery and sleep boost performance."
  ];
  int _currentFactIndex = 0;
  Timer? _factTimer;

  String spinStrength = "NONE";
  double spinTurnDeg = 0.0;

  Future<void> _incrementTotalVideos() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final plan = PremiumService.plan;

    // 🔹 IN_1999 → instant Firestore write
    if (plan == "IN_1999") {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .set({
        "totalVideos": FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
    // 🔹 IN_499 → batched Firestore write
    else if (plan == "IN_499") {
      _pendingVideoCount += 1;

      if (_pendingVideoCount >= 5) {
        await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .set({
          "totalVideos": FieldValue.increment(_pendingVideoCount),
        }, SetOptions(merge: true));

        _pendingVideoCount = 0;
      }
    }
    // 🔹 Lower plans → Hive only
    else {
      final box = await Hive.openBox('localStats');
      int current = box.get('totalVideos', defaultValue: 0);
      await box.put('totalVideos', current + 1);
    }
  }

  Future<void> _addXP(int amount) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final plan = PremiumService.plan;

    // 🔹 IN_1999 → instant Firestore write
    if (plan == "IN_1999") {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .set({
        "xp": FieldValue.increment(amount),
      }, SetOptions(merge: true));
    }
    // 🔹 IN_499 → batched Firestore write
    else if (plan == "IN_499") {
      _pendingXp += amount;

      if (_pendingXp >= 100) {
        await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .set({
          "xp": FieldValue.increment(_pendingXp),
        }, SetOptions(merge: true));

        _pendingXp = 0;
      }
    }
    // 🔹 Lower plans → Hive only
    else {
      final box = await Hive.openBox('localStats');
      int current = box.get('xp', defaultValue: 0);
      await box.put('xp', current + amount);
    }
  }
  @override
  void initState() {
    super.initState();
    debugPrint("UPLOAD_SCREEN initState");
    final user = FirebaseAuth.instance.currentUser;
    debugPrint("UPLOAD_SCREEN user=${user?.uid}");
    PremiumService.premiumNotifier.addListener(() {
      if (mounted) setState(() {});
    });
    _factTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      setState(() {
        _currentFactIndex =
            (_currentFactIndex + 1) % _cricketFacts.length;
      });
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
        analysisLoading = true;
        showTrajectory = false;
        showDRS = false;
        drsResult = null;
        swing = "";
        spin = "";
        // Reset XP guard at the start of upload
        _uploadXpGiven = false;
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
      // ✅ Increment total uploaded videos (only on successful analysis)
      await _incrementTotalVideos();

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

      // 🔥 Save speed to Hive for graph (flat list system)
      if (speedKmph != null) {
        final box = await Hive.openBox('speedBox');

        final stored = box.get('allSpeeds') as List?;
        List<double> allSpeeds = [];

        if (stored != null) {
          allSpeeds =
              stored.map((e) => (e as num).toDouble()).toList();
        }

        allSpeeds.add(speedKmph!);

        await box.put('allSpeeds', allSpeeds);

        debugPrint("HIVE SPEED UPDATED => $allSpeeds");
      }
      if (!mounted) return;

      setState(() {
        // -------- SWING (Direct Backend Value) --------
        final rawSwing = analysis["swing"];
        if (rawSwing is String && rawSwing.trim().isNotEmpty) {
          swing = rawSwing.trim().toUpperCase();
        } else {
          swing = "STRAIGHT";
        }

        // -------- SPIN (Direct Backend Value) --------
        final rawSpin = analysis["spin"];
        if (rawSpin is String && rawSpin.trim().isNotEmpty) {
          spin = rawSpin.trim().toUpperCase();
        } else {
          spin = "NO SPIN";
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

        analysisLoading = false;

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

      String decisionText = "UNKNOWN";

      if (rawDecision != null) {
        final normalized =
            rawDecision.toString().toLowerCase().trim();

        if (normalized.contains("not") &&
            normalized.contains("out")) {
          decisionText = "NOT OUT";
        } else if (normalized.contains("out")) {
          decisionText = "OUT";
        } else {
          decisionText = normalized.toUpperCase();
        }
      }

      String confidenceText = "";
      if (rawConfidence is num && rawConfidence > 0) {
        final percent = rawConfidence.toDouble() * 100;
        confidenceText =
            " (${percent.toStringAsFixed(0)}%)";
      }

      setState(() {
        drsResult = "$decisionText$confidenceText";
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

        // 🎯 Give 20 XP when AI Coach is successfully used
        if (!_uploadXpGiven) {
          await _addXP(20);
          _uploadXpGiven = true;
        }

        if (data["success"] == true && data["reply"] != null) {
          setState(() {
            coachReply = data["reply"];
          });
        }
        else if (data["coach_feedback"] != null) {
          setState(() {
            coachReply = data["coach_feedback"];
          });
        }
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
    _factTimer?.cancel();
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 🏏 Mode Selection Label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                    ),
                    child: const Text(
                      "🏏 Batting Analysis Mode",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 💡 Instruction Tip Box
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 30),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Text(
                      "Tip: Ensure your full body is visible from the side for better AI analysis.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 🎥 Upload Button
                  GestureDetector(
                    onTapDown: (_) => _pressDown((v) => _uploadScale = v, (r) => _uploadRotation = r),
                    onTapUp: (_) => _pressUp((v) => _uploadScale = v, (r) => _uploadRotation = r),
                    onTapCancel: () => _pressUp((v) => _uploadScale = v, (r) => _uploadRotation = r),
                    onTap: _showVideoRulesThenPick,
                    child: AnimatedRotation(
                      turns: _uploadRotation,
                      duration: const Duration(milliseconds: 120),
                      child: AnimatedScale(
                        scale: _uploadScale,
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutBack,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.blueAccent, Colors.deepPurpleAccent],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepPurpleAccent.withOpacity(0.6),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
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
                    ),
                  ),
                ],
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
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _metric(
                            "Speed",
                            analysisLoading
                                ? "Analyzing..."
                                : (speedKmph != null
                                    ? "${speedKmph!.toStringAsFixed(1)} km/h"
                                    : "----"),
                          ),
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
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _metric(
                            "Swing",
                            analysisLoading
                                ? "Analyzing..."
                                : (swing.isNotEmpty ? swing : "----"),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _metric(
                            "Spin",
                            analysisLoading
                                ? "Analyzing..."
                                : (spin.isNotEmpty
                                    ? (spinStrength != "0%"
                                        ? "$spin • $spinStrength"
                                        : spin)
                                    : "----"),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTapDown: (_) => _pressDown((v) => _drsScale = v, (r) => _drsRotation = r),
                          onTapUp: (_) => _pressUp((v) => _drsScale = v, (r) => _drsRotation = r),
                          onTapCancel: () => _pressUp((v) => _drsScale = v, (r) => _drsRotation = r),
                          onTap: drsLoading ? null : runDRS,
                          child: AnimatedRotation(
                            turns: _drsRotation,
                            duration: const Duration(milliseconds: 120),
                            child: AnimatedScale(
                              scale: _drsScale,
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOutBack,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.redAccent, Colors.deepOrange],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withOpacity(0.6),
                                      blurRadius: 18,
                                      spreadRadius: 1,
                                    ),
                                  ],
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
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTapDown: (_) => _pressDown((v) => _coachScale = v, (r) => _coachRotation = r),
                          onTapUp: (_) => _pressUp((v) => _coachScale = v, (r) => _coachRotation = r),
                          onTapCancel: () => _pressUp((v) => _coachScale = v, (r) => _coachRotation = r),
                          onTap: () async {
                            setState(() {
                              showCoach = true;
                              coachReply =
                                  "This may take 1–2 minutes...\nPlease keep the app open ⏳";
                            });

                            await Future.delayed(const Duration(seconds: 6));
                            if (!mounted) return;

                            setState(() {
                              coachReply = "Analyzing your batting... 🏏";
                            });

                            await runCoach();
                          },
                          child: AnimatedRotation(
                            turns: _coachRotation,
                            duration: const Duration(milliseconds: 120),
                            child: AnimatedScale(
                              scale: _coachScale,
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOutBack,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.blueAccent, Colors.cyan],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blueAccent.withOpacity(0.6),
                                      blurRadius: 18,
                                      spreadRadius: 1,
                                    ),
                                  ],
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
                                        drsResult!.startsWith("OUT")
                                    ? Colors.red
                                    : drsResult != null &&
                                            drsResult!.startsWith("NOT OUT")
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
                if (analysisLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.55),
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 28),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 600),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.3),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              _cricketFacts[_currentFactIndex],
                              key: ValueKey(_cricketFacts[_currentFactIndex]),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: value == "Analyzing..."
                ? TweenAnimationBuilder<double>(
                    key: const ValueKey("analyzing_clean"),
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOut,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: scale,
                          child: const Text(
                            "Analyzing...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                    onEnd: () {
                      if (mounted) setState(() {});
                    },
                  )
                : Text(
                    value,
                    key: ValueKey(value),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
