import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
    // 🔥 Load XP & stats from Firestore only
    if (uid != "guest") {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        totalXP = (data?["xp"] ?? 0) as int;
        totalVideos = (data?["totalVideos"] ?? 0) as int;

        // 🔥 Compute Max Speed from bowling_sessions collection
        double computedMax = 0.0;

        final sessionsSnapshot = await FirebaseFirestore.instance
            .collection("users")
            .doc(uid)
            .collection("bowling_sessions")
            .get();

        for (final session in sessionsSnapshot.docs) {
          final speeds = session.data()["speeds"];
          if (speeds is List) {
            for (final s in speeds) {
              if (s is num && s.toDouble() > computedMax) {
                computedMax = s.toDouble();
              }
            }
          }
        }

        maxSpeed = computedMax;
      }
    }

    // Calculate remaining XP for 50,000 milestone
    remainingXP = 50000 - totalXP;
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
                                Text(
                                  _getLevelTitle(totalXP),
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  "${totalXP.toString()} / 50000 XP",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Stack(
                              alignment: Alignment.centerRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: LinearProgressIndicator(
                                    minHeight: 14,
                                    value: totalXP >= 50000 ? 1 : totalXP / 50000,
                                    backgroundColor: const Color(0xFF1E293B),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      totalXP >= 10000
                                          ? const Color(0xFFFFD700)
                                          : const Color(0xFF1E90FF),
                                    ),
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
                              child: Text(
                                remainingXP > 0
                                    ? "${remainingXP} XP remaining to reach 50K milestone"
                                    : "🎉 50K Milestone Achieved!",
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFFFA500),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
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
                    child: _achievementItem(
                      "Max Speed",
                      "${maxSpeed.toStringAsFixed(1)} km/h",
                      const Color(0xFFFFD700), // Gold
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.white24,
                  ),
                  Expanded(
                    child: _achievementItem(
                      "Total Videos Uploaded",
                      "$totalVideos",
                      const Color(0xFF1E90FF), // Electric Blue
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
    return Expanded(
      child: Column(
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
      ),
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

  @override
  void initState() {
    super.initState();
    _loadXP();
  }

  Future<void> _loadXP() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";

    if (uid == "guest") return;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();

    if (doc.exists) {
      setState(() {
        totalXP = doc.data()?["xp"] ?? 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool eligibleForJersey = totalXP >= 50000;
    final bool eligibleForSpecial = totalXP >= 50000;

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
              description: "Unlock at 50,000 XP milestone.",
              eligible: eligibleForJersey,
              gradientColors: const [Color(0xFFFFD700), Color(0xFFFFA000)],
              icon: Icons.workspace_premium,
            ),
            const SizedBox(height: 20),
            _rewardCard(
              title: "🎁 Special Gift from CrickNova",
              description: "Unlocked at 50,000 XP milestone.",
              eligible: eligibleForSpecial,
              gradientColors: const [Color(0xFF1E90FF), Color(0xFF3B82F6)],
              icon: Icons.card_giftcard,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardCard({
    required String title,
    required String description,
    required bool eligible,
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
                ? "Congratulations! You unlocked this reward."
                : description,
            style: TextStyle(
              color: eligible ? Colors.black87 : Colors.white54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: eligible
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Reward claimed successfully! 🎉"),
                        ),
                      );
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
                  eligible ? "Claim Now" : "Locked",
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
}