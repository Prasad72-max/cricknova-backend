import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../navigation/main_navigation.dart';
import '../services/pricing_location_service.dart';
import '../services/premium_service.dart';
import '../services/subscription_provider.dart';
import '../services/trial_access_service.dart';
import '../auth/login_screen.dart';
import 'cricknova_game_snapshot_view.dart';
import 'cricknova_onboarding_store.dart';
import 'onboarding_ui_tokens.dart';

class CricknovaPrePaywallFlowScreen extends StatefulWidget {
  final String userName;
  final bool allowSkipToApp;

  const CricknovaPrePaywallFlowScreen({
    super.key,
    required this.userName,
    this.allowSkipToApp = true,
  });

  @override
  State<CricknovaPrePaywallFlowScreen> createState() =>
      _CricknovaPrePaywallFlowScreenState();
}

enum _PrePaywallStep { login, comparison, snapshot, hook, trust, trial }

enum _PlanChoice { yearly, monthly }

class _CricknovaPrePaywallFlowScreenState
    extends State<CricknovaPrePaywallFlowScreen>
    with TickerProviderStateMixin {
  _PrePaywallStep _step = _PrePaywallStep.hook;

  late final AnimationController _bellPulse;
  bool _includeSnapshot = false;
  bool _forceSkipSnapshot = false;
  bool _autoOpenedPaywall = false;
  bool _trialLoading = true;
  bool _isTrialAvailable = false;
  bool _billingLaunching = false;
  String? _billingError;
  _PlanChoice _plan = _PlanChoice.yearly;
  Map<String, String> _snapshotAnswers = const <String, String>{};

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _step = _PrePaywallStep.login;
    }
    _bellPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    PremiumService.premiumNotifier.addListener(_handlePremiumChanged);
    if (user != null) {
      unawaited(_loadSnapshot());
      unawaited(_maybeAutoPaywallForExistingFreeUser());
      unawaited(_loadTrialAvailability());
    }
  }

  @override
  void dispose() {
    PremiumService.premiumNotifier.removeListener(_handlePremiumChanged);
    _bellPulse.dispose();
    super.dispose();
  }

  void _handlePremiumChanged() {
    if (!mounted) return;
    if (PremiumService.isPremiumActive) {
      _goToApp();
    }
  }

  int get _index {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    if (_includeSnapshot) {
      return switch (_step) {
        _PrePaywallStep.comparison => 0,
        _PrePaywallStep.snapshot => 1,
        _PrePaywallStep.hook => 2,
        _PrePaywallStep.trust => 3,
        _PrePaywallStep.trial => 4,
        _PrePaywallStep.login => 0,
      };
    }
    return switch (_step) {
      _PrePaywallStep.comparison => 0,
      _PrePaywallStep.snapshot => 1,
      _PrePaywallStep.hook => 2,
      _PrePaywallStep.trust => 3,
      _PrePaywallStep.trial => 4,
      _PrePaywallStep.login => 0,
    };
  }

  int get _dotCount {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 1;
    return _includeSnapshot ? 5 : 4;
  }

  void _next() {
    setState(() {
      _step = switch (_step) {
        _PrePaywallStep.login => _PrePaywallStep.login,
        _PrePaywallStep.comparison => _PrePaywallStep.trial, // Skip directly to pricing
        _PrePaywallStep.snapshot => _PrePaywallStep.trial,   // Skip to pricing
        _PrePaywallStep.hook => _PrePaywallStep.trial,       // Skip to pricing
        _PrePaywallStep.trust => _PrePaywallStep.trial,
        _PrePaywallStep.trial => _PrePaywallStep.trial,
      };
    });
    HapticFeedback.lightImpact();
  }

  void _back() {
    if (_step == _PrePaywallStep.login) {
      if (widget.allowSkipToApp) {
        _goToApp();
        return;
      }
      Navigator.of(context).maybePop();
      return;
    }
    if (_step == _PrePaywallStep.snapshot) {
      if (widget.allowSkipToApp) {
        _goToApp();
        return;
      }
      Navigator.of(context).maybePop();
      return;
    }
    if (_step == _PrePaywallStep.hook) {
      if (_includeSnapshot) {
        setState(() => _step = _PrePaywallStep.snapshot);
        HapticFeedback.selectionClick();
        return;
      }
      if (widget.allowSkipToApp) {
        _goToApp();
        return;
      }
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _step = switch (_step) {
        _PrePaywallStep.login => _PrePaywallStep.login,
        _PrePaywallStep.comparison => _PrePaywallStep.comparison,
        _PrePaywallStep.snapshot => _PrePaywallStep.comparison,
        _PrePaywallStep.hook =>
          _includeSnapshot ? _PrePaywallStep.snapshot : _PrePaywallStep.comparison,
        _PrePaywallStep.trust => _PrePaywallStep.hook,
        _PrePaywallStep.trial => _PrePaywallStep.trust,
      };
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _loadSnapshot() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Map<String, dynamic> raw = <String, dynamic>{};
    try {
      raw = await CricknovaOnboardingStore.loadAnswers(uid);
    } catch (_) {}

    final out = <String, String>{};
    for (final e in raw.entries) {
      if (e.key.trim().isEmpty) continue;
      if (e.value == null) continue;
      out[e.key] = e.value.toString();
    }

    if (!mounted) return;
    setState(() {
      _snapshotAnswers = out;
      _includeSnapshot = out.isNotEmpty && !_forceSkipSnapshot;
      if (FirebaseAuth.instance.currentUser != null) {
        _step = _PrePaywallStep.comparison;
      }
    });
  }

  Future<void> _loadTrialAvailability() async {
    final bool available = await TrialAccessService.isTrialAvailable();
    if (!mounted) return;
    setState(() {
      _isTrialAvailable = available;
      _trialLoading = false;
    });
  }

  Future<bool> _firestoreUserExists(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> _maybeAutoPaywallForExistingFreeUser() async {
    if (_autoOpenedPaywall) return;
    if (PremiumService.isPremiumActive) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final exists = await _firestoreUserExists(uid);
    if (!exists) return;
    if (!mounted) return;

    setState(() {
      _forceSkipSnapshot = true;
      _includeSnapshot = false;
      _step = _PrePaywallStep.comparison;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_autoOpenedPaywall) return;
      if (PremiumService.isPremiumActive) return;
      if (FirebaseAuth.instance.currentUser == null) return;
      _autoOpenedPaywall = true;
      // Removed _openPaywall() call to show comparison screen first
    });
  }

  Future<void> _openPaywall() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              const LoginScreen(postLoginTarget: LoginPostLoginTarget.paywall),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    await _launchYearlyCheckout();
  }

  Future<void> _launchYearlyCheckout() async {
    if (_billingLaunching) return;
    setState(() {
      _billingLaunching = true;
      _billingError = null;
    });

    try {
      final subscriptionProvider = context.read<SubscriptionProvider>();
      await subscriptionProvider.fetchProducts();
      final selectedPlan = subscriptionProvider.planForBasePlanId(
        SubscriptionProvider.oneYearPlanId,
      );
      if (selectedPlan == null) {
        throw StateError(
          subscriptionProvider.lastError ??
              'This Google Play plan is not available right now.',
        );
      }

      final launched = await subscriptionProvider.purchasePlan(selectedPlan);
      if (mounted) {
        setState(() => _billingLaunching = false);
      }
      if (!launched && mounted) {
        setState(() {
          _billingError =
              subscriptionProvider.lastError ??
              'Unable to start Google Play billing right now.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _billingLaunching = false;
        _billingError = error.toString();
      });
    }
  }

  String _billingDateLabel() {
    final billingDate = DateTime.now().add(const Duration(days: 3));
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[billingDate.month - 1]} ${billingDate.day}, ${billingDate.year}';
  }

  void _goToApp() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final resolvedName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : widget.userName.trim().isEmpty
        ? 'Player'
        : widget.userName.trim();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainNavigation(userName: resolvedName)),
      (route) => false,
    );
  }

  Color get _bg => const Color(0xFF05080C);
  Color get _teal => const Color(0xFF10B981);
  Color get _tealSoft => const Color(0xFF34D399);

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final stepKey = ValueKey<String>('step_${_step.name}');
    final loggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _BackdropGlow(teal: _teal)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _IconPillButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: _back,
                      ),
                      const Spacer(),
                      _StepDots(active: _index, count: _dotCount, teal: _teal),
                      const Spacer(),
                      if (widget.allowSkipToApp && loggedIn)
                        TextButton(
                          onPressed: _goToApp,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(
                              alpha: 0.72,
                            ),
                            textStyle: OnboardingTextStyles.uiSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Skip'),
                        )
                      else
                        const SizedBox(width: 44),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 340),
                      reverseDuration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      switchInCurve: OnboardingUiTokens.motionEaseOut,
                      switchOutCurve: OnboardingUiTokens.motionEaseIn,
                      transitionBuilder: (child, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: OnboardingUiTokens.motionEaseOut,
                          reverseCurve: OnboardingUiTokens.motionEaseIn,
                        );
                        return FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(curved),
                            child: child,
                          ),
                        );
                      },
                      child: switch (_step) {
                        _PrePaywallStep.login => _LoginGateStep(
                          key: stepKey,
                          onLogin: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(
                                  postLoginTarget: LoginPostLoginTarget.paywall,
                                ),
                              ),
                            );
                          },
                        ),
                        _PrePaywallStep.snapshot => _SnapshotStep(
                          key: stepKey,
                          answers: _snapshotAnswers,
                          onNext: _next,
                        ),
                        _PrePaywallStep.hook => _HookStep(
                          key: stepKey,
                          teal: _teal,
                          tealSoft: _tealSoft,
                          onNext: _next,
                        ),
                        _PrePaywallStep.trust => _TrustStep(
                          key: stepKey,
                          teal: _teal,
                          pulse: _bellPulse,
                          onNext: _next,
                        ),
                        _PrePaywallStep.comparison => _ComparisonStep(
                          key: stepKey,
                          teal: _teal,
                          onNext: _next,
                        ),
                        _PrePaywallStep.trial => _TrialStep(
                          key: stepKey,
                          teal: _teal,
                          selectedPlan: _plan,
                          onPlanChange: (p) => setState(() => _plan = p),
                          trialAvailable: _isTrialAvailable,
                          trialLoading: _trialLoading,
                          onStartTrial: () => _openPaywall(),
                          onViewDirectPlans: () => _openPaywall(),
                          billingError: _billingError,
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackdropGlow extends StatelessWidget {
  final Color teal;

  const _BackdropGlow({required this.teal});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -120,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: teal.withValues(alpha: 0.14),
              ),
            ),
          ),
          Positioned(
            right: -160,
            bottom: -160,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: teal.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconPillButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, color: Colors.white.withValues(alpha: 0.92)),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int active;
  final int count;
  final Color teal;

  const _StepDots({
    required this.active,
    required this.count,
    required this.teal,
  });

  @override
  Widget build(BuildContext context) {
    Widget dot(bool on) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: on ? 18 : 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: on ? teal.withValues(alpha: 0.92) : Colors.white24,
          borderRadius: BorderRadius.circular(999),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: teal.withValues(alpha: 0.28),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(count, (i) => dot(active == i)),
    );
  }
}

