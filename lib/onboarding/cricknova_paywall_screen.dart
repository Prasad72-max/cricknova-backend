import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../navigation/main_navigation.dart';
import '../profile/legal_info_screen.dart';
import '../services/premium_service.dart';
import '../services/pricing_location_service.dart';
import '../services/subscription_provider.dart';
import '../services/trial_access_service.dart';

class CricknovaPaywallScreen extends StatefulWidget {
  final String userName;

  const CricknovaPaywallScreen({super.key, required this.userName});

  @override
  State<CricknovaPaywallScreen> createState() => _CricknovaPaywallScreenState();
}

enum _PlanChoice { monthly, yearly }

class _CricknovaPaywallScreenState extends State<CricknovaPaywallScreen>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF080808);
  static const Color _gold = Color(0xFFFFD700);
  static const String _yearlyProductId = 'cricknova_premium';

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _purchasePending = false;
  bool _showConfetti = false;
  String? _billingError;
  int _stepIndex = 0;
  _PlanChoice _lockedPlan = _PlanChoice.yearly;
  bool _trialLoading = true;
  bool _isTrialAvailable = false;

  final PageController _pageController = PageController();

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _purchaseSub = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _purchasePending = false;
          _billingError = 'Purchase stream error: $error';
        });
      },
    );
    unawaited(_loadTrialAvailability());
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _pageController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadTrialAvailability() async {
    final bool available = await TrialAccessService.isTrialAvailable();
    if (!mounted) return;
    setState(() {
      _isTrialAvailable = available;
      _trialLoading = false;
    });
  }

  Future<void> _startLockedPurchase() async {
    if (_purchasePending) return;

    setState(() {
      _purchasePending = true;
      _billingError = null;
    });

    try {
      final subscriptionProvider = context.read<SubscriptionProvider>();
      await subscriptionProvider.fetchProducts();
      final bool wantsYearly = _lockedPlan == _PlanChoice.yearly;
      // Yearly always gets free trial offer; monthly is always direct payment
      final bool allowTrial = wantsYearly && _isTrialAvailable;
      final bool requireTrial = false; // never hard-require – fall back gracefully
      final String basePlanId = wantsYearly
          ? SubscriptionProvider.oneYearPlanId
          : SubscriptionProvider.monthlyPlanId;

      var selectedPlan = subscriptionProvider.planForBasePlanId(
        basePlanId,
        allowFreeTrial: allowTrial,
        requireFreeTrial: requireTrial,
      );

      // Fallback: if trial offer not found for yearly, use direct paid plan
      if (selectedPlan == null) {
        selectedPlan = subscriptionProvider.planForBasePlanId(
          basePlanId,
          allowFreeTrial: false,
          requireFreeTrial: false,
        );
      }

      if (selectedPlan == null) {
        throw StateError(
          subscriptionProvider.lastError ??
              'This subscription option is not available right now.',
        );
      }

      final launched = await subscriptionProvider.purchasePlan(
        selectedPlan,
        allowFreeTrial: allowTrial && selectedPlan.hasFreeTrial,
        requireFreeTrial: false,
      );
      if (!launched && mounted) {
        setState(() {
          _purchasePending = false;
          _billingError =
              subscriptionProvider.lastError ??
              'Unable to start Google Play billing right now.';
        });
      }
      // Fallback in case billing sheet is closed without callback
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _purchasePending) {
          setState(() {
            _purchasePending = false;
          });
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _purchasePending = false;
        _billingError = error.toString();
      });
    }
  }

  Future<void> _enterApp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'name': widget.userName,
            'source': 'google_auth',
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigation(userName: widget.userName),
      ),
      (_) => false,
    );
  }

  void _openLegal(LegalDocType docType) {
    final document = switch (docType) {
      LegalDocType.privacy => LegalDocument.privacy(),
      LegalDocType.terms => LegalDocument.terms(),
      LegalDocType.about => LegalDocument.about(),
    };
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalInfoScreen(document: document)),
    );
  }

  Future<void> _goToStep(int index) async {
    // No-op: single-step paywall
  }

  Widget _buildTopBar() {
    return Row(
      children: <Widget>[
        Text(
          'CrickNova AI',
          style: GoogleFonts.inter(
            color: const Color(0xCCFFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: _enterApp,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  String _yearlyPriceLabel(PricingRegion region) {
    return region == PricingRegion.india
        ? 'Just ₹499.00 per year (₹41/mo)'
        : 'Just \$59.99 per year (\$5.00/mo)';
  }

  String _freeTrialButtonLabel(PricingRegion region) {
    return region == PricingRegion.india ? 'Try for ₹0.00' : 'Try for \$0.00';
  }

  Widget _buildHookStep(PricingRegion region) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 18),
        Text(
          'One Small Habit.\nOne Giant Leap for Your Game.',
          style: GoogleFonts.cormorantGaramond(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w700,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 18),
        const Expanded(child: _ComparisonTable()),
        const SizedBox(height: 16),
        const _NoPaymentRow(),
        const SizedBox(height: 14),
        _FlowActionButton(
          label: 'Continue to My Game',
          onTap: () => _goToStep(1),
        ),
      ],
    );
  }

  Widget _buildMockupStep(PricingRegion region) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 18),
        Text(
          'We want you to try\nCrickNova AI for free.',
          style: GoogleFonts.cormorantGaramond(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w700,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 18),
        const Expanded(child: _DeviceMockupCard()),
        const SizedBox(height: 16),
        const _NoPaymentRow(),
        const SizedBox(height: 14),
        _FlowActionButton(
          label: _freeTrialButtonLabel(region),
          onTap: () => _goToStep(2),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            _yearlyPriceLabel(region),
            style: GoogleFonts.inter(
              color: const Color(0x99FFFFFF),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrustStep(PricingRegion region) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 18),
        Text(
          'We’ll send you\na reminder before your\nfree trial ends.',
          style: GoogleFonts.cormorantGaramond(
            color: Colors.white,
            fontSize: 46,
            fontWeight: FontWeight.w700,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 24),
        const Expanded(child: Center(child: _TrustBellVisual())),
        const _NoPaymentRow(),
        const SizedBox(height: 14),
        _FlowActionButton(
          label: 'Continue for FREE',
          onTap: () => _goToStep(3),
        ),
      ],
    );
  }

  Widget _buildCommitmentStep(PricingRegion region) {
    if (_trialLoading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }

    final bool isIndia = region == PricingRegion.india;
    final bool selectedYearly = _lockedPlan == _PlanChoice.yearly;
    final bool isYearlyTrial = selectedYearly && _isTrialAvailable;

    final String headerTitle = isYearlyTrial
        ? 'Start your 3-day\nFREE trial to\ncontinue.'
        : 'Unlock Premium\nAccess to\ncontinue.';

    final String actionLabel = isYearlyTrial
        ? 'Start My 3-Day Free Trial'
        : selectedYearly
            ? 'Subscribe – ₹499/year'
            : 'Unlock Monthly Access';

    final String footerLabel = isYearlyTrial
        ? (isIndia
            ? '3 days free, then ₹499/year (₹41/mo)'
            : '3 days free, then \$59.99/year (\$5.00/mo)')
        : selectedYearly
            ? (isIndia
                ? 'Billed today at ₹499/year (₹41/mo)'
                : 'Billed today at \$59.99/year (\$5.00/mo)')
            : (isIndia ? 'Billed today at ₹99/month' : 'Billed today at \$8.99/mo');

    final DateTime bd = DateTime.now().add(const Duration(days: 3));
    const List<String> months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String billingDate = '${months[bd.month - 1]} ${bd.day}, ${bd.year}';
    final String billingLabel =
        'You\'ll be charged on $billingDate unless you cancel anytime before.';

    final String priceLabel = selectedYearly
        ? (isIndia ? '₹499/year' : '\$59.99/year')
        : (isIndia ? '₹99/month' : '\$8.99/mo');

    final double screenHeight = MediaQuery.of(context).size.height;
    final double scale = (screenHeight / 900.0).clamp(0.68, 1.0);

    final double headerFontSize = 42 * scale;
    final double gapHeaderToTimeline = 24 * scale;
    final double gapAfterTimeline = 28 * scale;
    final double gapAfterCard1 = 20 * scale;
    final double gapAfterCard2 = 28 * scale;
    final double gapAfterNoPayment = 24 * scale;
    final double ctaHeight = 64 * scale;
    final double ctaFontSize = 18 * scale;
    final double gapAfterCta = 24 * scale;
    final double footerFontSize = 15 * scale;
    final double protectionFontSize = 13 * scale;
    final double gapFooterToProtection = 12 * scale;
    final double bottomGap = 36 * scale;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Big header (made smaller and responsive)
          Text(
            headerTitle,
            style: GoogleFonts.cormorantGaramond(
              color: Colors.white,
              fontSize: headerFontSize,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          SizedBox(height: gapHeaderToTimeline),
          // Timeline (only show for yearly plan with trial)
          if (selectedYearly && _isTrialAvailable)
            _DarkTimeline(
              billingLabel: billingLabel,
              isYearly: selectedYearly,
              priceLabel: priceLabel,
            ),
          if (selectedYearly && _isTrialAvailable)
            SizedBox(height: gapAfterTimeline)
          else
            SizedBox(height: 16 * scale),
          // Monthly card
          _PaywallPlanCard(
            title: 'Monthly',
            price: isIndia ? '₹99/month' : '\$8.99/mo',
            selected: _lockedPlan == _PlanChoice.monthly,
            showTrial: false,
            onTap: () => setState(() => _lockedPlan = _PlanChoice.monthly),
          ),
          SizedBox(height: gapAfterCard1),
          // Yearly card
          _PaywallPlanCard(
            title: 'Yearly',
            price: isIndia ? '₹499/year' : '\$59.99/year',
            selected: _lockedPlan == _PlanChoice.yearly,
            showTrial: _isTrialAvailable,
            onTap: () => setState(() => _lockedPlan = _PlanChoice.yearly),
          ),
          // Extra spacing for yearly plan to make screen bigger
          SizedBox(height: gapAfterCard2),
          // No Payment Due Now
          if (isYearlyTrial) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.check_circle_rounded,
                    color: const Color(0xFFFFD700), size: 20 * scale),
                const SizedBox(width: 8),
                Text(
                  'No Payment Due Now',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 17 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: gapAfterNoPayment),
          ] else
            const SizedBox(height: 4),
          // CTA Button
          SizedBox(
            width: double.infinity,
            height: ctaHeight,
            child: ElevatedButton(
              onPressed: _purchasePending ? null : _startLockedPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: GoogleFonts.inter(
                  fontSize: ctaFontSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: _purchasePending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.black,
                      ),
                    )
                  : Text(actionLabel),
            ),
          ),
          // Extra spacing after button for yearly plan
          SizedBox(height: gapAfterCta),
          if (_billingError != null) ...[
            Text(
              _billingError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFFD32F2F),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Center(
            child: Text(
              footerLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFFAAAAAA),
                fontSize: footerFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: gapFooterToProtection),
          Center(
            child: Text(
              'Device-based trial protection is active.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFF777777),
                fontSize: protectionFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Extra bottom spacing for yearly plan
          SizedBox(height: bottomGap),
        ],
      );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PricingRegion>(
      valueListenable: PricingLocationService.regionNotifier,
      builder: (BuildContext context, PricingRegion region, _) {
        final double screenHeight = MediaQuery.of(context).size.height;
        final double scale = (screenHeight / 900.0).clamp(0.68, 1.0);
        final double outerTopGap = 12 * scale;
        final double outerBottomPadding = 18 * scale;
        final double outerHorizontalPadding = 18 * scale;
        final double spacingBelowTopBar = 12 * scale;

        return Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: <Widget>[
              const Positioned.fill(child: _PremiumPaywallBackdrop()),
              if (_showConfetti)
                const Positioned.fill(
                  child: IgnorePointer(child: _ConfettiBurst()),
                ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    outerHorizontalPadding,
                    outerTopGap,
                    outerHorizontalPadding,
                    outerBottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildTopBar(),
                      SizedBox(height: spacingBelowTopBar),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: _buildCommitmentStep(region),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != _yearlyProductId) {
        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (mounted) {
            setState(() {
              _purchasePending = true;
              _billingError = null;
            });
          }
          break;
        case PurchaseStatus.error:
          if (mounted) {
            setState(() {
              _purchasePending = false;
              _billingError = purchase.error?.message ?? 'Payment failed.';
            });
          }
          break;
        case PurchaseStatus.canceled:
          if (mounted) {
            setState(() {
              _purchasePending = false;
              _billingError = 'Purchase canceled.';
            });
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _unlockPremiumAndEnterApp();
          if (mounted) {
            setState(() => _purchasePending = false);
          }
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    }
  }

  Future<void> _unlockPremiumAndEnterApp() async {
    try {
      if (_lockedPlan == _PlanChoice.yearly) {
        await TrialAccessService.markTrialUsed(
          userId: FirebaseAuth.instance.currentUser?.uid,
        );
      }
    } catch (_) {
      // Trial protection is best-effort; subscription activation is handled by
      // SubscriptionProvider after Google Play purchase verification.
    }

    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await PremiumService.syncFromFirestore(user.uid);
    }
    if (!mounted) return;
    setState(() => _showConfetti = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await _enterApp();
  }
}

class _PremiumPaywallBackdrop extends StatelessWidget {
  const _PremiumPaywallBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF0A0A0A), Color(0xFF050505)],
        ),
      ),
      child: const Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            left: -60,
            child: _GlowOrb(color: Color(0x2EFFD700), size: 230),
          ),
          Positioned(
            top: 170,
            right: -80,
            child: _GlowOrb(color: Color(0x22FFFFFF), size: 180),
          ),
          Positioned(
            bottom: -120,
            left: 20,
            child: _GlowOrb(color: Color(0x1FFFCC66), size: 260),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color,
            blurRadius: size * 0.5,
            spreadRadius: size * 0.1,
          ),
        ],
      ),
    );
  }
}

