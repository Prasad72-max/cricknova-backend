import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'cricknova_paywall_screen.dart';
import 'onboarding_ui_tokens.dart';

const Color _paywallBg = Color(0xFF080808);
const Color _paywallGold = Color(0xFFFFD700);

class CricknovaPaywallReelScreen extends StatefulWidget {
  final String userName;

  const CricknovaPaywallReelScreen({super.key, required this.userName});

  @override
  State<CricknovaPaywallReelScreen> createState() =>
      _CricknovaPaywallReelScreenState();
}

class _CricknovaPaywallReelScreenState
    extends State<CricknovaPaywallReelScreen> {
  void _continueToPaywall() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CricknovaPaywallScreen(userName: widget.userName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paywallBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: OnboardingUiTokens.maxContentWidth,
              ),
              child: CricknovaPaywallReelView(onContinue: _continueToPaywall),
            ),
          ),
        ),
      ),
    );
  }
}

class CricknovaPaywallReelView extends StatefulWidget {
  final VoidCallback onContinue;

  const CricknovaPaywallReelView({super.key, required this.onContinue});

  @override
  State<CricknovaPaywallReelView> createState() =>
      _CricknovaPaywallReelViewState();
}

class _CricknovaPaywallReelViewState extends State<CricknovaPaywallReelView> {
  static const String _assetPath = 'assets/videos/paywall_intro_reel.mp4';

  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(_assetPath)..setLooping(false);
    unawaited(_initializeVideo());
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await _controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to load intro reel.');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxVideoHeight = media.size.height * 0.68;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxVideoHeight),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFF030506)),
                      if (_ready)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller.value.size.width,
                            height: _controller.value.size.height,
                            child: VideoPlayer(_controller),
                          ),
                        )
                      else
                        Center(
                          child: _error == null
                              ? const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _paywallGold,
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: OnboardingTextStyles.uiSans(
                                      color: OnboardingColors.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.08),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.46),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _paywallGold.withValues(alpha: 0.28),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Text(
                          'CRICKNOVA ELITE',
                          style: OnboardingTextStyles.uiMono(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Elite cricket intelligence. Affordable for serious players.',
          textAlign: TextAlign.center,
          style: OnboardingTextStyles.uiSans(
            color: OnboardingColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: widget.onContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: _paywallGold,
              foregroundColor: Colors.black,
              elevation: 0,
              shadowColor: _paywallGold.withValues(alpha: 0.36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: OnboardingTextStyles.uiSans(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}