class _SnapshotStep extends StatelessWidget {
  final Map<String, String> answers;
  final VoidCallback onNext;

  const _SnapshotStep({super.key, required this.answers, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return CricknovaGameSnapshotView(
      answers: answers,
      onContinue: onNext,
      ctaLabel: 'Continue',
      showRateCta: false,
    );
  }
}

class _LoginGateStep extends StatelessWidget {
  final VoidCallback onLogin;

  const _LoginGateStep({super.key, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'Sign in to unlock\nyour snapshot.',
          style: OnboardingTextStyles.serif(
            color: Colors.white.withValues(alpha: 0.96),
            fontSize: 34,
            fontWeight: FontWeight.w600,
            height: 1.08,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Google login → Snapshot → Paywall',
          style: OnboardingTextStyles.uiSans(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHY SIGN IN',
                  style: OnboardingTextStyles.uiMono(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 12),
                _GateLine('Save your answers'),
                _GateLine('Personal snapshot'),
                _GateLine('Unlock AI coaching'),
                const Spacer(),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.92),
                      foregroundColor: const Color(0xFF05080C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      textStyle: OnboardingTextStyles.uiSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: onLogin,
                    child: const Text('Continue with Google'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GateLine extends StatelessWidget {
  final String text;

  const _GateLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: const Color(0xFF10B981).withValues(alpha: 0.9),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: OnboardingTextStyles.uiSans(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HookStep extends StatelessWidget {
  final Color teal;
  final Color tealSoft;
  final VoidCallback onNext;

  const _HookStep({
    super.key,
    required this.teal,
    required this.tealSoft,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'We want you to try\nCrickNova for free.',
          style: OnboardingTextStyles.serif(
            color: Colors.white.withValues(alpha: 0.96),
            fontSize: 34,
            fontWeight: FontWeight.w600,
            height: 1.08,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Upload 2 videos → AI compares → feedback',
          style: OnboardingTextStyles.uiSans(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        const Expanded(child: _CricketAiPreview()),
        const SizedBox(height: 14),
        _CheckLine(text: 'No payment due now', teal: teal),
        const SizedBox(height: 14),
        _GlowButton(text: 'Try for ₹0.00', teal: teal, onTap: onNext),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Only ₹499/year (₹1.3/day)',
            style: OnboardingTextStyles.uiSans(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrustStep extends StatelessWidget {
  final Color teal;
  final Animation<double> pulse;
  final VoidCallback onNext;

  const _TrustStep({
    super.key,
    required this.teal,
    required this.pulse,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final t = reduceMotion ? 0.0 : pulse.value;
    final scale = 0.96 + (t * 0.08);
    final glow = 0.10 + (t * 0.16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'We’ll remind you\nbefore your trial ends.',
          style: OnboardingTextStyles.serif(
            color: Colors.white.withValues(alpha: 0.96),
            fontSize: 34,
            fontWeight: FontWeight.w600,
            height: 1.08,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'You stay in control.',
          style: OnboardingTextStyles.uiSans(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(color: Colors.white12),
                      boxShadow: [
                        BoxShadow(
                          color: teal.withValues(alpha: glow),
                          blurRadius: 38,
                          spreadRadius: 1.0,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      size: 54,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 18,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: teal.withValues(alpha: 0.95),
                        boxShadow: [
                          BoxShadow(
                            color: teal.withValues(alpha: 0.50),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _CheckLine(text: 'No payment due now', teal: teal),
        const SizedBox(height: 8),
        _CheckLine(text: 'Cancel anytime', teal: teal),
        const SizedBox(height: 14),
        _GlowButton(text: 'Continue for FREE', teal: teal, onTap: onNext),
      ],
    );
  }
}

class _TrialStep extends StatelessWidget {
  final Color teal;
  final _PlanChoice selectedPlan;
  final ValueChanged<_PlanChoice> onPlanChange;
  final VoidCallback onStartTrial;
  final VoidCallback onViewDirectPlans;
  final bool trialAvailable;
  final bool trialLoading;
  final String? billingError;

  const _TrialStep({
    super.key,
    required this.teal,
    required this.selectedPlan,
    required this.onPlanChange,
    required this.onStartTrial,
    required this.onViewDirectPlans,
    required this.trialAvailable,
    required this.trialLoading,
    required this.billingError,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIndia = PricingLocationService.currentRegion == PricingRegion.india;
    final String priceLabel = isIndia ? '₹499 /yr' : '\$69.99 /yr';
    final String footerCopy = isIndia
        ? 'Just ₹499.00 per year (approx ₹41.50/mo)'
        : 'Just \$69.99 per year (approx \$5.83/mo)';
    final DateTime bd = DateTime.now().add(const Duration(days: 3));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String billingLabel = isIndia
        ? 'Your yearly access begins at ₹499 on ${months[bd.month - 1]} ${bd.day}.'
        : 'Your yearly access begins at \$69.99 on ${months[bd.month - 1]} ${bd.day}.';

    if (trialLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.black));
    }

    return Container(
      color: const Color(0xFF05080C), // Dark theme
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header row ──
              Row(
                children: [
                  // Back arrow placeholder (navigation handled by parent)
                  const SizedBox(width: 44),
                  const Spacer(),
                  _HeaderIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Headline ──
              Text(
                'Start your 3-day FREE\ntrial to continue.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cormorantGaramond(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 24),
              // ── 3-Day Timeline ──
              _CalAITimeline(billingLabel: billingLabel),
              const SizedBox(height: 24),
              // ── Single Yearly Plan Card ──
              _CalAIPlanCard(priceLabel: priceLabel),
              const SizedBox(height: 18),
              // ✓ No Payment Due Now
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_rounded, color: Color(0xFFFFD700), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'No Payment Due Now',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // ── CTA Button ──
              SizedBox(
                width: double.infinity,
                height: 62,
                child: ElevatedButton(
                  onPressed: onStartTrial,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700), // Gold button
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Start My 3-Day Free Trial'),
                ),
              ),
              if (billingError != null) ...[
                const SizedBox(height: 8),
                Text(
                  billingError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFD32F2F),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                footerCopy,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cal AI 3-day vertical timeline
// ─────────────────────────────────────────────────────────────────────────────
class _CalAITimeline extends StatelessWidget {
  final String billingLabel;
  const _CalAITimeline({required this.billingLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CalAITimelineItem(
          iconData: Icons.lock_open_rounded,
          iconBg: const Color(0xFFF59E0B),
          iconColor: Colors.white,
          title: 'Today',
          subtitle: 'Unlock all AI Cricket features (Speed, Swing, and Technique analysis).',
          isLast: false,
        ),
        _CalAITimelineItem(
          iconData: Icons.notifications_active_rounded,
          iconBg: const Color(0xFFF59E0B),
          iconColor: Colors.white,
          title: 'In 2 Days – Reminder',
          subtitle: "We'll notify you before your trial ends.",
          isLast: false,
        ),
        _CalAITimelineItem(
          iconData: Icons.workspace_premium_rounded,
          iconBg: Colors.black,
          iconColor: Colors.white,
          title: 'In 3 Days – Billing Starts',
          subtitle: billingLabel,
          isLast: true,
        ),
      ],
    );
  }
}

class _CalAITimelineItem extends StatelessWidget {
  final IconData iconData;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isLast;

  const _CalAITimelineItem({
    required this.iconData,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
              child: Icon(iconData, color: iconColor, size: 18),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: const Color(0xFFD1D5DB),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF6B7280),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cal AI single yearly plan card with "3 DAYS FREE" badge
// ─────────────────────────────────────────────────────────────────────────────
class _CalAIPlanCard extends StatelessWidget {
  final String priceLabel;
  const _CalAIPlanCard({required this.priceLabel});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Yearly Access',
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                priceLabel,
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        // "3 DAYS FREE" badge
        Positioned(
          top: -12,
          right: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '3 DAYS FREE',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}



class _LockedTrialCard extends StatelessWidget {
  final Color teal;
  final VoidCallback onViewDirectPlans;

  const _LockedTrialCard({required this.teal, required this.onViewDirectPlans});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: teal.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Trial Expired. Upgrade to Premium to continue your training.',
            style: OnboardingTextStyles.serif(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              height: 1.04,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'This device has already used the free trial. Choose a direct plan instead.',
            style: OnboardingTextStyles.uiSans(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          _CheckLine(text: '₹499/year premium offer', teal: teal),
          const Spacer(),
          _GlowButton(
            text: 'View Premium Offer',
            teal: teal,
            onTap: onViewDirectPlans,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, color: const Color(0xFFB4B4B4), size: 22),
      ),
    );
  }
}

class _NoPaymentLine extends StatelessWidget {
  const _NoPaymentLine();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, color: Colors.black, size: 18),
          const SizedBox(width: 8),
          Text(
            'No Payment Due Now',
            style: GoogleFonts.inter(
              color: Colors.black,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _YearlyTrialCard extends StatelessWidget {
  final String priceLabel;
  final String billingDate;

  const _YearlyTrialCard({
    required this.priceLabel,
    required this.billingDate,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFD700), width: 1.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yearly',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      priceLabel,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Billed Annually',
                      style: GoogleFonts.inter(
                        color: const Color(0xCCFFFFFF),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD700),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1.6),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.black, size: 18),
              ),
            ],
          ),
        ),
        Positioned(
          top: -11,
          left: 28,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFFD700), width: 1),
            ),
            child: Text(
              '3 DAYS FREE',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final Color teal;
  final String billingDateLabel;

  const _Timeline({
    required this.teal,
    required this.billingDateLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget item({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool last,
      required Color iconColor,
      required Color iconBg,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBg,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 18,
                ),
              ),
              if (!last)
                Container(
                  width: 2,
                  height: 30,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        teal.withValues(alpha: 0.95),
                        const Color(0xFFB3B3B3),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF71717A),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          item(
            icon: Icons.lock_outline_rounded,
            title: 'Today',
            subtitle:
                'Unlock all CrickNova AI features like Bowling Speed, Swing analysis, and Batting posture tracking.',
            last: false,
            iconColor: Colors.white,
            iconBg: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 18),
          item(
            icon: Icons.notifications_active_rounded,
            title: 'In 2 Days – Reminder',
            subtitle: 'We\'ll send you a reminder that your trial is ending soon.',
            last: false,
            iconColor: Colors.white,
            iconBg: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 18),
          item(
            icon: Icons.workspace_premium_rounded,
            title: 'In 3 Days – Billing Starts',
            subtitle:
                'You\'ll be charged on $billingDateLabel unless you cancel anytime before.',
            last: true,
            iconColor: Colors.white,
            iconBg: Colors.black,
          ),
        ],
      ),
    );
  }
}

class _PlanChooser extends StatelessWidget {
  final Color teal;
  final _PlanChoice selected;
  final ValueChanged<_PlanChoice> onChange;
  final String yearlyPrice;
  final String monthlyPrice;

  const _PlanChooser({
    required this.teal,
    required this.selected,
    required this.onChange,
    required this.yearlyPrice,
    required this.monthlyPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlanCard(
            teal: teal,
            title: 'Monthly',
            subtitle: monthlyPrice,
            badge: null,
            highlighted: false,
            selected: selected == _PlanChoice.monthly,
            onTap: () => onChange(_PlanChoice.monthly),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PlanCard(
            teal: teal,
            title: 'Yearly',
            subtitle: yearlyPrice,
            badge: '3 DAYS FREE',
            highlighted: true,
            selected: selected == _PlanChoice.yearly,
            onTap: () => onChange(_PlanChoice.yearly),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Color teal;
  final String title;
  final String? subtitle;
  final String? badge;
  final bool highlighted;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.teal,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.highlighted,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Colors.white;
    final border = selected ? Colors.black : const Color(0xFFC7C7C7);
    final shadow = selected
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ]
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: border),
            boxShadow: shadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          _Badge(text: badge!, teal: teal),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.black : const Color(0xFFB7B7B7),
                    width: 2,
                  ),
                  color: selected ? Colors.black : Colors.transparent,
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color teal;

  const _Badge({required this.text, required this.teal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black,
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  final String text;
  final Color teal;

  const _CheckLine({required this.text, required this.teal});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 13,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: GoogleFonts.inter(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _GlowButton extends StatelessWidget {
  final String text;
  final Color teal;
  final VoidCallback onTap;

  const _GlowButton({
    required this.text,
    required this.teal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
        onPressed: onTap,
        child: Text(text),
      ),
    );
  }
}

class _CricketAiPreview extends StatelessWidget {
  const _CricketAiPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TinyChip(icon: Icons.upload_rounded, text: 'Upload'),
              const SizedBox(width: 10),
              const _TinyChip(icon: Icons.video_file_rounded, text: '2 videos'),
              const SizedBox(width: 10),
              const _TinyChip(
                icon: Icons.auto_awesome_rounded,
                text: 'Compare',
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: const Color(0xFF10B981).withValues(alpha: 0.10),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  'AI Preview',
                  style: OnboardingTextStyles.uiMono(
                    color: const Color(0xFF34D399).withValues(alpha: 0.95),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _VideoTile(
                  label: 'Video 1',
                  icon: Icons.sports_cricket_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _VideoTile(
                  label: 'Video 2',
                  icon: Icons.sports_cricket_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.025),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _MiniOutputLine(label: 'Mistake', value: 'Late reaction'),
                SizedBox(height: 8),
                _MiniOutputLine(label: 'Fix', value: 'Improve footwork'),
                SizedBox(height: 8),
                _MiniOutputLine(label: 'Result', value: 'Better timing'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TinyChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.75)),
          const SizedBox(width: 6),
          Text(
            text,
            style: OnboardingTextStyles.uiSans(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final String label;
  final IconData icon;

  const _VideoTile({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 34,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 10,
            child: Text(
              label,
              style: OnboardingTextStyles.uiSans(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white12),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniOutputLine extends StatelessWidget {
  final String label;
  final String value;

  const _MiniOutputLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            '$label:',
            style: OnboardingTextStyles.uiMono(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: OnboardingTextStyles.uiSans(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComparisonStep extends StatelessWidget {
  final Color teal;
  final VoidCallback onNext;

  const _ComparisonStep({
    super.key,
    required this.teal,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIndia = PricingLocationService.currentRegion == PricingRegion.india;
    
    return Column(
      children: [
        const SizedBox(height: 10),
        // Very Big Coffee Visual
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 25,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Image.network(
              isIndia 
                ? 'https://images.unsplash.com/photo-1509042239860-f550ce710b93?q=80&w=800&h=800&fit=crop'
                : 'https://images.unsplash.com/photo-1595769816263-9b910be24d5f?q=80&w=800&h=800&fit=crop',
              fit: BoxFit.cover,
              width: double.infinity,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  child: child,
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Marketing Text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Text(
                isIndia 
                  ? 'Costs less than a\ncup of coffee (just ₹99).'
                  : 'Costs less than a\nmovie ticket (\$29.99).',
                textAlign: TextAlign.center,
                style: OnboardingTextStyles.uiSans(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: OnboardingTextStyles.uiSans(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'Unlock elite-level cricket analysis for 30 days to '),
                    TextSpan(
                      text: 'boost your game.',
                      style: OnboardingTextStyles.uiSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ).copyWith(
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    TextSpan(
                      text: isIndia 
                        ? ' Invest in your skills for the price of one single coffee.'
                        : ' Invest in your skills for the price of one movie ticket.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _GlowButton(
          text: isIndia ? "Upgrade My Game for ₹99" : "Upgrade My Game for \$29.99",
          teal: teal,
          onTap: onNext,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            "35-day roadmap included. Cancel anytime.",
            style: OnboardingTextStyles.uiSans(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final Color color;
  final String imageSource; // URL or Path
  final String title;
  final String subtitle;
  final bool showCNLogo;

  const _ComparisonCard({
    required this.color,
    required this.imageSource,
    required this.title,
    required this.subtitle,
    this.showCNLogo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large Image Container
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SizedBox(
              width: double.infinity,
              height: 130,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: imageSource.startsWith('http') 
                      ? Image.network(imageSource, fit: BoxFit.cover)
                      : Image.asset(imageSource, fit: BoxFit.cover),
                  ),
                  if (showCNLogo)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981), // Emerald/CN Green
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)
                          ],
                        ),
                        child: Text(
                          'CN',
                          style: OnboardingTextStyles.uiSans(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                  // Subtle gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.1),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: OnboardingTextStyles.uiSans(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: OnboardingTextStyles.uiSans(
                    color: Colors.black.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
