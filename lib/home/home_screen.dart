import 'dart:io';
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

    await loadTrainingVideos();
    if (!mounted) return;
    setState(() {});
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
      child: ListView(
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
                        "Welcome back, ${widget.userName} 👋",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Ready for today’s cricket analysis?",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.white70,
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
                    icon: Icons.upload_file_rounded,
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
                    icon: Icons.compare_rounded,
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

            const SizedBox(height: 30),

            // VIDEO LIST
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "My Training Videos",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (trainingVideos.isEmpty)
                    const Text(
                      "No training videos uploaded yet",
                      style: TextStyle(color: Colors.white54),
                    )
                  else
                    ...trainingVideos.map((v) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ],
                          ),
                          child: ListTile(
                            title: Text(v,
                                style:
                                    GoogleFonts.poppins(fontSize: 15)),
                            trailing: const Icon(Icons.play_circle_fill,
                                color: Color(0xFF7C3AED), size: 30),
                            onTap: () {
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
                                          leading: const Icon(Icons.play_circle_fill),
                                          title: const Text("Play Video"),
                                          onTap: () {
                                            Navigator.pop(context);
                                            // Future: video preview screen
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text("Video preview coming soon")),
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.analytics),
                                          title: const Text("Analyse Video"),
                                          onTap: () {
                                            Navigator.pop(context);

                                            if (!PremiumService.canCompare()) {
                                              PremiumService.showPaywall(context);
                                              return;
                                            }

                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => const AnalyseYourselfScreen(),
                                              ),
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.delete, color: Colors.red),
                                          title: const Text("Delete Video"),
                                          onTap: () async {
                                            Navigator.pop(context);
                                            final prefs = await SharedPreferences.getInstance();
                                            final videos =
                                                prefs.getStringList("trainingVideos") ?? [];
                                            videos.remove(v);
                                            await prefs.setStringList("trainingVideos", videos);
                                            await loadTrainingVideos();
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        )),
                ],
              ),
            ),

            const SizedBox(height: 30),

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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1220),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Color(0xFF1F2937)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // PLAN HEADER
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Color(0xFF1F2937)),
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
              Icon(icon, size: 36, color: const Color(0xFF38BDF8)),
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
                color: Colors.black38,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
        ),
        Text(
          "$used/$displayTotal",
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: total == 0
                ? Colors.grey
                : (used >= total ? Colors.red : Color(0xFF38BDF8)),
          ),
        ),
      ],
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
          borderRadius: BorderRadius.circular(14),
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
            Icon(Icons.workspace_premium, color: Colors.black, size: 14),
            SizedBox(width: 4),
            Text(
              "PREMIUM USER",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.6,
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