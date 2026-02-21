import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import 'package:hive/hive.dart';

class AnalyseYourselfScreen extends StatefulWidget {
  const AnalyseYourselfScreen({super.key});

  @override
  State<AnalyseYourselfScreen> createState() => _AnalyseYourselfScreenState();
}

class _AnalyseYourselfScreenState extends State<AnalyseYourselfScreen> {

  File? leftVideo;
  File? rightVideo;

  VideoPlayerController? leftController;
  VideoPlayerController? rightController;

  final ImagePicker picker = ImagePicker();

  bool comparing = false;
  String? diffResult;

  bool isSynced = false;
  int _currentFactIndex = 0;
  late List<String> cricketFacts;
  Timer? _factTimer;

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
  }

  Future<void> pickVideo({required bool isLeft}) async {
    final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    final File file = File(picked.path);

    if (isLeft) {
      leftController?.dispose();
      leftController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {});
          leftController!.play();
        });
      leftVideo = file;
    } else {
      rightController?.dispose();
      rightController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {});
          rightController!.play();
        });
      rightVideo = file;
    }

    setState(() {});
  }

  Future<void> runCompare() async {
    // 🔒 Compare feature allowed ONLY for IN_499 and IN_1999
    if (!PremiumService.isLoaded ||
        !PremiumService.isPremium ||
        (PremiumService.plan != "IN_499" && PremiumService.plan != "IN_1999")) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "🔒 Analyse Yourself is available in ₹499 / ₹1999 plans.",
            ),
            backgroundColor: Colors.black87,
          ),
        );
      }
      return;
    }

    final remaining = await PremiumService.getCompareLimit();
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Your Analyse Yourself limit is over."),
            backgroundColor: Colors.black87,
          ),
        );
      }
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
        _currentFactIndex =
            (_currentFactIndex + 1) % cricketFacts.length;
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

    request.files.add(await http.MultipartFile.fromPath("left", leftVideo!.path));
    request.files.add(await http.MultipartFile.fromPath("right", rightVideo!.path));

    try {
      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);

        setState(() {
          diffResult = data["difference"] ?? "No difference returned.";
        });
        // 🎯 Tier-based XP update
        final plan = PremiumService.plan;

        // 🔹 High tier plans → Firestore
        if (plan == "IN_499" || plan == "IN_1999") {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'xp': FieldValue.increment(30),
          }, SetOptions(merge: true));
        } 
        // 🔹 Lower plans → Hive only
        else {
          final box = await Hive.openBox('localStats');
          int currentXp = box.get('xp', defaultValue: 0);
          await box.put('xp', currentXp + 30);
        }

        await PremiumService.consumeCompare();
      } else if (response.statusCode == 401) {
        setState(() {
          diffResult = "Session expired. Please log in again.";
        });
      } else if (response.statusCode == 403) {
        try {
          final data = jsonDecode(body);
          if (data["detail"] == "COMPARE_LIMIT_REACHED") {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PremiumScreen()),
            );
            return;
          }
        } catch (_) {}

        setState(() {
          diffResult = "Compare limit reached.";
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Analyse Yourself'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF38BDF8), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withOpacity(0.6),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Text(
                      "VS",
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: canCompare ? runCompare : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: canCompare ? const Color(0xFF38BDF8) : Colors.white24,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'COMPARE',
                        style: TextStyle(
                          color: canCompare ? Colors.black : Colors.white54,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

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
                    border: Border.all(color: const Color(0xFF38BDF8), width: 1),
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
      ),
    );
  }

  Widget videoCard({required bool isLeft}) {
    final VideoPlayerController? controller =
        isLeft ? leftController : rightController;
    final bool hasVideo =
        controller != null && controller.value.isInitialized;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: hasVideo
                ? AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              VideoPlayer(controller),
                            ],
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                "READY",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Icon(
                      Icons.video_library_outlined,
                      color: Colors.white38,
                      size: 48,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: () => pickVideo(isLeft: isLeft),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    isLeft ? 'ADD\nVID 1' : 'ADD\nVID 2',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