class _NoPaymentRow extends StatelessWidget {
  const _NoPaymentRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.check_rounded, color: Color(0xFFFFD700), size: 20),
        const SizedBox(width: 8),
        Text(
          'No Payment Due Now',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FlowActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FlowActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFD700),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _DeviceMockupCard extends StatefulWidget {
  const _DeviceMockupCard();

  @override
  State<_DeviceMockupCard> createState() => _DeviceMockupCardState();
}

class _DeviceMockupCardState extends State<_DeviceMockupCard>
    with TickerProviderStateMixin {
  late AnimationController _scanController;
  late AnimationController _textController;
  late AnimationController _pulseController;
  int _messageIndex = 0;

  final List<Map<String, dynamic>> _messages = [
    {'text': 'Analyzing Release Angle...', 'color': Colors.white},
    {
      'text': 'Mistake Detected: Excessive Side Bend',
      'color': const Color(0xFFFF5252),
    },
    {
      'text': 'Recommended Drill: Static Wall Lean',
      'color': const Color(0xFFFFD700),
    },
  ];

  @override
  void initState() {
    super.initState();

    // Scanner animation
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Text cycling animation
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _cycleMessages();
  }

  void _cycleMessages() async {
    while (mounted) {
      await _textController.forward();
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) break;
      await _textController.reverse();
      if (mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _messages.length;
        });
      }
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 0.58,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white24, width: 1.2),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Background Image
                Image.asset(
                  'assets/images/cover_drive_v2.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[900],
                      child: const Center(
                        child: Text(
                          'Cover Drive Image\n(assets/images/cover_drive_v2.jpg)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    );
                  },
                ),

                // Dark overlay for better text readability
                Container(color: Colors.black.withValues(alpha: 0.3)),

                // Top Left: Glassmorphism badge '128.4 KMPH'
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyan.withValues(alpha: 0.2),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.speed,
                          color: Colors.cyanAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '128.4 KMPH',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Center: Animated text overlay
                Positioned(
                  bottom: 74, // Moved up to avoid bottom camera icon
                  left: 12,
                  right: 12,
                  child: AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _textController.value,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - _textController.value)),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final bool isPulsing = _messageIndex == 0;
                          final double scale = isPulsing
                              ? 1.0 + (_pulseController.value * 0.05)
                              : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: Text(
                              _messages[_messageIndex]['text'],
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: _messages[_messageIndex]['color'],
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // Scanning line animation
                AnimatedBuilder(
                  animation: _scanController,
                  builder: (context, child) {
                    return Positioned(
                      top:
                          _scanController.value *
                          420, // approximate height travel for full box
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withValues(alpha: 0.6),
                              blurRadius: 12,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Camera icon at the bottom
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
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

class _TrustBellVisual extends StatelessWidget {
  const _TrustBellVisual();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: 184,
          height: 184,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            size: 96,
            color: Color(0xFFE7EDF0),
          ),
        ),
        Positioned(
          right: 8,
          top: 20,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFD92222),
            ),
            alignment: Alignment.center,
            child: Text(
              '1',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dark Theme 3-Day Timeline
// ─────────────────────────────────────────────────────────────────────────────
class _DarkTimeline extends StatelessWidget {
  final String billingLabel;
  final bool isYearly;
  final String priceLabel;

  const _DarkTimeline({
    required this.billingLabel,
    required this.isYearly,
    required this.priceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double scale = (screenHeight / 900.0).clamp(0.68, 1.0);
    final double itemSpacing = 20 * scale;
    final double iconBoxSize = 48 * scale;
    final double lineLeft = (iconBoxSize / 2) - 1;

    return Stack(
      children: [
        Positioned(
          left: lineLeft,
          top: 18,
          bottom: 18,
          child: Container(
            width: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFD700),
                  Color(0xFFFFD700),
                  Color(0xFF2A2A2A),
                ],
              ),
            ),
          ),
        ),
        Column(
          children: [
            _DarkTimelineItem(
              iconData: Icons.lock_open_rounded,
              iconBg: const Color(0xFFFFD700),
              iconColor: Colors.white,
              title: 'Today',
              subtitle: 'Unlock all premium features like AI batting analysis, bowling coach, and more.',
            ),
            SizedBox(height: itemSpacing),
            _DarkTimelineItem(
              iconData: Icons.notifications_active_rounded,
              iconBg: const Color(0xFFFFD700),
              iconColor: Colors.white,
              title: 'In 2 Days – Reminder',
              subtitle: 'We\'ll send you a reminder that your trial is ending soon.',
            ),
            SizedBox(height: itemSpacing),
            _DarkTimelineItem(
              iconData: Icons.workspace_premium_rounded,
              iconBg: Colors.black,
              iconColor: Colors.white,
              title: 'In 3 Days – Billing Starts',
              subtitle: billingLabel,
              border: Border.all(color: Colors.white24),
            ),
          ],
        ),
      ],
    );
  }
}

