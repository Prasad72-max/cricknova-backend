import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
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
    if (!PremiumService.isPremium ||
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
    } finally {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canCompare = leftVideo != null && rightVideo != null;

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
              Row(
                children: [
                  Expanded(child: videoCard(isLeft: true)),
                  const SizedBox(width: 16),
                  Expanded(child: videoCard(isLeft: false)),
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
                      color: canCompare ? Colors.greenAccent : Colors.white24,
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

              if (comparing)
                const Center(child: CircularProgressIndicator()),

              if (diffResult != null)
                Container(
                  margin: const EdgeInsets.only(top: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    diffResult!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
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
                    child: Container(
                      color: Colors.black,
                      child: safeVideo(controller),
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Icon(
                      Icons.video_library,
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
