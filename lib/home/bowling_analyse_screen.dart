import 'package:flutter/material.dart';

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
                lockCaption: "Unlock elite bowling AI with Pro or Ultra.",
                onTap: () {
                  if (!mistakeUnlocked) {
                    _goPremium(context, "bowling_analysis");
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
                lockCaption: "Unlock elite video comparison with Pro or Ultra.",
                onTap: () {
                  if (!compareUnlocked) {
                    _goPremium(context, "bowling_compare");
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
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black,
              elevation: locked ? 8 : 2,
              shadowColor: const Color(0xFF38BDF8).withOpacity(0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onTap,
            child: Text(
              locked ? "Go Elite" : buttonText,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
            child: Center(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.all(18),
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
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}
