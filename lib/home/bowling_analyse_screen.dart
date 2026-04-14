import 'package:flutter/material.dart';

import '../compare/analyse_yourself_screen.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../upload/upload_screen.dart';

class BowlingAnalyseScreen extends StatelessWidget {
  const BowlingAnalyseScreen({super.key});

  void _openIfAllowed(
    BuildContext context,
    Widget destination, {
    required String lockEntrySource,
  }) {
    if (!PremiumService.hasBowlingAnalysisAccess) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PremiumScreen(entrySource: lockEntrySource),
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E11),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0E11),
          foregroundColor: Colors.white,
          title: const Text("Bowling Analysis"),
          bottom: const TabBar(
            indicatorColor: Color(0xFF38BDF8),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: "Mistake Detection"),
              Tab(text: "Compare Vid"),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B0E11), Color(0xFF060A12)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: TabBarView(
            children: [
              _BowlingActionCard(
                icon: Icons.sports_baseball_rounded,
                title: "Bowling Mistake Detection",
                subtitle:
                    "Upload your bowling clip and get bowling-specific mistakes with fix drills.",
                buttonText: "Start Mistake Detection",
                onTap: () => _openIfAllowed(
                  context,
                  const UploadScreen(bowlingMode: true),
                  lockEntrySource: "mistake_lock",
                ),
              ),
              _BowlingActionCard(
                icon: Icons.compare_arrows_rounded,
                title: "Bowling Compare",
                subtitle:
                    "Compare two bowling videos and get bowling difference feedback.",
                buttonText: "Start Compare",
                onTap: () => _openIfAllowed(
                  context,
                  const AnalyseYourselfScreen(bowlingMode: true),
                  lockEntrySource: "analyse",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BowlingActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  const _BowlingActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withOpacity(0.45),
                  ),
                ),
                child: Icon(icon, color: const Color(0xFF7DD3FC), size: 30),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onTap,
                  child: Text(
                    buttonText,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
