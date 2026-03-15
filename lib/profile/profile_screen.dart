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
import 'package:in_app_review/in_app_review.dart';
import '../premium/premium_screen.dart';
import '../auth/login_screen.dart';
import '../services/premium_service.dart';
import 'legal_info_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController nameController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String? userEmail;

  File? profileImage;
  final ImagePicker _picker = ImagePicker();
  bool _isEditingProfile = false;
  bool _nameDirty = false;
  String _savedName = "";

  double maxSpeed = 0;
  int totalVideos = 0;
  int totalCertificates = 0;
  int totalXP = 0;
  int chatXP = 0;
  int remainingXP = 0;
  Box? _statsBox;
  int nextMilestone = 50000;
  late final AnimationController _supportPulseController;
  late final Animation<double> _supportPulse;
  bool _showRatingDetails = false;
  int _selectedRating = 0;
  late final TextEditingController _reviewController;

  Future<Box> _getStatsBox(String uid) async {
    final boxName = "local_stats_$uid";
    if (_statsBox != null && _statsBox!.name == boxName) {
      return _statsBox!;
    }
    _statsBox = await Hive.openBox(boxName);
    return _statsBox!;
  }

  @override
  void initState() {
    super.initState();
    _supportPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _supportPulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _supportPulseController, curve: Curves.easeInOut),
    );
    _reviewController = TextEditingController(
      text:
          "CrickNova AI is very good and accurate. It helped me improve my bowling speed and swing.",
    );
    loadProfileData();
  }

  @override
  void dispose() {
    _supportPulseController.dispose();
    nameController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    userEmail = user?.email;

    final uid = user?.uid ?? "guest";

    // 🔥 Load XP & stats from Hive (local storage)
    final box = await _getStatsBox(uid);

    // ✅ Load profile photo from Hive (per-user)
    profileImage = null;
    final hiveImagePath = box.get("profileImagePath") as String?;
    if (hiveImagePath != null && hiveImagePath.isNotEmpty) {
      profileImage = File(hiveImagePath);
    } else {
      // 🔁 Migrate legacy SharedPreferences value (global) into Hive
      final legacyPath = prefs.getString("profileImagePath");
      if (legacyPath != null && legacyPath.isNotEmpty) {
        await box.put("profileImagePath", legacyPath);
        await prefs.remove("profileImagePath");
        profileImage = File(legacyPath);
      }
    }

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

    // 👤 Load profile name from Hive (per-user)
    final hiveName = box.get("profileName") as String?;
    if (hiveName != null && hiveName.trim().isNotEmpty) {
      _savedName = hiveName.trim();
    } else {
      final legacyName = prefs.getString("profileName");
      if (legacyName != null && legacyName.trim().isNotEmpty) {
        _savedName = legacyName.trim();
        await box.put("profileName", _savedName);
        await prefs.remove("profileName");
      } else {
        _savedName = "";
      }
    }
    nameController.text = _savedName;
    _isEditingProfile = _savedName.isEmpty;
    _nameDirty = false;

    // 💬 Load AI Chat XP count (still from SharedPreferences)
    chatXP = prefs.getInt("chatXP_$uid") ?? 0;

    final savedCerts = prefs.getStringList("savedCertificates") ?? [];

    // Remove duplicate certificate paths
    final uniqueCerts = savedCerts.toSet().toList();

    totalCertificates = uniqueCerts.length;

    setState(() {});
  }

  Future<void> saveName() async {
    final trimmed = nameController.text.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter your name.")),
        );
      }
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final box = await _getStatsBox(uid);
    await box.put("profileName", trimmed);
    _savedName = trimmed;
    _isEditingProfile = false;
    _nameDirty = false;

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Profile updated!")));
    setState(() {});
  }

  Future<void> pickProfileImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
      final box = await _getStatsBox(uid);
      await box.put("profileImagePath", picked.path);
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

  Future<void> _openRating() async {
    try {
      final review = InAppReview.instance;
      await review.openStoreListing();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Thanks for supporting CrickNova AI!")),
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
                                        ? const Color(
                                            0xFFFFD700,
                                          ) // Gold if 10k XP
                                        : const Color(
                                            0xFF3B82F6,
                                          ), // Default Electric Blue
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
                                      : const Icon(
                                          Icons.person,
                                          size: 70,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                              if (PremiumService.isPremium)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFD700),
                                          Color(0xFFFFA000),
                                        ],
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
                                        Icon(
                                          Icons.star,
                                          color: Colors.black,
                                          size: 14,
                                        ),
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
                          nameController.text.isNotEmpty
                              ? nameController.text
                              : "Player",
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  ValueListenableBuilder<Box>(
                                    valueListenable: _statsBox!.listenable(
                                      keys: ['xp'],
                                    ),
                                    builder: (context, box, _) {
                                      final xp = box.get('xp', defaultValue: 0);
                                      final String levelTitle = _getLevelTitle(
                                        xp,
                                      );

                                      Color levelColor;
                                      if (xp >= 2000000) {
                                        levelColor = const Color(
                                          0xFFFFD700,
                                        ); // Gold
                                      } else if (xp >= 1000000) {
                                        levelColor = const Color(
                                          0xFF8B5CF6,
                                        ); // Purple
                                      } else if (xp >= 500000) {
                                        levelColor = const Color(
                                          0xFF3B82F6,
                                        ); // Blue
                                      } else if (xp >= 250000) {
                                        levelColor = const Color(
                                          0xFF10B981,
                                        ); // Green
                                      } else if (xp >= 50000) {
                                        levelColor = const Color(
                                          0xFFFFA500,
                                        ); // Orange
                                      } else {
                                        levelColor = Colors.white70;
                                      }

                                      return AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 600,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: levelColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: xp >= 1000000
                                              ? [
                                                  BoxShadow(
                                                    color: levelColor
                                                        .withOpacity(0.6),
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
                                                padding: EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: Icon(
                                                  Icons.emoji_events,
                                                  color: Color(0xFFFFD700),
                                                  size: 16,
                                                ),
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
                                    valueListenable: _statsBox!.listenable(
                                      keys: ['xp'],
                                    ),
                                    builder: (context, box, _) {
                                      final int xp =
                                          (box.get('xp', defaultValue: 0)
                                                  as num)
                                              .toInt();
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
                                      valueListenable: _statsBox!.listenable(
                                        keys: ['xp'],
                                      ),
                                      builder: (context, box, _) {
                                        final int xp =
                                            (box.get('xp', defaultValue: 0)
                                                    as num)
                                                .toInt();
                                        final double progress =
                                            xp >= nextMilestone
                                            ? 1.0
                                            : xp / nextMilestone;
                                        return TweenAnimationBuilder<double>(
                                          tween: Tween<double>(
                                            begin: 0,
                                            end: progress,
                                          ),
                                          duration: const Duration(
                                            milliseconds: 800,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          builder: (context, value, _) {
                                            return LinearProgressIndicator(
                                              minHeight: 14,
                                              value: value,
                                              backgroundColor: const Color(
                                                0xFF1E293B,
                                              ),
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    xp >= 10000
                                                        ? const Color(
                                                            0xFFFFD700,
                                                          )
                                                        : const Color(
                                                            0xFF1E90FF,
                                                          ),
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
                                  valueListenable: _statsBox!.listenable(
                                    keys: ['xp'],
                                  ),
                                  builder: (context, box, _) {
                                    final int xp =
                                        (box.get('xp', defaultValue: 0) as num)
                                            .toInt();
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
                        valueListenable: _statsBox!.listenable(
                          keys: ['maxSpeed'],
                        ),
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
                        valueListenable: _statsBox!.listenable(
                          keys: ['totalVideos'],
                        ),
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

              // 👤 PERSONAL INFORMATION (Premium Style)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B1220), Color(0xFF131B2B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFF2A3A54)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withOpacity(0.08),
                        blurRadius: 18,
                        spreadRadius: 1,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF38BDF8,
                                  ).withOpacity(0.35),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Personal Information",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Secure & private account details",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: PremiumService.isPremium
                                  ? const Color(0xFFFFD700).withOpacity(0.16)
                                  : Colors.white10,
                              border: Border.all(
                                color: PremiumService.isPremium
                                    ? const Color(0xFFFFD700)
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              PremiumService.isPremium ? "PREMIUM" : "FREE",
                              style: GoogleFonts.poppins(
                                color: PremiumService.isPremium
                                    ? const Color(0xFFFFD700)
                                    : Colors.white70,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: Colors.white10,
                      ),
                      const SizedBox(height: 16),
                      if (_isEditingProfile)
                        TextField(
                          controller: nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: inputStyle("Full Name").copyWith(
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              color: Colors.white54,
                            ),
                          ),
                          onChanged: (val) {
                            final trimmed = val.trim();
                            final dirty =
                                trimmed.isNotEmpty && trimmed != _savedName;
                            if (dirty != _nameDirty) {
                              setState(() {
                                _nameDirty = dirty;
                              });
                            }
                          },
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F131A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person_outline,
                                color: Colors.white54,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _savedName.isNotEmpty ? _savedName : "Player",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F131A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.mail_outline,
                              color: Colors.white54,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                userEmail ?? "Email not linked",
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isEditingProfile && _nameDirty)
                        InkWell(
                          onTap: saveName,
                          borderRadius: BorderRadius.circular(16),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1D4ED8), Color(0xFF38BDF8)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF38BDF8,
                                  ).withOpacity(0.35),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                "Save Profile",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (!_isEditingProfile)
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isEditingProfile = true;
                              _nameDirty = false;
                              nameController.text = _savedName;
                            });
                          },
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.white70,
                            size: 18,
                          ),
                          label: Text(
                            "Edit Profile",
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // PREMIUM
              cardContainer(
                title: "Explore Premium",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.workspace_premium,
                    color: Color(0xFFFFD700),
                  ),
                  title: const Text(
                    "See all premium benefits",
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 18,
                    color: Color(0xFF3B82F6),
                  ),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) {
                        return SafeArea(
                          child: _PremiumBrochureSheet(
                            onUpgrade: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PremiumScreen(
                                    entrySource: "profile",
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // SUPPORT & RATING
              cardContainer(
                title: "Support & Rating",
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ScaleTransition(
                        scale: _supportPulse,
                        child: _supportStarIcon(),
                      ),
                      title: const Text(
                        "Support CrickNova AI (Rate Us)",
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text(
                            "If CrickNova AI is improving your game, give us 5 stars on the Play Store.",
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Tap the stars to rate now.",
                            style: GoogleFonts.poppins(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 10),
                                _ratingStarsRow(
                                  rating: _selectedRating,
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedRating = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedRating == 0
                                      ? "Select your rating (1 to 5 stars)."
                                      : "You selected $_selectedRating/5. Tap “Open Play Store” to submit.",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "Write a quick review (optional):",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _reviewController,
                                  minLines: 2,
                                  maxLines: 3,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF0F131A),
                                    hintText:
                                        "CrickNova AI is very good... (edit if you want)",
                                    hintStyle: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFD86B),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _openRating,
                                    child: const Text("Open Play Store"),
                                  ),
                                ),
                              ],
                            ),
                            crossFadeState: _showRatingDetails
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _supportBadge(),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Color(0xFF3B82F6),
                          ),
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          _showRatingDetails = !_showRatingDetails;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Your single review can help CrickNova AI reach players globally. Thank you!",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
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
                      leading: const Icon(
                        Icons.privacy_tip,
                        color: Color(0xFF3B82F6),
                      ),
                      title: const Text(
                        "Privacy Policy",
                        style: TextStyle(color: Colors.white),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                        color: Color(0xFF3B82F6),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalInfoScreen(
                              document: LegalDocument.privacy(),
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(color: Colors.white12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.description,
                        color: Color(0xFF3B82F6),
                      ),
                      title: const Text(
                        "Terms & Conditions",
                        style: TextStyle(color: Colors.white),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                        color: Color(0xFF3B82F6),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalInfoScreen(
                              document: LegalDocument.terms(),
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(color: Colors.white12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.info_outline,
                        color: Color(0xFF3B82F6),
                      ),
                      title: const Text(
                        "About CrickNova AI",
                        style: TextStyle(color: Colors.white),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                        color: Color(0xFF3B82F6),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalInfoScreen(
                              document: LegalDocument.about(),
                            ),
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
                  title: const Text(
                    "Log Out",
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 18,
                    color: Color(0xFF3B82F6),
                  ),
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
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
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
                  const Icon(
                    Icons.workspace_premium,
                    size: 18,
                    color: Color(0xFFFFD700),
                  ),
                if (title == "Legal & App Information")
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: Color(0xFF3B82F6),
                  ),
                if (title == "Account")
                  const Icon(
                    Icons.manage_accounts_outlined,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
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
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _supportStarIcon() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0F131A),
        border: Border.all(
          color: const Color(0xFFFFD86B).withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD86B).withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            colors: [Color(0xFFFFD86B), Color(0xFFF59E0B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds);
        },
        child: const Icon(Icons.stars_rounded, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _supportBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        "Help us grow",
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _ratingStarsRow({
    required int rating,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isFilled = starValue <= rating;
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(starValue),
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              isFilled ? Icons.star_rounded : Icons.star_border_rounded,
              color: const Color(0xFFFFD86B),
              size: 20,
            ),
          ),
        );
      }),
    );
  }

  Widget socialButton(IconData icon, String text, Function onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 28, color: const Color(0xFF3B82F6)),
      title: Text(text, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: Color(0xFF3B82F6),
      ),
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
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF3B82F6),
                ),
                title: const Text("Upload from Gallery"),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? picked = await _picker.pickImage(
                    source: ImageSource.gallery,
                  );
                  if (picked != null) {
                    final uid =
                        FirebaseAuth.instance.currentUser?.uid ?? "guest";
                    final box = await _getStatsBox(uid);
                    await box.put("profileImagePath", picked.path);
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
                  final XFile? picked = await _picker.pickImage(
                    source: ImageSource.camera,
                  );
                  if (picked != null) {
                    final uid =
                        FirebaseAuth.instance.currentUser?.uid ?? "guest";
                    final box = await _getStatsBox(uid);
                    await box.put("profileImagePath", picked.path);
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
                    final uid =
                        FirebaseAuth.instance.currentUser?.uid ?? "guest";
                    final box = await _getStatsBox(uid);
                    await box.delete("profileImagePath");
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
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54),
        ),
      ],
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

class _PremiumFeature {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;

  const _PremiumFeature({
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
  });
}

class _PremiumBrochureSheet extends StatefulWidget {
  final VoidCallback onUpgrade;

  const _PremiumBrochureSheet({required this.onUpgrade});

  @override
  State<_PremiumBrochureSheet> createState() => _PremiumBrochureSheetState();
}

class _PremiumBrochureSheetState extends State<_PremiumBrochureSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  final List<_PremiumFeature> _features = const [
    _PremiumFeature(
      icon: Icons.flash_on_rounded,
      title: "Power Speed",
      description: "Physics-based KMPH tracking.",
    ),
    _PremiumFeature(
      icon: Icons.blur_circular_rounded,
      title: "Swing & Spin Mastery",
      description: "Inswing, Outswing, and spin revolutions.",
    ),
    _PremiumFeature(
      icon: Icons.auto_awesome_rounded,
      title: "AI Coach",
      description: "Your personal cricket consultant.",
      badge: "ELITE",
    ),
    _PremiumFeature(
      icon: Icons.gavel_rounded,
      title: "DRS Call",
      description: "Elite-level ball trajectory simulation.",
      badge: "PRO",
    ),
    _PremiumFeature(
      icon: Icons.video_library_rounded,
      title: "Pro Video Compare",
      description: "Side-by-side comparison overlays.",
    ),
    _PremiumFeature(
      icon: Icons.insights_rounded,
      title: "Elite Growth Dashboard",
      description: "Graphs, power levels, and trends.",
    ),
    _PremiumFeature(
      icon: Icons.psychology_alt_rounded,
      title: "AI Mistake Detection",
      description: "Instant batting & bowling flaw checks.",
    ),
    _PremiumFeature(
      icon: Icons.support_agent_rounded,
      title: "Direct Coach Access",
      description: "One-click WhatsApp support.",
    ),
    _PremiumFeature(
      icon: Icons.picture_as_pdf_rounded,
      title: "PDF Performance Reports",
      description: "Weekly progress reports.",
    ),
    _PremiumFeature(
      icon: Icons.rocket_launch_rounded,
      title: "Priority Processing",
      description: "2x faster Elite servers.",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 720 ? 3 : 2;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0A0E14),
              gradient: RadialGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF0A0E14)],
                radius: 1.3,
                center: Alignment(0.0, -0.2),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _PremiumMeshPainter())),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Column(
                    children: [
                      Text(
                        "Premium Benefits",
                        style: GoogleFonts.playfairDisplay(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Unlock the full CrickNova Elite experience",
                        style: GoogleFonts.montserrat(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _GlowDivider(),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: _features.length,
                  itemBuilder: (context, index) {
                    final feature = _features[index];
                    return _PremiumFeatureTile(feature: feature, index: index);
                  },
                ),
                const SizedBox(height: 18),
                const _GlowDivider(),
                const SizedBox(height: 18),
                _ShimmerCtaButton(
                  controller: _shimmerController,
                  onTap: widget.onUpgrade,
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Close",
                      style: GoogleFonts.montserrat(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumMeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD86B).withValues(alpha: 0.06)
      ..strokeWidth = 1;

    const spacing = 36.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }

    final overlay = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width + size.height; x += spacing * 1.3) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        overlay,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumMeshPainter oldDelegate) => false;
}

class _GlowDivider extends StatelessWidget {
  const _GlowDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFFFFD86B).withValues(alpha: 0.5),
            const Color(0xFF3B82F6).withValues(alpha: 0.4),
            Colors.transparent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD86B).withValues(alpha: 0.25),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _PremiumFeatureTile extends StatelessWidget {
  final _PremiumFeature feature;
  final int index;

  const _PremiumFeatureTile({required this.feature, required this.index});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 280 + (index * 60)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFD86B).withValues(alpha: 0.35),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GradientIcon(icon: feature.icon),
                  const SizedBox(height: 10),
                  Text(
                    feature.title,
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    feature.description,
                    style: GoogleFonts.montserrat(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              if (feature.badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD86B), Color(0xFF3B82F6)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD86B).withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      feature.badge!,
                      style: GoogleFonts.montserrat(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  final IconData icon;

  const _GradientIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: const Color(0xFFFFD86B).withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            colors: [Color(0xFFFFD86B), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds);
        },
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ShimmerCtaButton extends StatelessWidget {
  final AnimationController controller;
  final VoidCallback onTap;

  const _ShimmerCtaButton({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD86B), Color(0xFFB8860B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD86B).withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                "Unlock Elite Perks",
                style: GoogleFonts.montserrat(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return FractionallySizedBox(
                    widthFactor: 0.35,
                    alignment: Alignment(-1 + (2 * controller.value), 0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
              description:
                  "Unlock at 50,000 XP milestone. Includes Official Jersey + Special Gift.",
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
              description:
                  "Unlock at 20 Lakh XP milestone. Delivered in 30–45 days.",
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
                  final daysPassed = DateTime.now()
                      .difference(claimDate!)
                      .inDays;
                  final daysRemaining = 30 - daysPassed;
                  final safeRemaining = daysRemaining < 0 ? 0 : daysRemaining;

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
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: eligible ? Colors.black : const Color(0xFF0F172A),
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

  void showClaimBottomSheet(
    BuildContext context,
    String rewardTitle,
    int threshold,
  ) {
    final rewardsContext = context;
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final pincodeController = TextEditingController();
    final houseController = TextEditingController();
    final roadController = TextEditingController();
    final landmarkController = TextEditingController();
    final cityStateController = TextEditingController();
    String selectedCountryCode = "+91";
    String selectedSize = "M";
    String selectedGlovesSize = "Men";
    String selectedPadsSize = "Men";
    String selectedHelmetSize = "Men";
    String selectedBatCompany = "SS";
    String selectedBatWeight = "Medium (1130–1200g)";
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
                              Icon(
                                Icons.workspace_premium,
                                color: Color(0xFFFFD700),
                                size: 40,
                              ),
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
                            Visibility(
                              visible: false,
                              maintainState: true,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    dropdownColor: const Color(0xFF1E293B),
                                    value: selectedCountryCode,
                                    style: const TextStyle(color: Colors.white),
                                    items:
                                        const [
                                          "+1",
                                          "+7",
                                          "+20",
                                          "+27",
                                          "+30",
                                          "+31",
                                          "+32",
                                          "+33",
                                          "+34",
                                          "+36",
                                          "+39",
                                          "+40",
                                          "+41",
                                          "+43",
                                          "+44",
                                          "+45",
                                          "+46",
                                          "+47",
                                          "+48",
                                          "+49",
                                          "+51",
                                          "+52",
                                          "+53",
                                          "+54",
                                          "+55",
                                          "+56",
                                          "+57",
                                          "+58",
                                          "+60",
                                          "+61",
                                          "+62",
                                          "+63",
                                          "+64",
                                          "+65",
                                          "+66",
                                          "+81",
                                          "+82",
                                          "+84",
                                          "+86",
                                          "+90",
                                          "+91",
                                          "+93",
                                          "+94",
                                          "+95",
                                          "+98",
                                          "+211",
                                          "+212",
                                          "+213",
                                          "+216",
                                          "+218",
                                          "+220",
                                          "+221",
                                          "+222",
                                          "+223",
                                          "+224",
                                          "+225",
                                          "+226",
                                          "+227",
                                          "+228",
                                          "+229",
                                          "+230",
                                          "+231",
                                          "+232",
                                          "+233",
                                          "+234",
                                          "+235",
                                          "+236",
                                          "+237",
                                          "+238",
                                          "+239",
                                          "+240",
                                          "+241",
                                          "+242",
                                          "+243",
                                          "+244",
                                          "+245",
                                          "+246",
                                          "+248",
                                          "+249",
                                          "+250",
                                          "+251",
                                          "+252",
                                          "+253",
                                          "+254",
                                          "+255",
                                          "+256",
                                          "+257",
                                          "+258",
                                          "+260",
                                          "+261",
                                          "+262",
                                          "+263",
                                          "+264",
                                          "+265",
                                          "+266",
                                          "+267",
                                          "+268",
                                          "+269",
                                          "+290",
                                          "+291",
                                          "+297",
                                          "+298",
                                          "+299",
                                          "+350",
                                          "+351",
                                          "+352",
                                          "+353",
                                          "+354",
                                          "+355",
                                          "+356",
                                          "+357",
                                          "+358",
                                          "+359",
                                          "+370",
                                          "+371",
                                          "+372",
                                          "+373",
                                          "+374",
                                          "+375",
                                          "+376",
                                          "+377",
                                          "+378",
                                          "+380",
                                          "+381",
                                          "+382",
                                          "+383",
                                          "+385",
                                          "+386",
                                          "+387",
                                          "+389",
                                          "+420",
                                          "+421",
                                          "+423",
                                          "+500",
                                          "+501",
                                          "+502",
                                          "+503",
                                          "+504",
                                          "+505",
                                          "+506",
                                          "+507",
                                          "+508",
                                          "+509",
                                          "+590",
                                          "+591",
                                          "+592",
                                          "+593",
                                          "+594",
                                          "+595",
                                          "+596",
                                          "+597",
                                          "+598",
                                          "+599",
                                          "+670",
                                          "+672",
                                          "+673",
                                          "+674",
                                          "+675",
                                          "+676",
                                          "+677",
                                          "+678",
                                          "+679",
                                          "+680",
                                          "+681",
                                          "+682",
                                          "+683",
                                          "+685",
                                          "+686",
                                          "+687",
                                          "+688",
                                          "+689",
                                          "+690",
                                          "+691",
                                          "+692",
                                          "+850",
                                          "+852",
                                          "+853",
                                          "+855",
                                          "+856",
                                          "+880",
                                          "+886",
                                          "+960",
                                          "+961",
                                          "+962",
                                          "+963",
                                          "+964",
                                          "+965",
                                          "+966",
                                          "+967",
                                          "+968",
                                          "+970",
                                          "+971",
                                          "+972",
                                          "+973",
                                          "+974",
                                          "+975",
                                          "+976",
                                          "+977",
                                          "+992",
                                          "+993",
                                          "+994",
                                          "+995",
                                          "+996",
                                          "+998",
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
                            ),
                            const SizedBox.shrink(),
                            Expanded(
                              child: TextFormField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.phone,
                                    color: Color(0xFF3B82F6),
                                  ),
                                  labelText:
                                      "Mobile Number (with country code)",
                                  labelStyle: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                  helperText: "Example: +91XXXXXXXXXX",
                                  helperStyle: const TextStyle(
                                    color: Colors.white54,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                validator: (value) {
                                  final raw = (value ?? "").trim();
                                  if (raw.isEmpty) {
                                    return "Contact number required";
                                  }
                                  if (!raw.startsWith("+")) {
                                    return "Add country code (example: +91)";
                                  }
                                  final normalized =
                                      "+${raw.substring(1).replaceAll(RegExp(r'\\D'), '')}";
                                  if (normalized.length < 8) {
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
                            children:
                                [
                                  "S",
                                  "M",
                                  "L",
                                  "XL",
                                  "XXL",
                                  "2XL",
                                  "3XL",
                                  "4XL",
                                ].map((size) {
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
                            children: ["Small", "Youth", "Men"].map((size) {
                              final bool isSelected =
                                  selectedGlovesSize == size;
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
                            options: ["Small", "Youth", "Men"],
                            onChanged: (val) =>
                                setState(() => selectedPadsSize = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Batting Gloves Size",
                            value: selectedGlovesSize,
                            options: ["Small", "Youth", "Men"],
                            onChanged: (val) =>
                                setState(() => selectedGlovesSize = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Helmet Size",
                            value: selectedHelmetSize,
                            options: ["Small", "Youth", "Men"],
                            onChanged: (val) =>
                                setState(() => selectedHelmetSize = val),
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
                          const SizedBox(height: 6),
                          const Text(
                            "Delivered in 30–45 days",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _kitDropdown(
                            label: "Bat Company",
                            value: selectedBatCompany,
                            options: ["SS", "SG", "MRF", "GM", "Kookaburra"],
                            onChanged: (val) =>
                                setState(() => selectedBatCompany = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Bat Weight",
                            value: selectedBatWeight,
                            options: [
                              "Light (1080–1120g)",
                              "Medium (1130–1200g)",
                              "Heavy (1200g+)",
                            ],
                            onChanged: (val) =>
                                setState(() => selectedBatWeight = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Bat Size",
                            value: selectedBatSize,
                            options: ["SH", "LH"],
                            onChanged: (val) =>
                                setState(() => selectedBatSize = val),
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
                                final orderSummary =
                                    '''
Reward: $rewardTitle
${threshold == 50000 ? "Jersey Size: $selectedSize" : ""}
${threshold == 500000 ? "Gloves Size: $selectedGlovesSize" : ""}
${threshold == 1000000 ? "Pads: $selectedPadsSize\nGloves: $selectedGlovesSize\nHelmet: $selectedHelmetSize" : ""}
${threshold == 2000000 ? "Bat Company: $selectedBatCompany\nBat Weight: $selectedBatWeight\nBat Size: $selectedBatSize" : ""}

Full Name: ${nameController.text}
Phone: ${phoneController.text}

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
                                    FirebaseAuth.instance.currentUser?.uid ??
                                    "guest";
                                final box = await Hive.openBox(
                                  "local_stats_$uid",
                                );

                                final currentXP =
                                    box.get("xp", defaultValue: 0) as int;
                                final now = DateTime.now();

                                final isJersey = threshold == 50000;
                                if (isJersey) {
                                  // Do NOT reset XP. Keep cumulative progress.
                                  await box.put("xpAtClaim", currentXP);
                                  await box.put(
                                    "claimDateMillis",
                                    now.millisecondsSinceEpoch,
                                  );
                                }
                                await box.put("claimed_$threshold", true);
                                await box.flush();

                                if (mounted) {
                                  this.setState(() {
                                    if (isJersey) {
                                      jerseyClaimed = true;
                                      claimDate = now;
                                      xpAtClaim = currentXP;
                                    }
                                    totalXP = currentXP;
                                  });
                                }

                                Navigator.pop(context);

                                await showDialog(
                                  context: rewardsContext,
                                  barrierDismissible: false,
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
                                        Icon(
                                          Icons.celebration,
                                          color: Color(0xFFFFD700),
                                          size: 60,
                                        ),
                                        SizedBox(height: 12),
                                        Text(
                                          "Reward claimed successfully!\nKeep climbing to the next milestone 🚀",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(rewardsContext),
                                        child: const Text(
                                          "OK",
                                          style: TextStyle(
                                            color: Color(0xFF38BDF8),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (!mounted) return;
                                Navigator.of(rewardsContext).pop();
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
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
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
