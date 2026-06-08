import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../compare/analyse_yourself_screen.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../upload/upload_screen.dart';

class BowlingAnalyseScreen extends StatelessWidget {
  const BowlingAnalyseScreen({super.key});

  void _goPremium(BuildContext context, String entrySource) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PremiumScreen(entrySource: entrySource),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mistakeUnlocked =
        PremiumService.isLoaded && PremiumService.isPremiumActive;
    final compareUnlocked = PremiumService.hasCompareAccess;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF02040B),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Bowling Analysis',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF02040B), Color(0xFF040A18), Color(0xFF010204)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827).withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      indicator: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF7CF0D5).withValues(alpha: 0.5),
                        ),
                      ),
                      tabs: const [
                        Tab(text: 'Detect'),
                        Tab(text: 'Compare'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      _MinimalBowlingAction(
                        icon: Icons.track_changes_rounded,
                        title: 'Detect Bowling',
                        subtitle:
                            'Upload a bowling clip to check speed, swing, spin and get coach analysis.',
                        buttonText: 'Upload Video',
                        locked: !mistakeUnlocked,
                        onTap: () {
                          if (!mistakeUnlocked) {
                            _goPremium(context, 'bowling_analysis');
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const UploadScreen(bowlingMode: true),
                            ),
                          );
                        },
                      ),
                      _MinimalBowlingAction(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Compare Bowling',
                        subtitle:
                            'Choose two bowling clips and review the technique difference.',
                        buttonText: 'Choose Videos',
                        locked: !compareUnlocked,
                        onTap: () {
                          if (!compareUnlocked) {
                            _goPremium(context, 'bowling_compare');
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AnalyseYourselfScreen(
                                bowlingMode: true,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimalBowlingAction extends StatelessWidget {
  const _MinimalBowlingAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.locked,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7CF0D5), Color(0xFF1AAE8B)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7CF0D5).withValues(alpha: 0.2),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: const Color(0xFF03110E), size: 28),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF7CF0D5),
                      foregroundColor: const Color(0xFF03110E),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(locked ? 'View Plans' : buttonText),
                  ),
                ),
                if (locked) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Available with an active plan',
                    style: GoogleFonts.poppins(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
