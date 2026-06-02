import 'dart:io';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import 'onboarding_ui_tokens.dart';

class CricknovaMistakeAnalysisStep extends StatefulWidget {
  final Color teal;
  final String userName;
  final VoidCallback onNext;

  const CricknovaMistakeAnalysisStep({
    super.key,
    required this.teal,
    required this.userName,
    required this.onNext,
  });

  @override
  State<CricknovaMistakeAnalysisStep> createState() => _CricknovaMistakeAnalysisStepState();
}

class _CricknovaMistakeAnalysisStepState extends State<CricknovaMistakeAnalysisStep> {
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _bgCard = Color(0xFF161619);

  VideoPlayerController? _controller;
  bool _videoInitialized = false;
  bool _showFlowchart = false;

  @override
  void initState() {
    super.initState();
    _loadTrialVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadTrialVideo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('trial_video_path');
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        _controller = VideoPlayerController.file(File(path));
        await _controller!.initialize();
        _controller!.setLooping(true);
        _controller!.play();
        if (mounted) {
          setState(() {
            _videoInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading trial video in mistake step: $e");
    }
  }

  Future<void> _populateCoachChatWithMistakeFix() async {
    try {
      final auth = FirebaseAuth.instance;
      final uid = auth.currentUser?.uid ?? 'guest';

      final box = await Hive.openBox("chat_sessions_$uid");
      final raw = (box.get("sessions") as List?)?.cast<Map>() ?? const <Map>[];
      final sessionStore = raw.map((e) => Map<String, dynamic>.from(e)).toList(growable: true);

      // Check if we already inserted the mistake fix chat to avoid duplicates
      final bool alreadyExists = sessionStore.any((s) => s["title"] == "AI Batting Analysis Fix");
      if (alreadyExists) return;

      final String chatId = "mistake_analysis_fix_${DateTime.now().millisecondsSinceEpoch}";
      final List<Map<String, dynamic>> messages = [
        {
          "role": "user",
          "content": "Hi Coach, my AI analysis says my bottom hand grip is too tight on my batting video. How do I fix this mistake?"
        },
        {
          "role": "coach",
          "content": "Hello! I saw your video analysis. A tight bottom hand grip is very common but restricts your wrist movement and causes you to hit cross-batted shots. Here is how we fix it:\n\n1. **Bottom Hand Isolation Drill**: Hold the bat only with your bottom hand (using just 2 fingers and thumb) and practice shadow drives. This forces your top hand to lead.\n2. **Tee Work Focus**: Place a ball on the batting tee. During backswing and downswing, make sure your bottom hand is loose and acting only as a guide, while your top hand generates all the steering and power.\n3. **Grip Pressure Check**: On a scale of 1-10, your top hand pressure should be an 8, and your bottom hand should be a 3. Let's aim to practice this for 10-15 minutes daily!"
        }
      ];

      sessionStore.insert(0, {
        "chat_id": chatId,
        "user_id": uid,
        "title": "AI Batting Analysis Fix",
        "timestamp": DateTime.now().millisecondsSinceEpoch,
        "messages": messages,
      });

      await box.put("sessions", sessionStore);
      debugPrint("SUCCESSFULLY AUTO-POPULATED COACH CHAT WITH MISTAKE DRILLS FOR UID $uid");
    } catch (e) {
      debugPrint("Error populating coach chat: $e");
    }
  }

  void _onCheckHowToFix() {
    setState(() {
      _showFlowchart = true;
    });
    // In background, populate coach chat with the drills
    _populateCoachChatWithMistakeFix();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isSmall = screenHeight < 820;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            "AI BATTING MISTAKE DETECTED",
            style: OnboardingTextStyles.uiMono(
              color: const Color(0xFFFF4D4D),
              fontSize: isSmall ? 10 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Check Your Technique Fix",
            style: OnboardingTextStyles.serif(
              color: OnboardingColors.textPrimary,
              fontSize: isSmall ? 32 : 38,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),

          // Video Card showing batting video and mistake warning
          Container(
            height: isSmall ? 180 : 230,
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: OnboardingColors.borderDefault,
                width: 1.2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_videoInitialized && _controller != null)
                    Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey[900],
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.sports_cricket,
                        size: 64,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                  // Dark vignette gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.2),
                          Colors.black.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                  // Warning details banner
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E0E0E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF4D4D).withOpacity(0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFFF4D4D),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "MISTAKE FOUND",
                                  style: OnboardingTextStyles.uiMono(
                                    color: const Color(0xFFFF4D4D),
                                    fontSize: isSmall ? 8.5 : 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  "Bottom Hand Grip Too Tight",
                                  style: OnboardingTextStyles.uiSans(
                                    color: Colors.white,
                                    fontSize: isSmall ? 13 : 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
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
          const SizedBox(height: 20),

          // Main Interactive Action
          if (!_showFlowchart) ...[
            SizedBox(
              height: isSmall ? 52 : 60,
              child: ElevatedButton.icon(
                onPressed: _onCheckHowToFix,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: OnboardingTextStyles.uiSans(
                    fontSize: isSmall ? 15 : 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.bolt, size: 20),
                label: const Text("Check How to Fix Mistakes"),
              ),
            ),
          ] else ...[
            // Show Animated Flowchart
            _buildFlowchart(isSmall),
            const SizedBox(height: 20),
            // Premium Conversion Copy
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _gold.withOpacity(0.24),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    "and many features you'll get in premium",
                    style: OnboardingTextStyles.uiSans(
                      color: OnboardingColors.textSecondary,
                      fontSize: isSmall ? 12 : 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: OnboardingTextStyles.uiSans(
                        color: Colors.white,
                        fontSize: isSmall ? 13 : 15,
                        height: 1.35,
                      ),
                      children: [
                        const TextSpan(text: "Increase your selection chances by "),
                        TextSpan(
                          text: "37%",
                          style: TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(text: " by using just "),
                        TextSpan(
                          text: "30 days",
                          style: TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(text: " CrickNova Premium!"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Checkout Continue Button
            SizedBox(
              height: isSmall ? 52 : 60,
              child: ElevatedButton(
                onPressed: widget.onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.teal,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: OnboardingTextStyles.uiSans(
                    fontSize: isSmall ? 15 : 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text("Continue to Checkout"),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFlowchart(bool isSmall) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          _buildFlowStep(
            icon: Icons.video_camera_back_rounded,
            color: widget.teal,
            title: "Batting Video Uploaded",
            subtitle: "Successful 1 Free Analysis check.",
            isSmall: isSmall,
          ),
          _buildFlowConnector(widget.teal),
          _buildFlowStep(
            icon: Icons.auto_awesome,
            color: _gold,
            title: "CrickNova AI Model",
            subtitle: "Detected excess bottom-hand dominance.",
            isSmall: isSmall,
          ),
          _buildFlowConnector(_gold),
          _buildFlowStep(
            icon: Icons.warning_rounded,
            color: const Color(0xFFFF4D4D),
            title: "Mistake Flagged",
            subtitle: "Bottom Hand Grip Too Tight.",
            isSmall: isSmall,
          ),
          _buildFlowConnector(const Color(0xFFFF4D4D)),
          _buildFlowStep(
            icon: Icons.chat_bubble_rounded,
            color: widget.teal,
            title: "Auto-Sent to Chat Coach",
            subtitle: "Drills & checklists transferred automatically.",
            isSmall: isSmall,
          ),
          _buildFlowConnector(widget.teal),
          _buildFlowStep(
            icon: Icons.check_circle_rounded,
            color: _gold,
            title: "Coach Session Populated!",
            subtitle: "Ready inside the CrickNova AI Chat tab.",
            isSmall: isSmall,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFlowStep({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isSmall,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: isSmall ? 36 : 44,
          height: isSmall ? 36 : 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.08),
            border: Border.all(
              color: color,
              width: 1.5,
            ),
          ),
          child: Icon(icon, color: color, size: isSmall ? 18 : 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: OnboardingTextStyles.uiSans(
                  color: Colors.white,
                  fontSize: isSmall ? 14 : 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: OnboardingTextStyles.uiSans(
                  color: Colors.white70,
                  fontSize: isSmall ? 11 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFlowConnector(Color color) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 1.5,
        height: 24,
        margin: const EdgeInsets.only(left: 18, top: 2, bottom: 2),
        color: color.withOpacity(0.5),
      ),
    );
  }
}
