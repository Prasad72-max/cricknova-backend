import 'package:flutter/material.dart';
import 'dart:ui';

import '../compare/analyse_yourself_screen.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../upload/upload_screen.dart';

class BowlingAnalyseScreen extends StatelessWidget {
  const BowlingAnalyseScreen({super.key});

  bool _hasMistakeAccess() {
    return PremiumService.isLoaded && PremiumService.isPremiumActive;
  }

  bool _hasCompareAccess() {
    return PremiumService.hasCompareAccess;
  }

  void _goPremium(BuildContext context, String entrySource) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PremiumScreen(entrySource: entrySource),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool mistakeUnlocked = _hasMistakeAccess();
    final bool compareUnlocked = _hasCompareAccess();
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
                locked: !mistakeUnlocked,
                lockCaption: "Locked for Free users. Upgrade to unlock.",
                onTap: () {
                  if (!mistakeUnlocked) {
                    _goPremium(context, "mistake_lock");
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UploadScreen(bowlingMode: true),
                    ),
                  );
                },
              ),
              _BowlingActionCard(
                icon: Icons.compare_arrows_rounded,
                title: "Bowling Compare",
                subtitle:
                    "Compare two bowling videos and get bowling difference feedback.",
                buttonText: "Start Compare",
                locked: !compareUnlocked,
                lockCaption:
                    "Unlocked only in Pro/Ultra (₹499/₹1999 or \$69.99/\$169.99).",
                onTap: () {
                  if (!compareUnlocked) {
                    _goPremium(context, "analyse");
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AnalyseYourselfScreen(bowlingMode: true),
                    ),
                  );
                },
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
  final bool locked;
  final String? lockCaption;

  const _BowlingActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
    this.locked = false,
    this.lockCaption,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
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
              backgroundColor: locked
                  ? Colors.white12
                  : const Color(0xFF38BDF8),
              foregroundColor: locked ? Colors.white70 : Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onTap,
            child: Text(
              locked ? "LOCKED" : buttonText,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (locked && lockCaption != null) ...[
          const SizedBox(height: 10),
          Text(
            lockCaption!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 12.5),
          ),
        ],
      ],
    );

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
          child: locked
              ? Stack(
                  children: [
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Opacity(opacity: 0.85, child: content),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.lock_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                              SizedBox(height: 10),
                              Text(
                                "Premium Locked",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : content,
        ),
      ),
    );
  }
}
