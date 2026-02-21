import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/premium_service.dart';
import '../premium/premium_screen.dart';
import '../upload/upload_screen.dart';
import '../compare/analyse_yourself_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userName;

  const HomeScreen({super.key, required this.userName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> trainingVideos = [];
  List<double> speedHistory = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    PremiumService.premiumNotifier.addListener(_onPremiumChanged);
  }

  void _onPremiumChanged() {
    if (!mounted) return;
    setState(() {});
  }


  @override
  void initState() {
    super.initState();
    _bootstrapAuthAndData();
  }

  Future<void> _bootstrapAuthAndData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 🔐 Force refresh Firebase ID token so backend always receives a valid one
      final String? token = await user.getIdToken(true);
      if (token != null && token.isNotEmpty) {
        // ⚠️ DEBUG ONLY: log full token to test backend auth
        debugPrint("🔥 FULL_FIREBASE_TOKEN=$token");
      } else {
        debugPrint("⚠️ HOME SCREEN: Firebase token is null or empty");
      }

      // ✅ Restore premium ONLY after auth is fully ready
      await PremiumService.restoreOnLaunch();
    }

    await loadSpeedHistory();
    await loadTrainingVideos();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> loadSpeedHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList("speedHistory") ?? [];
    final allSpeeds = raw.map((e) => double.tryParse(e) ?? 0).toList();

    // Keep only last 6 balls for Current Session view
    if (allSpeeds.length > 6) {
      speedHistory = allSpeeds.sublist(allSpeeds.length - 6);
    } else {
      speedHistory = allSpeeds;
    }
  }

  Future<void> loadTrainingVideos() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      trainingVideos = prefs.getStringList("trainingVideos") ?? [];
    });
  }


  @override
  Widget build(BuildContext context) {
    debugPrint("HOME → isPremium=${PremiumService.isPremium}");
    return Container(
      color: const Color(0xFF020617),
      child: RefreshIndicator(
        color: const Color(0xFF00FF88),
        backgroundColor: const Color(0xFF0F172A),
        onRefresh: () async {
          await _bootstrapAuthAndData();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: kBottomNavigationBarHeight + 24),
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0B0F1A),
                    Color(0xFF111827),
                    Color(0xFF0F172A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 40,
                    spreadRadius: 1,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // (keep the circle, but remove purple-heavy glow)
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF111827).withOpacity(0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Welcome back, ${widget.userName} ",
                        style: GoogleFonts.poppins(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Ready for today’s cricket analysis?",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),
            _premiumBadge(),

            // ACTION TABS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _actionCard(
                    title: "Upload Training Video",
                    subtitle: "AI will analyze your batting or bowling",
                    icon: Icons.upload_file_outlined,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const UploadScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _actionCard(
                    title: "Analyse Yourself",
                    subtitle: "Compare two videos and see differences",
                    icon: Icons.compare_arrows_outlined,
                    onTap: () {
                      if (!PremiumService.isLoaded) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Checking premium status...")),
                        );
                        return;
                      }

                      if (!PremiumService.isPremium) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PremiumScreen(entrySource: "analyse"),
                          ),
                        );
                        return;
                      }

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AnalyseYourselfScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),


            const SizedBox(height: 50),

            // REMAINING FEATURES
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Remaining Features",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Premium",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              PremiumService.isPremium ? "Premium" : "Free",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: PremiumService.isPremium ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _usageRow(
                          label: "AI Coach Chats",
                          used: PremiumService.chatUsed,
                          total: PremiumService.chatLimit,
                        ),
                        const SizedBox(height: 10),
                        _usageRow(
                          label: "Mistake Detection",
                          used: PremiumService.mistakeUsed,
                          total: PremiumService.mistakeLimit,
                        ),
                        // Analyse Yourself usage row if allowed
                        if (PremiumService.compareLimit > 0) ...[
                          const SizedBox(height: 10),
                          _usageRow(
                            label: "Analyse Yourself",
                            used: PremiumService.compareUsed,
                            total: PremiumService.compareLimit,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          debugPrint('ACTION CARD TAPPED → $title');
          onTap();
        },
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                spreadRadius: 2,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, size: 32, color: Colors.white70),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 20,
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _usageRow({
    required String label,
    required int used,
    required int total,
  }) {
    final displayTotal = total == 0 ? "-" : total.toString();

    IconData iconData;

    if (label.contains("Chat")) {
      iconData = Icons.smart_toy_outlined; // AI Coach Robot
    } else if (label.contains("Mistake")) {
      iconData = Icons.track_changes_outlined; // Target icon
    } else {
      iconData = Icons.analytics_outlined;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                iconData,
                size: 18,
                color: Colors.white70,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Text(
            "$used/$displayTotal",
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFFD700), // Gold for Elite feel
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumBadge() {
    if (!PremiumService.isPremium) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 20, top: 4, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
          ),
          borderRadius: BorderRadius.circular(50),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.star_rounded, color: Colors.black, size: 16),
            SizedBox(width: 6),
            Text(
              "ELITE USER",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
  @override
  void dispose() {
    PremiumService.premiumNotifier.removeListener(_onPremiumChanged);
    super.dispose();
  }
}
