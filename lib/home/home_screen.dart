import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../upload/upload_screen.dart';   // <-- your upload screen
import '../compare/analyse_yourself_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userName;

  const HomeScreen({super.key, required this.userName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String planName = "Free";
  int planPrice = 0;

  int chatUsed = 0;
  int chatLimit = 0;

  int mistakeUsed = 0;
  int mistakeLimit = 0;

  List<String> trainingVideos = [];

  @override
  void initState() {
    super.initState();
    loadTrainingVideos();
    loadUsageStatus();
  }

  Future<void> loadTrainingVideos() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      trainingVideos = prefs.getStringList("trainingVideos") ?? [];
    });
  }

  Future<void> loadUsageStatus() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      planName = prefs.getString("planName") ?? "Free";
      planPrice = prefs.getInt("planPrice") ?? 0;

      chatUsed = prefs.getInt("chatUsed") ?? 0;
      chatLimit = prefs.getInt("chatLimit") ?? 0;

      mistakeUsed = prefs.getInt("mistakeUsed") ?? 0;
      mistakeLimit = prefs.getInt("mistakeLimit") ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // HEADER
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF050A1E),
                    Color(0xFF0E1A36),
                    Color(0xFF1E3A8A),
                    Color(0xFF3B82F6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent,
                    blurRadius: 40,
                    spreadRadius: 1,
                    offset: Offset(0, 6),
                  ),
                ],
              ),

              child: Stack(
                children: [
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
                            Colors.blueAccent.withOpacity(0.6),
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
                          shadows: [
                            Shadow(
                              color: Colors.blueAccent,
                              blurRadius: 15,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            Colors.white70,
                            Colors.blueAccent.shade100,
                          ],
                        ).createShader(bounds),
                        child: Text(
                          "Ready for today’s cricket analysis?",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
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
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => UploadScreen()),
                      );
                      await loadTrainingVideos();
                    },
                  ),
                  const SizedBox(height: 14),
                  _actionCard(
                    title: "Analyse Yourself",
                    subtitle: "Compare two videos and see differences",
                    icon: Icons.compare_rounded,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AnalyseYourselfScreen(),
                        ),
                      );
                      await loadTrainingVideos();
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
                      style: TextStyle(color: Colors.black54),
                    )
                  else
                    ...trainingVideos.map((v) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                                color: Colors.blueAccent, size: 30),
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
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => UploadScreen(),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
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
                              planPrice > 0 ? "₹$planPrice" : "Free",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: planPrice > 0 ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        _usageRow(
                          label: "AI Coach Chats",
                          used: chatUsed,
                          total: chatLimit,
                        ),
                        const SizedBox(height: 10),
                        _usageRow(
                          label: "Mistake Detection",
                          used: mistakeUsed,
                          total: mistakeLimit,
                        ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              spreadRadius: 2,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 34, color: Colors.blueAccent),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 22, color: Colors.black38),
          ],
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
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        Text(
          "$used/$displayTotal",
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: total == 0
                ? Colors.grey
                : (used >= total ? Colors.red : Colors.blueAccent),
          ),
        ),
      ],
    );
  }

  Widget _premiumBadge() {
    if (planPrice <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.workspace_premium, color: Colors.black, size: 22),
          SizedBox(width: 8),
          Text(
            "PREMIUM",
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}