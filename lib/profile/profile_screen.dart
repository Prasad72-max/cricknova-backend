import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../premium/premium_screen.dart';
import '../auth/login_screen.dart';
import '../services/premium_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String? userEmail;

  File? profileImage;
  final ImagePicker _picker = ImagePicker();

double maxSpeed = 0;
int totalVideos = 0;
int totalCertificates = 0;
int totalXP = 0;
int chatXP = 0;
int remainingXP = 0;
Box? _statsBox;
int nextMilestone = 50000;

  @override
  void initState() {
    super.initState();
    loadProfileData();
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    nameController.text = prefs.getString("profileName") ?? "Player";
    final imagePath = prefs.getString("profileImagePath");
    if (imagePath != null && imagePath.isNotEmpty) {
      profileImage = File(imagePath);
    }
    final user = FirebaseAuth.instance.currentUser;
    userEmail = user?.email;

    final uid = user?.uid ?? "guest";

    // 🔥 Load XP & stats from Hive (local storage)
    _statsBox ??= await Hive.openBox("local_stats_$uid");
    final box = _statsBox!;

    totalXP = box.get("xp", defaultValue: 0);
    totalVideos = box.get("totalVideos", defaultValue: 0);
    maxSpeed = box.get("maxSpeed", defaultValue: 0.0);

    final claimed50 = box.get("claimed_50000", defaultValue: false);
    final claimed5L = box.get("claimed_500000", defaultValue: false);
    final claimed10L = box.get("claimed_1000000", defaultValue: false);
    final claimed20L = box.get("claimed_2000000", defaultValue: false);

    if (!claimed50) {
      nextMilestone = 50000;
    } else if (!claimed5L) {
      nextMilestone = 500000;
    } else if (!claimed10L) {
      nextMilestone = 1000000;
    } else if (!claimed20L) {
      nextMilestone = 2000000;
    } else {
      nextMilestone = 2000000;
    }

    // Calculate remaining XP for current milestone
    remainingXP = nextMilestone - totalXP;
    if (remainingXP < 0) remainingXP = 0;

    // 💬 Load AI Chat XP count (still from SharedPreferences)
    chatXP = prefs.getInt("chatXP_$uid") ?? 0;

    final savedCerts = prefs.getStringList("savedCertificates") ?? [];

    // Remove duplicate certificate paths
    final uniqueCerts = savedCerts.toSet().toList();

    totalCertificates = uniqueCerts.length;

    setState(() {});
  }

  Future<void> saveName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("profileName", nameController.text);
    if (profileImage != null) {
      await prefs.setString("profileImagePath", profileImage!.path);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile updated!")),
    );
  }


  Future<void> pickProfileImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("profileImagePath", picked.path);
      setState(() {
        profileImage = File(picked.path);
      });
    }
  }

  void showPremiumPopup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PremiumScreen()),
    );
  }

  void logoutUser() async {
    try {
      await FirebaseAuth.instance.signOut();
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E11),
      body: RefreshIndicator(
        color: const Color(0xFF3B82F6),
        backgroundColor: const Color(0xFF11151C),
        onRefresh: () async {
          await loadProfileData();
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
            // 🌌 SPACEFOCO PREMIUM HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 70, 20, 40),
              decoration: const BoxDecoration(
                color: Color(0xFF0F131A),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Stack(
                children: [
                  // Removed glowing circle Positioned widget for a cleaner look.
                  Column(
                    children: [
                      GestureDetector(
                        onTap: showImageOptions,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 110,
                              width: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF020617),
                                border: Border.all(
                                  color: totalXP >= 25000
                                      ? const Color(0xFFFFD700) // Gold if 10k XP
                                      : const Color(0xFF3B82F6), // Default Electric Blue
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: profileImage != null
                                    ? Image.file(
                                        profileImage!,
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.cover,
                                      )
                                    : const Icon(Icons.person, size: 70, color: Colors.white),
                              ),
                            ),
                            if (PremiumService.isPremium)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star, color: Colors.black, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        "ELITE",
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        nameController.text.isNotEmpty ? nameController.text : "Player",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (userEmail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            userEmail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // ⭐ XP PROGRESS SECTION
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ValueListenableBuilder<Box>(
                                  valueListenable: _statsBox!.listenable(keys: ['xp']),
                                  builder: (context, box, _) {
                                    final xp = box.get('xp', defaultValue: 0);
                                    final String levelTitle = _getLevelTitle(xp);

                                    Color levelColor;
                                    if (xp >= 2000000) {
                                      levelColor = const Color(0xFFFFD700); // Gold
                                    } else if (xp >= 1000000) {
                                      levelColor = const Color(0xFF8B5CF6); // Purple
                                    } else if (xp >= 500000) {
                                      levelColor = const Color(0xFF3B82F6); // Blue
                                    } else if (xp >= 250000) {
                                      levelColor = const Color(0xFF10B981); // Green
                                    } else if (xp >= 50000) {
                                      levelColor = const Color(0xFFFFA500); // Orange
                                    } else {
                                      levelColor = Colors.white70;
                                    }

                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 600),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: levelColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: xp >= 1000000
                                            ? [
                                                BoxShadow(
                                                  color: levelColor.withOpacity(0.6),
                                                  blurRadius: 16,
                                                  spreadRadius: 1,
                                                ),
                                              ]
                                            : [],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (xp >= 2000000)
                                            const Padding(
                                              padding: EdgeInsets.only(right: 6),
                                              child: Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 16),
                                            ),
                                          Text(
                                            levelTitle,
                                            style: GoogleFonts.poppins(
                                              color: levelColor,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                ValueListenableBuilder<Box>(
                                  valueListenable: _statsBox!.listenable(keys: ['xp']),
                                  builder: (context, box, _) {
                                    final int xp = (box.get('xp', defaultValue: 0) as num).toInt();
                                    return Text(
                                      "$xp / $nextMilestone XP",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Stack(
                              alignment: Alignment.centerRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: ValueListenableBuilder<Box>(
                                    valueListenable: _statsBox!.listenable(keys: ['xp']),
                                    builder: (context, box, _) {
                                      final int xp = (box.get('xp', defaultValue: 0) as num).toInt();
                                      final double progress = xp >= nextMilestone ? 1.0 : xp / nextMilestone;
                                      return TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0,
                                          end: progress,
                                        ),
                                        duration: const Duration(milliseconds: 800),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, value, _) {
                                          return LinearProgressIndicator(
                                            minHeight: 14,
                                            value: value,
                                            backgroundColor: const Color(0xFF1E293B),
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              xp >= 10000
                                                  ? const Color(0xFFFFD700)
                                                  : const Color(0xFF1E90FF),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.card_giftcard,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ValueListenableBuilder<Box>(
                                valueListenable: _statsBox!.listenable(keys: ['xp']),
                                builder: (context, box, _) {
                                  final int xp = (box.get('xp', defaultValue: 0) as num).toInt();
                                  int remaining = nextMilestone - xp;
                                  if (remaining < 0) remaining = 0;

                                  return Text(
                                    remaining > 0
                                        ? "$remaining XP remaining to reach next milestone"
                                        : "🎉 Milestone Achieved!",
                                    style: GoogleFonts.poppins(
                                      color: const Color(0xFFFFA500),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),
                            ),

                            
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E90FF),
                    elevation: 8,
                    shadowColor: const Color(0xFF1E90FF).withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RewardsScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    "🎁 View My Rewards & Milestones",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🏆 LIFETIME ACHIEVEMENTS
            cardContainer(
              title: "Lifetime Achievements",
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ValueListenableBuilder<Box>(
                      valueListenable: _statsBox!.listenable(keys: ['maxSpeed']),
                      builder: (context, box, _) {
                        final double speed =
                            (box.get('maxSpeed', defaultValue: 0.0) as num)
                                .toDouble();
                        return _achievementItem(
                          "Max Speed",
                          "${speed.toStringAsFixed(1)} km/h",
                          const Color(0xFFFFD700),
                        );
                      },
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.white24,
                  ),
                  Expanded(
                    child: ValueListenableBuilder<Box>(
                      valueListenable:
                          _statsBox!.listenable(keys: ['totalVideos']),
                      builder: (context, box, _) {
                        final int videos =
                            (box.get('totalVideos', defaultValue: 0) as num)
                                .toInt();
                        return _achievementItem(
                          "Total Videos Uploaded",
                          "$videos",
                          const Color(0xFF1E90FF),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),


            // 👤 PERSONAL INFORMATION
            cardContainer(
              title: "Personal Information",
              child: Column(
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: inputStyle("Full Name"),
                  ),
                  const SizedBox(height: 14),
                  elevatedButton("Save Profile", saveName),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // PREMIUM
            cardContainer(
              title: "Explore Premium",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.workspace_premium, color: Color(0xFFFFD700)),
                title: const Text("See all premium benefits", style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF3B82F6)),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: const Color(0xFF0F131A),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (_) {
                      return SafeArea(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Center(
                                child: Text(
                                  "✨ Premium Benefits",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              _premiumItem("⚡ Bowling Speed Analysis",
                                "Accurate speed shown in km/h using physics-based AI."),
                              _premiumItem("🌪️ Swing Detection",
                                "Detects outswing, inswing, or straight delivery."),
                              _premiumItem("🌀 Spin Detection",
                                "Identifies off-spin, leg-spin, or no spin when confident."),
                              _premiumItem("🎯 Shot & Mistake Analysis",
                                "AI detects timing, shot selection, and technical mistakes."),
                              _premiumItem("🧠 AI Coach",
                                "Personalised coaching feedback for batting & bowling."),
                              _premiumItem("🧑‍⚖️ DRS Simulation",
                                "Training-only decision review with clear reasoning."),
                              _premiumItem("🎥 Video Compare",
                                "Compare multiple deliveries or shots side by side."),
                              _premiumItem("🔥 Advanced Visuals",
                                "Shot maps, swing paths, and trajectory insights."),
                              _premiumItem("🚀 Priority Processing",
                                "Faster AI analysis with premium servers."),
                              _premiumItem("🔓 All Premium Limits Unlocked",
                                "Higher chat, analysis, and comparison limits."),

                              const SizedBox(height: 28),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const PremiumScreen(entrySource: "profile"),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    "Upgrade to Premium",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // 📜 LEGAL & APP INFO
            cardContainer(
              title: "Legal & App Information",
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip, color: Color(0xFF3B82F6)),
                    title: const Text("Privacy Policy", style: TextStyle(color: Colors.white)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF3B82F6)),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF11151C),
                          title: const Text("Privacy Policy", style: TextStyle(color: Colors.white)),
                          content: const SingleChildScrollView(
                            child: Text(
                              "CrickNova AI collects limited user data such as email, profile name, "
                              "and uploaded videos strictly for analysis purposes.\n\n"
                              "We do NOT sell or share personal data with third parties.\n\n"
                              "All AI analysis results are stored securely in Firebase.\n\n"
                              "For support contact: urmila0@gmail.com",
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Close", style: TextStyle(color: Color(0xFF3B82F6))),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(color: Colors.white12),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description, color: Color(0xFF3B82F6)),
                    title: const Text("Terms & Conditions", style: TextStyle(color: Colors.white)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF3B82F6)),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF11151C),
                          title: const Text("Terms & Conditions", style: TextStyle(color: Colors.white)),
                          content: const SingleChildScrollView(
                            child: Text(
                              "CrickNova AI is a training and educational tool only.\n\n"
                              "It does NOT replace official match umpires, coaches, or governing bodies.\n\n"
                              "Speed, swing, spin, and DRS insights are AI-generated estimates.\n\n"
                              "Users are responsible for ensuring uploaded content complies with copyright laws.\n\n"
                              "By using this app, you agree to these terms.",
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Close", style: TextStyle(color: Color(0xFF3B82F6))),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(color: Colors.white12),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline, color: Color(0xFF3B82F6)),
                    title: const Text("About CrickNova AI", style: TextStyle(color: Colors.white)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF3B82F6)),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF11151C),
                          title: const Text("About CrickNova AI", style: TextStyle(color: Colors.white)),
                          content: const SingleChildScrollView(
                            child: Text(
                              "App Name: CrickNova AI\n"
                              "Version: 1.0.0\n\n"
                              "CrickNova AI is an advanced cricket analysis platform "
                              "that provides AI-powered speed detection, swing & spin analysis, "
                              "DRS simulation, and coaching insights.\n\n"
                              "Built using Flutter, Firebase, and AI-based computer vision.\n\n"
                              "Developer: cricknova\n"
                              "Contact: urmila0@gmail.com",
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Close", style: TextStyle(color: Color(0xFF3B82F6))),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // LOG OUT
            cardContainer(
              title: "Account",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                title: const Text("Log Out", style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF3B82F6)),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF11151C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Text(
                        "Log Out",
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        "Are you sure you want to log out?",
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Go Back",
                            style: TextStyle(color: Color(0xFF3B82F6)),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(context);
                            try {
                              await FirebaseAuth.instance.signOut();
                              await _googleSignIn.signOut();
                              await _googleSignIn.disconnect();
                            } catch (_) {}

                            if (!mounted) return;

                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (route) => false,
                            );
                          },
                          child: const Text(
                            "Yes, Log Out",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),


            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                "⚠️ AI Disclaimer:\nAll AI-generated insights, speed estimates, DRS decisions, and coaching feedback are provided for training and educational purposes only. Results may vary based on video quality, camera angle, lighting, and frame rate. CrickNova AI does not claim official match accuracy or replacement of professional umpires or coaches.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.white38,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 📌 Helper Widgets
  Widget cardContainer({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF11151C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (title == "Explore Premium")
                  const Icon(Icons.workspace_premium, size: 18, color: Color(0xFFFFD700)),
                if (title == "Legal & App Information")
                  const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF3B82F6)),
                if (title == "Account")
                  const Icon(Icons.manage_accounts_outlined, size: 18, color: Color(0xFFEF4444)),
                if (title == "Explore Premium" ||
                    title == "Legal & App Information" ||
                    title == "Account")
                  const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  InputDecoration inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: const Color(0xFF0F131A),
      labelStyle: const TextStyle(color: Colors.white70),
      floatingLabelStyle: const TextStyle(color: Colors.white),
      hintStyle: const TextStyle(color: Colors.white54),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget elevatedButton(String text, Function onTap, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF1E90FF),
          elevation: 6,
          shadowColor: const Color(0xFF1E90FF).withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        onPressed: () => onTap(),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget socialButton(IconData icon, String text, Function onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 28, color: const Color(0xFF3B82F6)),
      title: Text(text, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF3B82F6)),
      onTap: () => onTap(),
    );
  }
  void showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF3B82F6)),
                title: const Text("Upload from Gallery"),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? picked =
                      await _picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString("profileImagePath", picked.path);
                    setState(() {
                      profileImage = File(picked.path);
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3B82F6)),
                title: const Text("Open Camera"),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? picked =
                      await _picker.pickImage(source: ImageSource.camera);
                  if (picked != null) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString("profileImagePath", picked.path);
                    setState(() {
                      profileImage = File(picked.path);
                    });
                  }
                },
              ),
              if (profileImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Color(0xFFEF4444)),
                  title: const Text("Remove Profile Photo"),
                  onTap: () async {
                    Navigator.pop(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove("profileImagePath");
                    setState(() {
                      profileImage = null;
                    });
                  },
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
  Widget _achievementItem(String title, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _premiumItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
  String _getLevelTitle(int xp) {
    if (xp >= 2000000) return "Level 12: Immortal Master";
    if (xp >= 1500000) return "Level 11: World Dominator";
    if (xp >= 1000000) return "Level 10: Grand Champion";
    if (xp >= 750000) return "Level 9: Supreme Legend";
    if (xp >= 500000) return "Level 8: Master Blaster";
    if (xp >= 250000) return "Level 7: Elite Warrior";
    if (xp >= 50000) return "Level 6: Legendary";
    if (xp >= 25000) return "Level 5: Elite Player";
    if (xp >= 15000) return "Level 4: Rising Star";
    if (xp >= 8000) return "Level 3: Competitor";
    if (xp >= 3000) return "Level 2: Developing";
    return "Level 1: Beginner";
  }
}


class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  int totalXP = 0;

  bool jerseyClaimed = false;
  DateTime? claimDate;
  int xpAtClaim = 0;

  @override
  void initState() {
    super.initState();
    _loadXP();
  }

  Future<void> _loadXP() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    if (uid == "guest") return;

    final box = await Hive.openBox("local_stats_$uid");
    final xp = box.get("xp", defaultValue: 0);
    final claimMillis = box.get("claimDateMillis");
    final claimed50 = box.get("claimed_50000", defaultValue: false);
    final claimed5L = box.get("claimed_500000", defaultValue: false);
    final claimed10L = box.get("claimed_1000000", defaultValue: false);
    final claimed20L = box.get("claimed_2000000", defaultValue: false);

    DateTime? savedClaimDate;
    if (claimMillis != null) {
      savedClaimDate = DateTime.fromMillisecondsSinceEpoch(claimMillis);
    }

    setState(() {
      totalXP = xp;
      xpAtClaim = box.get("xpAtClaim", defaultValue: 0);
      claimDate = savedClaimDate;
      jerseyClaimed = claimed50;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isEligible(int threshold) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
      if (uid == "guest") return false;
      final box = Hive.box("local_stats_$uid");

      final alreadyClaimed = box.get("claimed_$threshold", defaultValue: false);
      if (alreadyClaimed) return false;

      return totalXP >= threshold;
    }

    int extraXPFor(int threshold) {
      return totalXP > threshold ? (totalXP - threshold) : 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F131A),
        title: const Text(
          "Rewards & Milestones",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _rewardCard(
              title: "Official CrickNova Jersey",
              description: "Unlock at 50,000 XP milestone. Includes Official Jersey + Special Gift.",
              threshold: 50000,
              eligible: isEligible(50000),
              extraXP: extraXPFor(50000),
              gradientColors: const [Color(0xFFFFD700), Color(0xFFFFA000)],
              icon: Icons.workspace_premium,
            ),
            const SizedBox(height: 16),
            _rewardCard(
              title: "Batting Gloves + Special Gift",
              description: "Unlock at 5 Lakh XP milestone.",
              threshold: 500000,
              eligible: isEligible(500000),
              extraXP: extraXPFor(500000),
              gradientColors: const [Color(0xFF60A5FA), Color(0xFF2563EB)],
              icon: Icons.sports_cricket,
            ),
            const SizedBox(height: 16),
            _rewardCard(
              title: "Full Cricket Kit + Special Gift",
              description: "Unlock at 10 Lakh XP milestone.",
              threshold: 1000000,
              eligible: isEligible(1000000),
              extraXP: extraXPFor(1000000),
              gradientColors: const [Color(0xFF34D399), Color(0xFF059669)],
              icon: Icons.inventory,
            ),
            const SizedBox(height: 16),
            _rewardCard(
              title: "English Willow Bat + Special Gift",
              description: "Unlock at 20 Lakh XP milestone.",
              threshold: 2000000,
              eligible: isEligible(2000000),
              extraXP: extraXPFor(2000000),
              gradientColors: const [Color(0xFFF472B6), Color(0xFFDB2777)],
              icon: Icons.emoji_events,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardCard({
    required String title,
    required String description,
    required int threshold,
    required bool eligible,
    required int extraXP,
    required List<Color> gradientColors,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: eligible
              ? gradientColors
              : [const Color(0xFF1E293B), const Color(0xFF11151C)],
        ),
        boxShadow: [
          if (eligible)
            BoxShadow(
              color: gradientColors.first.withOpacity(0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: eligible ? Colors.black : Colors.white54,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: eligible ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            eligible
                ? (extraXP > 0
                    ? "Unlocked! You have $extraXP XP above $threshold."
                    : "Congratulations! You unlocked this reward.")
                : description,
            style: TextStyle(
              color: eligible ? Colors.black87 : Colors.white54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          // Delivery status indicator
          if (jerseyClaimed && claimDate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Builder(
                builder: (_) {
                  final daysPassed =
                      DateTime.now().difference(claimDate!).inDays;
                  final daysRemaining = 30 - daysPassed;
                  final safeRemaining =
                      daysRemaining < 0 ? 0 : daysRemaining;

                  return Text(
                    safeRemaining > 0
                        ? "📦 Order received. Delivering in $safeRemaining days"
                        : "🎉 Delivered Successfully",
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  );
                },
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: eligible
                  ? () {
                      showClaimBottomSheet(context, title, threshold);
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: eligible
                      ? Colors.black
                      : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  eligible
                      ? "Claim Now"
                      : "Locked",
                  style: TextStyle(
                    color: eligible ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showClaimBottomSheet(BuildContext context, String rewardTitle, int threshold) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final pincodeController = TextEditingController();
    final houseController = TextEditingController();
    final roadController = TextEditingController();
    final landmarkController = TextEditingController();
    final cityStateController = TextEditingController();
    String selectedCountryCode = "+91";
    String selectedSize = "M";
    String selectedGlovesSize = "M";
    String selectedPadsSize = "Adult";
    String selectedHelmetSize = "M";
    String selectedBatCompany = "SS";
    String selectedBatWeight = "1180g";
    String selectedBatSize = "SH";
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF0F131A),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(
                          child: Column(
                            children: [
                              Icon(Icons.workspace_premium,
                                  color: Color(0xFFFFD700), size: 40),
                              SizedBox(height: 10),
                              Text(
                                "Claim Your Official Jersey",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),

                        _premiumField(
                          controller: nameController,
                          label: "Full Name",
                          icon: Icons.person,
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  dropdownColor: const Color(0xFF1E293B),
                                  value: selectedCountryCode,
                                  style: const TextStyle(color: Colors.white),
                                  items: const [
                                    "+1","+7","+20","+27","+30","+31","+32","+33","+34","+36","+39","+40","+41","+43","+44","+45","+46","+47","+48","+49",
                                    "+51","+52","+53","+54","+55","+56","+57","+58","+60","+61","+62","+63","+64","+65","+66","+81","+82","+84","+86","+90",
                                    "+91","+93","+94","+95","+98","+211","+212","+213","+216","+218","+220","+221","+222","+223","+224","+225","+226","+227","+228","+229",
                                    "+230","+231","+232","+233","+234","+235","+236","+237","+238","+239","+240","+241","+242","+243","+244","+245","+246","+248","+249","+250",
                                    "+251","+252","+253","+254","+255","+256","+257","+258","+260","+261","+262","+263","+264","+265","+266","+267","+268","+269","+290","+291",
                                    "+297","+298","+299","+350","+351","+352","+353","+354","+355","+356","+357","+358","+359","+370","+371","+372","+373","+374","+375","+376",
                                    "+377","+378","+380","+381","+382","+383","+385","+386","+387","+389","+420","+421","+423","+500","+501","+502","+503","+504","+505","+506",
                                    "+507","+508","+509","+590","+591","+592","+593","+594","+595","+596","+597","+598","+599","+670","+672","+673","+674","+675","+676","+677",
                                    "+678","+679","+680","+681","+682","+683","+685","+686","+687","+688","+689","+690","+691","+692","+850","+852","+853","+855","+856","+880",
                                    "+886","+960","+961","+962","+963","+964","+965","+966","+967","+968","+970","+971","+972","+973","+974","+975","+976","+977","+992","+993",
                                    "+994","+995","+996","+998"
                                  ].map((code) {
                                    return DropdownMenuItem(
                                      value: code,
                                      child: Text(code),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      selectedCountryCode = value!;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.phone, color: Color(0xFF3B82F6)),
                                  labelText: "Mobile Number",
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Contact number required";
                                  }
                                  if (value.trim().length < 6) {
                                    return "Enter valid number";
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: pincodeController,
                          label: "Pincode",
                          icon: Icons.pin,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: houseController,
                          label: "Flat, House no., Building",
                          icon: Icons.home,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: roadController,
                          label: "Area, Colony, Street, Sector",
                          icon: Icons.map,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: landmarkController,
                          label: "Landmark",
                          icon: Icons.place,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: cityStateController,
                          label: "City / State",
                          icon: Icons.location_city,
                        ),

                        // Jersey Size ONLY for 50K
                        if (threshold == 50000) ...[
                          const SizedBox(height: 20),
                          const Text(
                            "Select Jersey Size",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children: ["S", "M", "L", "XL", "XXL", "2XL", "3XL", "4XL"].map((size) {
                              final bool isSelected = selectedSize == size;
                              return ChoiceChip(
                                label: Text(size),
                                selected: isSelected,
                                selectedColor: const Color(0xFF1E90FF),
                                backgroundColor: const Color(0xFF1E293B),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    selectedSize = size;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],

                        // Gloves Size for 5 Lakh
                        if (threshold == 500000) ...[
                          const SizedBox(height: 20),
                          const Text(
                            "Select Gloves Size",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children: ["S", "M", "L", "XL", "XXL"].map((size) {
                              final bool isSelected = selectedGlovesSize == size;
                              return ChoiceChip(
                                label: Text(size),
                                selected: isSelected,
                                selectedColor: const Color(0xFF1E90FF),
                                backgroundColor: const Color(0xFF1E293B),
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    selectedGlovesSize = size;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],

                        // Kit Equipment Sizes for 10 Lakh
                        if (threshold == 1000000) ...[
                          const SizedBox(height: 20),
                          const Text(
                            "Cricket Kit Sizes",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _kitDropdown(
                            label: "Batting Pads Size",
                            value: selectedPadsSize,
                            options: ["Youth", "Adult", "Large Adult"],
                            onChanged: (val) => setState(() => selectedPadsSize = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Batting Gloves Size",
                            value: selectedGlovesSize,
                            options: ["S", "M", "L", "XL", "XXL"],
                            onChanged: (val) => setState(() => selectedGlovesSize = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Helmet Size",
                            value: selectedHelmetSize,
                            options: ["S", "M", "L"],
                            onChanged: (val) => setState(() => selectedHelmetSize = val),
                          ),
                        ],

                        // Bat Options for 20 Lakh
                        if (threshold == 2000000) ...[
                          const SizedBox(height: 20),
                          const Text(
                            "Bat Preferences",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _kitDropdown(
                            label: "Bat Company",
                            value: selectedBatCompany,
                            options: ["SS", "SG", "MRF", "GM", "Kookaburra"],
                            onChanged: (val) => setState(() => selectedBatCompany = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Bat Weight",
                            value: selectedBatWeight,
                            options: ["1160g", "1180g", "1200g", "1220g"],
                            onChanged: (val) => setState(() => selectedBatWeight = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Bat Size",
                            value: selectedBatSize,
                            options: ["SH", "LH"],
                            onChanged: (val) => setState(() => selectedBatSize = val),
                          ),
                        ],

                        const SizedBox(height: 30),

                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E90FF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 8,
                            ),
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                final orderSummary = '''
Reward: $rewardTitle
${threshold == 50000 ? "Jersey Size: $selectedSize" : ""}
${threshold == 500000 ? "Gloves Size: $selectedGlovesSize" : ""}
${threshold == 1000000 ? "Pads: $selectedPadsSize\nGloves: $selectedGlovesSize\nHelmet: $selectedHelmetSize" : ""}
${threshold == 2000000 ? "Bat Company: $selectedBatCompany\nBat Weight: $selectedBatWeight\nBat Size: $selectedBatSize" : ""}

Full Name: ${nameController.text}
Phone: $selectedCountryCode ${phoneController.text}

Address:
Pincode: ${pincodeController.text}
House/Building: ${houseController.text}
Road/Area: ${roadController.text}
Landmark: ${landmarkController.text}
City/State: ${cityStateController.text}

Total XP: $totalXP
''';

                                final subject = "CrickNova Jersey Order";

                                final Uri emailUri = Uri.parse(
                                  'mailto:urmiladukare0@gmail.com'
                                  '?subject=${Uri.encodeComponent(subject)}'
                                  '&body=${Uri.encodeComponent(orderSummary)}',
                                );

                                if (await canLaunchUrl(emailUri)) {
                                  await launchUrl(emailUri);
                                }

                                if (!mounted) return;

                                final uid =
                                    FirebaseAuth.instance.currentUser?.uid ?? "guest";
                                final box = await Hive.openBox("local_stats_$uid");

                                final currentXP = box.get("xp", defaultValue: 0) as int;
                                final now = DateTime.now();

                                setState(() {
                                  jerseyClaimed = true;
                                  claimDate = now;
                                  xpAtClaim = currentXP;
                                });

                                // Do NOT reset XP. Keep cumulative progress.
                                await box.put("xpAtClaim", currentXP);
                                await box.put("claimDateMillis", now.millisecondsSinceEpoch);
                                await box.put("claimed_$threshold", true);
                                await box.flush();

                                // Keep totalXP unchanged (milestones are cumulative)
                                setState(() {
                                  totalXP = currentXP;
                                });

                                Navigator.pop(context);

                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: const Color(0xFF11151C),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    title: const Text(
                                      "🎉 Milestone Unlocked!",
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.celebration,
                                            color: Color(0xFFFFD700), size: 60),
                                        SizedBox(height: 12),
                                        Text(
                                          "Reward claimed successfully!\nKeep climbing to the next milestone 🚀",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            },
                            child: const Text(
                              "Submit",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _premiumField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF3B82F6)),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return "This field is required";
        }
        return null;
      },
    );
  }
}
  Widget _kitDropdown({
    required String label,
    required String value,
    required List<String> options,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white),
              isExpanded: true,
              items: options
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
        ),
      ],
    );
  }