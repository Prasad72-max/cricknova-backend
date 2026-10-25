import 'package:flutter/material.dart';
import '../services/analysis_credit_service.dart';
import '../services/premium_service.dart';
import '../services/admob_service.dart';
import '../theme/crickx_colors.dart';

/// Reusable "Watch Ad to Unlock 4 AI Cricket Analyses" button.
/// Automatically hidden for premium users.
/// Shows loading state while ad loads.
class WatchAdButton extends StatefulWidget {
  const WatchAdButton({
    super.key,
    required this.onCreditGranted,
    this.label = 'Watch Ad to Unlock 4 AI Cricket Analyses',
    this.buttonText = 'Watch Ad 🎬',
    this.compact = false,
  });

  final VoidCallback onCreditGranted;
  final String label;
  final String buttonText;
  final bool compact;

  @override
  State<WatchAdButton> createState() => _WatchAdButtonState();
}

class _WatchAdButtonState extends State<WatchAdButton> {
  bool _loading = false;
  String? _message;

  Future<void> _handleWatchAd() async {
    if (_loading) return; // Prevent double tap
    setState(() {
      _loading = true;
      _message = null;
    });

    final result = await AnalysisCreditService.instance.watchAdForCredit();

    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case AdWatchResult.rewardEarned:
        setState(() => _message = '✅ 4 AI Analyses Unlocked!');
        widget.onCreditGranted();
        break;
      case AdWatchResult.adNotAvailable:
        setState(() =>
            _message = "Ad isn't available right now. Please try again.");
        break;
      case AdWatchResult.adClosedEarly:
        setState(
            () => _message = 'Watch the complete ad to earn analysis.');
        break;
      case AdWatchResult.premiumUser:
        // Should not appear for premium users but handle gracefully
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hide entirely for premium users
    if (PremiumService.isPremiumActive) return const SizedBox.shrink();

    final isAdReady = AdMobService.instance.isRewardedAdReady;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
        GestureDetector(
          onTap: _loading ? null : _handleWatchAd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              vertical: widget.compact ? 10 : 14,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _loading || !isAdReady
                    ? [Colors.grey.shade800, Colors.grey.shade700]
                    : [
                        CrickXColors.limeSpark,
                        CrickXColors.limeSparkDark,
                      ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: isAdReady && !_loading
                  ? [
                      BoxShadow(
                        color: CrickXColors.limeSpark.withOpacity(0.35),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(CrickXColors.onLime),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      isAdReady ? widget.buttonText : 'Loading Ad...',
                      style: const TextStyle(
                        color: CrickXColors.onLime,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _message!.startsWith('✅')
                    ? Colors.greenAccent
                    : Colors.redAccent.shade100,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 4),
        // Credit balance display
        ValueListenableBuilder<int>(
          valueListenable: AnalysisCreditService.instance.creditsNotifier,
          builder: (_, credits, __) {
            if (credits == 0) return const SizedBox.shrink();
            return Text(
              '🎯 $credits AI Analysis credit${credits > 1 ? 's' : ''} available',
              style: const TextStyle(
                color: CrickXColors.limeSpark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
      ],
    );
  }
}