class _DarkTimelineItem extends StatelessWidget {
  final IconData iconData;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final BoxBorder? border;

  const _DarkTimelineItem({
    required this.iconData,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double scale = (screenHeight / 900.0).clamp(0.68, 1.0);
    final double iconBoxSize = 48 * scale;
    final double iconSize = 24 * scale;
    final double titleFontSize = 20 * scale;
    final double subtitleFontSize = 15 * scale;
    final double titleToSubtitleGap = 4 * scale;
    final double horizontalGap = 16 * scale;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconBg,
            border: border,
          ),
          child: Icon(iconData, color: iconColor, size: iconSize),
        ),
        SizedBox(width: horizontalGap),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: titleToSubtitleGap),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFAAAAAA),
                    fontSize: subtitleFontSize,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Dark Theme Single Yearly Plan Card
// ─────────────────────────────────────────────────────────────────────────────
class _DarkPlanCard extends StatelessWidget {
  final String priceLabel;
  const _DarkPlanCard({required this.priceLabel});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD700), width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yearly',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceLabel,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFD700),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.black,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFFD700), width: 1),
            ),
            child: Text(
              '3 DAYS FREE',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalTimeline extends StatelessWidget {
  final String billingLabel;
  const _CalTimeline({required this.billingLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _CalTimelineItem(
          iconData: Icons.lock_open_rounded,
          iconBg: const Color(0xFFF59E0B),
          iconColor: Colors.white,
          title: 'Today',
          subtitle:
              'Unlock all AI Cricket features (Speed, Swing, and Technique analysis).',
          isLast: false,
        ),
        _CalTimelineItem(
          iconData: Icons.notifications_active_rounded,
          iconBg: const Color(0xFFF59E0B),
          iconColor: Colors.white,
          title: 'In 2 Days – Reminder',
          subtitle: 'We\'ll notify you before your trial ends.',
          isLast: false,
        ),
        _CalTimelineItem(
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

class _CalTimelineItem extends StatelessWidget {
  final IconData iconData;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isLast;

  const _CalTimelineItem({
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
      children: <Widget>[
        Column(
          children: <Widget>[
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
              children: <Widget>[
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
// ─────────────────────────────────────────────────────────────────────────────
// Plan card for the trial-locked/upgrade state
// ─────────────────────────────────────────────────────────────────────────────
class _LockedPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String billingText;
  final bool highlighted;
  final bool isBestValue;
  final VoidCallback onTap;

  const _LockedPlanCard({
    required this.title,
    required this.price,
    required this.billingText,
    required this.highlighted,
    this.isBestValue = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: highlighted ? Colors.black : const Color(0xFFD1D5DB),
                width: highlighted ? 2 : 1.2,
              ),
              boxShadow: highlighted
                  ? <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: highlighted ? Colors.black : Colors.transparent,
                        border: Border.all(
                          color: highlighted
                              ? Colors.black
                              : const Color(0xFFD1D5DB),
                          width: 1.5,
                        ),
                      ),
                      child: highlighted
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 14,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  price,
                  style: GoogleFonts.inter(
                    color: Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  billingText,
                  style: GoogleFonts.inter(
                    color: Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isBestValue)
          Positioned(
            top: -10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'BEST VALUE',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 9,
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

// ─────────────────────────────────────────────────────────────────────────────
// Cal AI-style single yearly plan card
// ─────────────────────────────────────────────────────────────────────────────
class _CalPlanCard extends StatelessWidget {
  final String priceLabel;
  const _CalPlanCard({required this.priceLabel});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 1.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
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

class _TrialButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool pending;

  const _TrialButton({required this.onTap, required this.pending});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: pending ? null : onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFFD700), Color(0xFFFFA500)],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _CricknovaPaywallScreenState._gold.withValues(alpha: 0.36),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: pending
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.black,
                ),
              )
            : Text(
                'Start My 3-Day Free Trial',
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _PaywallTimeline extends StatelessWidget {
  final String todayLabel;
  final String billingLabel;

  const _PaywallTimeline({
    required this.todayLabel,
    required this.billingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: <Widget>[
          _TimelinePoint(
            icon: Icons.lock_open_rounded,
            title: 'Today',
            subtitle: todayLabel,
            isLast: false,
          ),
          SizedBox(height: 8),
          _TimelinePoint(
            icon: Icons.notifications_active_rounded,
            title: 'Day 2',
            subtitle: 'Reminder: your trial is ending soon.',
            isLast: false,
          ),
          SizedBox(height: 8),
          _TimelinePoint(
            icon: Icons.credit_card_rounded,
            title: 'Day 3',
            subtitle: billingLabel,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _TimelinePoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  const _TimelinePoint({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x1AFFD700),
                border: Border.all(color: const Color(0x66FFD700)),
              ),
              child: Icon(icon, color: const Color(0xFFFFD700), size: 18),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: Colors.white.withValues(alpha: 0.15),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: const Color(0xB3FFFFFF),
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

class _YearlyPricingCard extends StatelessWidget {
  final String priceLabel;
  final String monthlyEquivalentLabel;

  const _YearlyPricingCard({
    required this.priceLabel,
    required this.monthlyEquivalentLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x66FFD700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '1 Year Elite Membership',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            priceLabel,
            style: GoogleFonts.cormorantGaramond(
              color: const Color(0xFFFFD700),
              fontSize: 40,
              fontWeight: FontWeight.w700,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            monthlyEquivalentLabel,
            style: GoogleFonts.inter(
              color: const Color(0xCCFFFFFF),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xE6FFFFFF),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xE6FFFFFF),
          ),
        ),
      ),
    );
  }
}

class _DirectPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String billingText;
  final bool highlighted;
  final bool recommended;
  final VoidCallback onTap;

  const _DirectPlanCard({
    required this.title,
    required this.price,
    required this.billingText,
    required this.highlighted,
    required this.recommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = highlighted
        ? const Color(0xFFFFD700)
        : Colors.white.withValues(alpha: 0.24);
    final double borderWidth = highlighted ? 2.4 : 1.4;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
                if (highlighted)
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.18),
                    blurRadius: 24,
                    spreadRadius: 0.5,
                  ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        price,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        billingText,
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
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: highlighted
                        ? const Color(0xFFFFD700)
                        : Colors.white10,
                    border: Border.all(
                      color: highlighted
                          ? const Color(0xFFFFD700)
                          : Colors.white54,
                      width: 1.6,
                    ),
                  ),
                  child: highlighted
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.black,
                          size: 18,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        if (recommended)
          Positioned(
            top: -11,
            right: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: Text(
                'BEST VALUE',
                style: GoogleFonts.inter(
                  color: const Color(0xFFFFD700),
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

class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final List<_ConfettiPiece> _pieces = List<_ConfettiPiece>.generate(
    24,
    (int i) => _ConfettiPiece(
      dx: (math.Random(i + 11).nextDouble() * 2) - 1,
      dy: (math.Random(i + 31).nextDouble() * -1.1) - 0.2,
      size: 6 + math.Random(i + 51).nextDouble() * 8,
      color: i.isEven ? const Color(0xFFFFD700) : Colors.white,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Opacity(
          opacity: 1 - t,
          child: Stack(
            children: _pieces
                .map(
                  (_ConfettiPiece p) => Align(
                    alignment: Alignment(0, 0.6),
                    child: Transform.translate(
                      offset: Offset(p.dx * 180 * t, p.dy * 280 * t),
                      child: Transform.rotate(
                        angle: t * math.pi * 2,
                        child: Container(
                          width: p.size,
                          height: p.size * 0.6,
                          decoration: BoxDecoration(
                            color: p.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _ConfettiPiece {
  final double dx;
  final double dy;
  final double size;
  final Color color;

  const _ConfettiPiece({
    required this.dx,
    required this.dy,
    required this.size,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Paywall Plan Card — fills Expanded height, slightly bigger than compact
// ─────────────────────────────────────────────────────────────────────────────
class _PaywallPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final bool selected;
  final bool showTrial;
  final VoidCallback? onTap;

  const _PaywallPlanCard({
    required this.title,
    required this.price,
    required this.selected,
    this.showTrial = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double scale = (screenHeight / 900.0).clamp(0.68, 1.0);

    final double cardHeight = 96 * scale;
    final double paddingHorizontal = 20 * scale;
    final double paddingVertical = 14 * scale;
    final double titleFontSize = 19 * scale;
    final double priceFontSize = 28 * scale;
    final double radioSize = 36 * scale;
    final double checkIconSize = 20 * scale;
    final double badgeTop = -11 * scale;
    final double badgeFontSize = 11 * scale;
    final double titleToPriceGap = 6 * scale;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: double.infinity,
            height: cardHeight,
            padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF1A1500)
                  : const Color(0xFF181818),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? const Color(0xFFFFD700) : Colors.white24,
                width: selected ? 2.0 : 1.2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.10),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: titleToPriceGap),
                      Text(
                        price,
                        style: GoogleFonts.inter(
                          color: selected
                              ? const Color(0xFFFFD700)
                              : Colors.white,
                          fontSize: priceFontSize,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                // Radio circle
                Container(
                  width: radioSize,
                  height: radioSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? const Color(0xFFFFD700)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFD700)
                          : Colors.white38,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: checkIconSize, color: Colors.black)
                      : null,
                ),
              ],
            ),
          ),
          // 3 DAYS FREE badge
          if (showTrial)
            Positioned(
              top: badgeTop,
              right: 14,
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 5 * scale),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: const Color(0xFFFFD700), width: 1.5),
                ),
                child: Text(
                  '3 DAYS FREE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: badgeFontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Big Plan Card — full-height, large text, used in the commitment step
// ─────────────────────────────────────────────────────────────────────────────
class _BigPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String subtitle;
  final bool selected;
  final bool showTrial;
  final VoidCallback? onTap;

  const _BigPlanCard({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.selected,
    this.showTrial = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF1E1A0E)
                  : const Color(0xFF181818),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? const Color(0xFFFFD700) : Colors.white24,
                width: selected ? 2.2 : 1.2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Title + price + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        price,
                        style: GoogleFonts.inter(
                          color: selected
                              ? const Color(0xFFFFD700)
                              : Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Right: radio circle
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? const Color(0xFFFFD700)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFD700)
                          : Colors.white38,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 18, color: Colors.black)
                      : null,
                ),
              ],
            ),
          ),
          // 3 DAYS FREE badge
          if (showTrial)
            Positioned(
              top: -12,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                ),
                child: Text(
                  '3 DAYS FREE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dark Plan Option Widget (for plan selection UI)
// ─────────────────────────────────────────────────────────────────────────────
class _DarkPlanOption extends StatelessWidget {
  final String title;
  final String price;
  final bool selected;
  final bool showTrial;
  final VoidCallback? onTap;

  const _DarkPlanOption({
    required this.title,
    required this.price,
    required this.selected,
    this.showTrial = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? const Color(0xFFFFD700) : Colors.white24,
                width: selected ? 2 : 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 22.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? const Color(0xFFFFD700)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFD700)
                          : Colors.white54,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.black)
                      : null,
                ),
              ],
            ),
          ),

          if (showTrial)
            Positioned(
              top: -10,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFFFD700)),
                ),
                child: Text(
                  '3 DAYS FREE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Comparison Table for Paywall
// ─────────────────────────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  @override
  Widget build(BuildContext context) {
    final bool isIndia =
        PricingLocationService.currentRegion == PricingRegion.india;
    const Color gold = Color(0xFFFFD700);

    return Column(
      children: [
        const SizedBox(height: 10),
        // Side-by-Side Cards (Image Style)
        // Very Big Coffee Visual
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 25,
                  spreadRadius: 2,
                ),
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

        const SizedBox(height: 12),

        // Marketing Text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Text(
                isIndia
                    ? 'Costs less than a\ncup of coffee.'
                    : 'Costs less than a\nmovie ticket (\$8.99).',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'Unlock elite-level cricket analysis for 30 days to ',
                    ),
                    TextSpan(
                      text: 'boost your game.',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

        const SizedBox(height: 12),

        // CTA Button
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Unlock everything. Cancel anytime.',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final Color color;
  final String imageSource; // URL or Path
  final String title;
  final String subtitle;
  final bool isPro;
  final bool showCNLogo;

  const _ComparisonCard({
    required this.color,
    required this.imageSource,
    required this.title,
    required this.subtitle,
    this.isPro = false,
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
          ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981), // Emerald/CN Green
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          'CN',
                          style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
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
