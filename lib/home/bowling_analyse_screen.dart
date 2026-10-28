import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../compare/analyse_yourself_screen.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../services/analysis_credit_service.dart';
import '../theme/crickx_colors.dart';
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

  Future<void> _showWatchAdDialog(
    BuildContext context, {
    required VoidCallback onUnlocked,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _BowlingWatchAdDialog(
        onCreditGranted: () {
          Navigator.of(dialogCtx).pop();
          onUnlocked();
        },
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
        backgroundColor: CrickXColors.graphiteBg,
        appBar: AppBar(
          backgroundColor: CrickXColors.graphiteBg,
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
        body: Container(
          color: CrickXColors.graphiteBg,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: CrickXColors.graphiteBorder),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: CrickXColors.onLime,
                      unselectedLabelColor: Colors.white60,
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      indicator: BoxDecoration(
                        color: CrickXColors.limeSpark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tabs: const [
                        Tab(text: 'Analysis'),
                        Tab(text: 'Bowling Compare'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      // TAB 1: Bowling Analysis (Mistake Detection / Speed & Swing)
                      ValueListenableBuilder<int>(
                        valueListenable:
                            AnalysisCreditService.instance.creditsNotifier,
                        builder: (context, credits, _) {
                          final hasDetectAccess =
                              mistakeUnlocked || credits > 0;

                          return Center(
                            child: _MinimalBowlingAction(
                              icon: Icons.track_changes_rounded,
                              title: 'Bowling Analysis',
                              subtitle:
                                  'Upload a bowling clip to check speed, swing, spin and get AI coach analysis.',
                              buttonText: hasDetectAccess
                                  ? (credits > 0 && !mistakeUnlocked
                                      ? 'Start AI Analysis ($credits Left)'
                                      : 'Start AI Analysis')
                                  : 'Watch Ad to Unlock 4 Bowling Analyses',
                              locked: false,
                              onTap: () {
                                if (hasDetectAccess) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const UploadScreen(
                                        bowlingMode: true,
                                      ),
                                    ),
                                  );
                                } else {
                                  _showWatchAdDialog(
                                    context,
                                    onUnlocked: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const UploadScreen(
                                            bowlingMode: true,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),

                      // TAB 2: Bowling Compare (Two Video Comparison)
                      Center(
                        child: _MinimalBowlingAction(
                          icon: Icons.compare_arrows_rounded,
                          title: 'Bowling Compare',
                          subtitle:
                              'Choose two bowling clips to compare run-up, gather, release point, wrist seam, and follow-through.',
                          buttonText: compareUnlocked
                              ? 'Compare Bowling Clips'
                              : 'Unlock Bowling Compare',
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

// ── Bowling Watch Ad Dialog ──────────────────────────────────────────────────
class _BowlingWatchAdDialog extends StatefulWidget {
  const _BowlingWatchAdDialog({
    required this.onCreditGranted,
  });

  final VoidCallback onCreditGranted;

  @override
  State<_BowlingWatchAdDialog> createState() => _BowlingWatchAdDialogState();
}

class _BowlingWatchAdDialogState extends State<_BowlingWatchAdDialog> {
  bool _loading = false;
  String? _message;

  Future<void> _handleWatchAd() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });

    final result = await AnalysisCreditService.instance.watchAdForCredit();
    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case AdWatchResult.rewardEarned:
        widget.onCreditGranted();
        break;
      case AdWatchResult.adNotAvailable:
        setState(() =>
            _message = "Ad isn't available right now. Please try again.");
        break;
      case AdWatchResult.adClosedEarly:
        setState(
            () => _message = 'Watch the complete ad to earn your 4 analyses.');
        break;
      case AdWatchResult.premiumUser:
        widget.onCreditGranted();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CrickXColors.graphiteBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
      ),
      title: Text(
        '🎬 Watch Ad to Unlock',
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Watch a short ad to unlock 4 AI Bowling Analyses & Speed Detections.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _message!.startsWith("Ad isn")
                      ? Colors.redAccent
                      : Colors.orangeAccent,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CrickXColors.limeSpark,
                foregroundColor: CrickXColors.onLime,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _loading ? null : _handleWatchAd,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Watch Ad 🎬',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
      ],
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
              color: CrickXColors.graphite,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: CrickXColors.graphiteBorder,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
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
                    color: CrickXColors.limeSpark,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: CrickXColors.limeSpark.withValues(alpha: 0.35),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: CrickXColors.onLime, size: 28),
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
                      backgroundColor: CrickXColors.limeSpark,
                      foregroundColor: CrickXColors.onLime,
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
