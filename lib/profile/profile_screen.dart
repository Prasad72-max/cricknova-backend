import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:provider/provider.dart';
import '../premium/premium_screen.dart';
import '../auth/login_screen.dart';
import '../navigation/main_navigation.dart';
import '../services/pricing_location_service.dart';
import '../services/premium_service.dart';
import '../services/subscription_provider.dart';
import '../live/live_nets_tab.dart';
import '../premium/elite_support_chat_screen.dart';
import 'faq_screen.dart';
import 'legal_info_screen.dart';
import '../reels/screens/my_reels_screen.dart';
import '../reels/screens/saved_reels_screen.dart';
import '../theme/crickx_colors.dart';

class _SubscriptionPlanSpec {
  const _SubscriptionPlanSpec({
    required this.planId,
    required this.title,
    required this.price,
    required this.region,
    required this.icon,
    required this.features,
    this.recommended = false,
  });

  final String planId;
  final String title;
  final String price;
  final String region;
  final IconData icon;
  final List<String> features;
  final bool recommended;
}

const String _onboardingSeenOnceKey = 'cricknova_onboarding_seen_once';

class _SubscriptionHub extends StatelessWidget {
  const _SubscriptionHub({required this.onUpgrade});

  final VoidCallback onUpgrade;

  static const _domesticPlans = [
    _SubscriptionPlanSpec(
      planId: 'IN_99',
      title: 'Domestic Basic',
      price: 'INR 99',
      region: 'Domestic',
      icon: Icons.star_border_rounded,
      features: [
        '100% Ad-Free Experience',
        '1,000 CricX Chat Coach',
        '90 CricX Mistake Detection',
        '60 CricX Analyse Yourself',
      ],
    ),
    _SubscriptionPlanSpec(
      planId: 'IN_299',
      title: 'Domestic Plus',
      price: 'INR 299',
      region: 'Domestic',
      icon: Icons.auto_awesome_outlined,
      features: [
        '100% Ad-Free Experience',
        '3,000 CricX Chat Coach',
        '400 CricX Mistake Detection',
        '300 CricX Analyse Yourself',
      ],
    ),
    _SubscriptionPlanSpec(
      planId: 'IN_499',
      title: 'Domestic Pro',
      price: 'INR 499',
      region: 'Domestic',
      icon: Icons.workspace_premium_outlined,
      features: [
        '100% Ad-Free Experience',
        '7,000 CricX Chat Coach',
        '800 CricX Mistake Detection',
        '700 CricX Analyse Yourself',
        'Pro Coaching Insights',
      ],
      recommended: true,
    ),
  ];

  static const _globalPlans = [
    _SubscriptionPlanSpec(
      planId: 'INTL_MONTHLY',
      title: 'Starter ⚡',
      price: '\$8.99/month',
      region: 'Global',
      icon: Icons.star_border_rounded,
      features: [
        '100% Ad-Free Experience',
        '1,000 CricX Chat Coach',
        '90 CricX Mistake Detection',
        '60 CricX Analyse Yourself',
      ],
    ),
    _SubscriptionPlanSpec(
      planId: 'INTL_6M',
      title: 'Season Pass 🔥',
      price: '\$29.99 / 6 months',
      region: 'Global',
      icon: Icons.auto_awesome_outlined,
      features: [
        '100% Ad-Free Experience',
        '3,000 CricX Chat Coach',
        '400 CricX Mistake Detection',
        '300 CricX Analyse Yourself',
      ],
    ),
    _SubscriptionPlanSpec(
      planId: 'INTL_YEARLY',
      title: 'Pro Athlete 💎',
      price: '\$59.99/year',
      region: 'Global',
      icon: Icons.workspace_premium_outlined,
      features: [
        '100% Ad-Free Experience',
        '7,000 CricX Chat Coach',
        '800 CricX Mistake Detection',
        '700 CricX Analyse Yourself',
        'Advanced AI Reports',
      ],
      recommended: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PremiumService.premiumNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<PricingRegion>(
          valueListenable: PricingLocationService.regionNotifier,
          builder: (context, region, __) {
            final currentPlan = _planForId(PremiumService.plan, region);
            final visiblePlans = region == PricingRegion.india
                ? _domesticPlans
                : _globalPlans;
            final visibleTitle = region == PricingRegion.india
                ? 'Domestic'
                : 'Global';
            final visibleSubtitle = region == PricingRegion.india
                ? 'INR tiers for India-based pricing'
                : 'USD tiers for international pricing';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActiveSubscriptionCard(plan: currentPlan),
                const SizedBox(height: 16),
                _SectionLabel(title: visibleTitle, subtitle: visibleSubtitle),
                const SizedBox(height: 10),
                _PlanRail(
                  plans: visiblePlans,
                  currentPlanId: PremiumService.plan,
                  onTap: (plan) => _showPlanDetails(context, plan),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ready for the pitch? Your AI is awake and calibrated.',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFA0A0A0),
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  _SubscriptionPlanSpec _planForId(String planId, PricingRegion region) {
    final all = [..._domesticPlans, ..._globalPlans];
    for (final plan in all) {
      if (plan.planId == planId) return plan;
    }
    return region == PricingRegion.india
        ? _domesticPlans.last
        : _globalPlans.last;
  }

  void _showPlanDetails(BuildContext context, _SubscriptionPlanSpec plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanComparisonSheet(
        plan: plan,
        currentPlanId: PremiumService.plan,
        onUpgrade: onUpgrade,
      ),
    );
  }
}

class _ActiveSubscriptionCard extends StatelessWidget {
  const _ActiveSubscriptionCard({required this.plan});

  final _SubscriptionPlanSpec plan;

  @override
  Widget build(BuildContext context) {
    final expiry = PremiumService.expiryDate;
    final isPremium = PremiumService.isPremiumActive;
    final now = DateTime.now();
    final remaining = expiry == null ? null : expiry.difference(now);
    final renewalLabel = remaining == null
        ? 'Renewal not synced'
        : remaining.isNegative
        ? 'Expired'
        : '${remaining.inDays}d ${remaining.inHours % 24}h left';

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: CrickXColors.graphite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: CrickXColors.limeSpark.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    isPremium ? 'PRO' : 'FREE',
                    style: GoogleFonts.poppins(
                      color: CrickXColors.limeSpark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(plan.icon, color: CrickXColors.limeSpark, size: 20),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Current Plan',
              style: GoogleFonts.poppins(
                color: const Color(0xFFA1A1AA),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isPremium ? '${plan.title} ${plan.price}' : 'Free Access',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatusChip(
                    label: 'Next renewal',
                    value: renewalLabel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusChip(
                    label: 'Plan code',
                    value: PremiumService.plan,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanRail extends StatelessWidget {
  const _PlanRail({
    required this.plans,
    required this.currentPlanId,
    required this.onTap,
  });

  final List<_SubscriptionPlanSpec> plans;
  final String currentPlanId;
  final ValueChanged<_SubscriptionPlanSpec> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: plans.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final plan = plans[index];
          final selected = plan.planId == currentPlanId;
          return GestureDetector(
            onTap: () => onTap(plan),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 170,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CrickXColors.graphite,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected
                      ? CrickXColors.limeSpark
                      : plan.recommended
                      ? CrickXColors.limeSpark
                      : CrickXColors.graphiteBorder,
                  width: selected || plan.recommended ? 1.5 : 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        plan.icon,
                        size: 20,
                        color: plan.recommended
                            ? CrickXColors.limeSpark
                            : const Color(0xFFD0D6DD),
                      ),
                      const Spacer(),
                      if (plan.recommended)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: CrickXColors.limeSpark.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'Recommended',
                            style: GoogleFonts.poppins(
                              color: CrickXColors.limeSpark,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    plan.title,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    plan.price,
                    style: GoogleFonts.poppins(
                      color: plan.recommended
                          ? CrickXColors.limeSpark
                          : const Color(0xFFD0D6DD),
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plan.features.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFA0A0A0),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlanComparisonSheet extends StatelessWidget {
  const _PlanComparisonSheet({
    required this.plan,
    required this.currentPlanId,
    required this.onUpgrade,
  });

  final _SubscriptionPlanSpec plan;
  final String currentPlanId;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('AI Ball Tracking', true),
      ('RPM Analysis', plan.features.contains('RPM Analysis')),
      (
        'CricX Bowling Analysis',
        plan.features.contains('CricX Bowling Analysis'),
      ),
      (
        'CricX Analyse Yourself (Batting/Bowling)',
        plan.features.any(
          (feature) =>
              feature.contains('CricX Analyse Yourself (Batting/Bowling)'),
        ),
      ),
      (
        'Pro Coaching Insights',
        plan.features.contains('Pro Coaching Insights'),
      ),
      ('Elite DRS Tools', plan.features.contains('Elite DRS Tools')),
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CrickXColors.graphite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  plan.icon,
                  color: plan.recommended
                      ? CrickXColors.limeSpark
                      : Colors.white70,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${plan.title} ${plan.price}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: CrickXColors.graphiteElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CrickXColors.graphiteBorder),
              ),
              child: Column(
                children: rows
                    .map(
                      (row) => ListTile(
                        dense: true,
                        leading: Icon(
                          row.$2 ? Icons.check_circle_rounded : Icons.cancel_outlined,
                          color: row.$2
                              ? CrickXColors.limeSpark
                              : Colors.white24,
                          size: 18,
                        ),
                        title: Text(
                          row.$1,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: currentPlanId == plan.planId
                    ? null
                    : () {
                        Navigator.pop(context);
                        onUpgrade();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: plan.recommended
                      ? CrickXColors.limeSpark
                      : CrickXColors.graphiteElevated,
                  foregroundColor: plan.recommended
                      ? CrickXColors.onLime
                      : Colors.white,
                  disabledBackgroundColor: Colors.white10,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: plan.recommended
                          ? Colors.transparent
                          : CrickXColors.graphiteBorder,
                    ),
                  ),
                ),
                child: Text(
                  currentPlanId == plan.planId
                      ? 'Current plan'
                      : 'View Checkout',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            color: const Color(0xFFA0A0A0),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CrickXColors.graphiteBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final TextEditingController nameController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String? userEmail;
  String? userPhotoUrl;

  File? profileImage;
  final ImagePicker _picker = ImagePicker();
  bool _isEditingProfile = false;
  bool _nameDirty = false;
  String _savedName = "";
  bool _profileDataLoaded = false;

  double maxSpeed = 0;
  int totalVideos = 0;
  int totalCertificates = 0;
  int totalXP = 0;
  int chatXP = 0;
  int remainingXP = 0;
  Box? _statsBox;
  int nextMilestone = 50000;
  late final AnimationController _supportPulseController;
  late final AnimationController _xpShimmerController;
  late final Animation<double> _supportPulse;
  bool _showRatingDetails = false;
  int _selectedRating = 0;
  late final TextEditingController _reviewController;
  bool _profileAnimationsActive = false;

  Future<void> _resetOnboardingForNextLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingSeenOnceKey);
  }

  Future<Box> _getStatsBox(String uid) async {
    final boxName = "local_stats_$uid";
    if (_statsBox != null && _statsBox!.name == boxName) {
      return _statsBox!;
    }
    _statsBox = await Hive.openBox(boxName);
    return _statsBox!;
  }

  @override
  void initState() {
    super.initState();
    _supportPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _supportPulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _supportPulseController, curve: Curves.easeInOut),
    );
    _xpShimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _reviewController = TextEditingController(
      text:
          "CricX AI is very good and accurate. It helped me improve my bowling speed and swing.",
    );
    MainNavigation.activeTabNotifier.addListener(_handleTabVisibilityChange);
    if (_isProfileTabVisible) {
      _resumeProfileAnimations();
    } else {
      _pauseProfileAnimations();
    }
    loadProfileData();
  }

  bool get _isProfileTabVisible => MainNavigation.activeTabNotifier.value == 3;

  void _handleTabVisibilityChange() {
    if (_isProfileTabVisible) {
      _resumeProfileAnimations();
      return;
    }
    _pauseProfileAnimations();
  }

  void _resumeProfileAnimations() {
    if (_profileAnimationsActive) return;
    _profileAnimationsActive = true;
    if (!_supportPulseController.isAnimating) {
      _supportPulseController.repeat(reverse: true);
    }
    if (!_xpShimmerController.isAnimating) {
      _xpShimmerController.repeat();
    }
  }

  void _pauseProfileAnimations() {
    if (!_profileAnimationsActive) return;
    _profileAnimationsActive = false;
    _supportPulseController.stop();
    _xpShimmerController.stop();
  }

  @override
  void dispose() {
    _pauseProfileAnimations();
    MainNavigation.activeTabNotifier.removeListener(_handleTabVisibilityChange);
    _supportPulseController.dispose();
    _xpShimmerController.dispose();
    nameController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "guest";
    userEmail = user?.email;
    userPhotoUrl = user?.photoURL;
    if (userPhotoUrl == null || userPhotoUrl!.isEmpty) {
      for (final profile in user?.providerData ?? []) {
        if (profile.photoURL != null && profile.photoURL!.isNotEmpty) {
          userPhotoUrl = profile.photoURL;
          break;
        }
      }
    }

    // 🔥 Load XP & stats from Hive (local storage)
    final box = await _getStatsBox(uid);

    // ✅ Load profile photo from Hive (per-user)
    profileImage = null;
    final hiveImagePath = box.get("profileImagePath") as String?;
    if (hiveImagePath != null && hiveImagePath.isNotEmpty) {
      final file = File(hiveImagePath);
      if (await file.exists()) {
        profileImage = file;
      } else {
        await box.delete("profileImagePath");
      }
    } else {
      // 🔁 Migrate legacy SharedPreferences value (global) into Hive
      final legacyPath = prefs.getString("profileImagePath");
      if (legacyPath != null && legacyPath.isNotEmpty) {
        final file = File(legacyPath);
        if (await file.exists()) {
          await box.put("profileImagePath", legacyPath);
          profileImage = file;
        }
        await prefs.remove("profileImagePath");
      }
    }

    totalXP = box.get("xp", defaultValue: 0);
    totalVideos = box.get("totalVideos", defaultValue: 0);
    maxSpeed = box.get("maxSpeed", defaultValue: 0.0);

    final claimed50 = box.get("claimed_50000", defaultValue: false);
    final claimed5L = box.get("claimed_500000", defaultValue: false);
    final claimed10L = box.get("claimed_1000000", defaultValue: false);
    final claimed20L = box.get("claimed_2000000", defaultValue: false);

    if (!claimed50) {
      nextMilestone = 50000;
    } else if (!claimed5L) {
      nextMilestone = 500000;
    } else if (!claimed10L) {
      nextMilestone = 1000000;
    } else if (!claimed20L) {
      nextMilestone = 2000000;
    } else {
      nextMilestone = 2000000;
    }

    // Calculate remaining XP for current milestone
    remainingXP = nextMilestone - totalXP;
    if (remainingXP < 0) remainingXP = 0;

    final hiveName = (box.get("profileName") as String?)?.trim();
    final uidProfileName = prefs.getString("profileName_$uid")?.trim();
    final uidUserName = prefs.getString("userName_$uid")?.trim();
    final authName = user?.displayName?.trim();
    final emailName = _nameFromEmail(user?.email);
    final onboardingProfileName = prefs.getString("profileName")?.trim();
    final onboardingUserName = prefs.getString("userName")?.trim();
    final resolvedName =
        [
          hiveName,
          uidProfileName,
          uidUserName,
          authName,
          emailName,
          if (uid == 'guest') onboardingProfileName,
          if (uid == 'guest') onboardingUserName,
        ].whereType<String>().firstWhere(
          (name) => name.isNotEmpty && name.toLowerCase() != "player",
          orElse: () => "",
        );

    _savedName = resolvedName;
    if (_savedName.isNotEmpty && _savedName != hiveName) {
      await box.put("profileName", _savedName);
    }
    nameController.text = _savedName;
    _isEditingProfile = _savedName.isEmpty;
    _nameDirty = false;

    // 💬 Load AI Chat XP count (still from SharedPreferences)
    chatXP = prefs.getInt("chatXP_$uid") ?? 0;

    final savedCerts = prefs.getStringList("savedCertificates") ?? [];

    // Remove duplicate certificate paths
    final uniqueCerts = savedCerts.toSet().toList();

    totalCertificates = uniqueCerts.length;

    _profileDataLoaded = true;
    if (!mounted) return;
    setState(() {});
  }

  String? _nameFromEmail(String? email) {
    final raw = email?.trim();
    if (raw == null || raw.isEmpty || !raw.contains('@')) return null;
    final local = raw.split('@').first.trim();
    return local.isEmpty ? null : local;
  }

  Future<void> saveName() async {
    final trimmed = nameController.text.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter your name.")),
        );
      }
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final box = await _getStatsBox(uid);
    final prefs = await SharedPreferences.getInstance();
    await box.put("profileName", trimmed);
    await prefs.setString("profileName_$uid", trimmed);
    await prefs.setString("userName_$uid", trimmed);
    // Legacy fallbacks
    await prefs.setString("profileName", trimmed);
    await prefs.setString("userName", trimmed);
    MainNavigation.userNameNotifier.value = trimmed;
    _savedName = trimmed;
    _isEditingProfile = false;
    _nameDirty = false;

    // Perform Firebase Auth and Firestore network updates in the background (optimistically)
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      user.updateDisplayName(trimmed).catchError((_) {});
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'display_name': trimmed,
            'name': trimmed,
            'onboardingAnswers': {'display_name': trimmed},
          }, SetOptions(merge: true))
          .catchError((e) {
            debugPrint("Firestore name sync error: $e");
          });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Profile updated!"),
        duration: Duration(milliseconds: 800),
      ),
    );
    setState(() {});
  }

  Future<void> pickProfileImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
      final box = await _getStatsBox(uid);
      await box.put("profileImagePath", picked.path);
      setState(() {
        profileImage = File(picked.path);
      });
    }
  }

  void showPremiumPopup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PremiumScreen(entrySource: "profile"),
      ),
    );
  }

  void _openSubscriptionHub() {
    context.read<SubscriptionProvider>().fetchProducts();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: const PremiumScreen(entrySource: "profile"),
        ),
      ),
    );
  }

  Future<void> _openRating() async {
    try {
      final review = InAppReview.instance;
      await review.openStoreListing();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Thanks for supporting CricX AI!")),
    );
  }

  void logoutUser() async {
    try {
      await _resetOnboardingForNextLogin();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("is_logged_in");
      await prefs.remove("isLoggedIn");
      await prefs.remove("firebase_id_token");
      await prefs.remove("user_id");
      await prefs.remove("uid");
      await prefs.remove("login_type");
      await prefs.remove("userName");
      await prefs.remove("user_name");
      await FirebaseAuth.instance.signOut();
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(
          postLoginTarget: LoginPostLoginTarget.app,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _confirmRemoveAccount() async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF0E131B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.redAccent,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  "Are you sure?",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "This will permanently delete your CricX AI account and all associated user data. This action cannot be undone.",
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (PremiumService.isPremiumActive) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.redAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "ELITE STATUS WARNING:\nYou have an active Elite Subscription. Removing your account will permanently cancel your Elite status and forfeit any remaining time. This cannot be recovered.",
                            style: GoogleFonts.poppins(
                              color: Colors.redAccent.shade100,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          "Cancel",
                          style: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          "Delete",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldDelete != true || !mounted) return;
    await _removeAccount();
  }

  Future<void> _removeAccount() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Please log in again to remove account.")),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uid = user.uid;
      await user.delete();
      await _deleteFirestoreUserData(uid);
      await _resetOnboardingForNextLogin();

      try {
        await _googleSignIn.signOut();
        await _googleSignIn.disconnect();
      } catch (_) {}

      if (!mounted) return;
      navigator.pop();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(
            postLoginTarget: LoginPostLoginTarget.app,
          ),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      navigator.pop();
      final bool needsRecentLogin =
          error.code == 'requires-recent-login' ||
          error.code == 'credential-too-old-login-again';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            needsRecentLogin
                ? "For security, please log in again and then retry removing your account."
                : (error.message?.isNotEmpty == true
                      ? error.message!
                      : "Unable to remove account right now. Please try again."),
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'permission-denied'
                ? "Some Firestore data could not be removed from this device. Please log in again and retry."
                : (error.message?.isNotEmpty == true
                      ? error.message!
                      : "Unable to remove account right now. Please try again."),
          ),
        ),
      );
    } catch (error) {
      debugPrint("REMOVE_ACCOUNT ERROR => $error");
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "Unable to remove account right now. ${error.toString()}",
          ),
        ),
      );
    }
  }

  Future<void> _deleteFirestoreUserData(String uid) async {
    final firestore = FirebaseFirestore.instance;

    await _runCleanupStep(
      'support_chat_messages',
      () => _deleteCollectionQuery(
        firestore.collection('support_chats').doc(uid).collection('messages'),
      ),
    );
    await _runCleanupStep(
      'support_chat_doc',
      () => firestore.collection('support_chats').doc(uid).delete(),
    );
    await _runCleanupStep(
      'premium_device_bindings',
      () => firestore.collection('premium_device_bindings').doc(uid).delete(),
    );
    await _runCleanupStep(
      'subscriptions',
      () => firestore.collection('subscriptions').doc(uid).delete(),
    );
    await _runCleanupStep(
      'users',
      () => firestore.collection('users').doc(uid).delete(),
    );
    await _runCleanupStep(
      'claims',
      () => _deleteCollectionQuery(
        firestore.collection('claims').where('userId', isEqualTo: uid),
      ),
    );
    await _runCleanupStep(
      'security_logs',
      () => _deleteCollectionQuery(
        firestore.collection('security_logs').where('userId', isEqualTo: uid),
      ),
    );
  }

  Future<void> _deleteCollectionQuery(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snapshot = await query.limit(25).get();
      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < 25) {
        return;
      }
    }
  }

  Future<void> _runCleanupStep(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('REMOVE_ACCOUNT CLEANUP [$label] => $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsBox = _statsBox;

    return Scaffold(
      backgroundColor: CrickXColors.graphiteBg,
      body: RefreshIndicator(
        color: CrickXColors.limeSpark,
        backgroundColor: CrickXColors.graphiteBg,
        notificationPredicate: (_) => false,
        onRefresh: () async {},
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 14,
                  20,
                  0,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
                decoration: BoxDecoration(
                  color: CrickXColors.graphite,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: CrickXColors.graphiteBorder,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: showImageOptions,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 140,
                            width: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: CrickXColors.graphiteElevated,
                              border: Border.all(
                                color: CrickXColors.limeSpark,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: CrickXColors.limeSpark.withValues(alpha: 0.25),
                                  blurRadius: 20,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: profileImage != null
                                  ? Image.file(
                                      profileImage!,
                                      width: 140,
                                      height: 140,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildAvatarFallback(),
                                    )
                                  : ((userPhotoUrl ?? FirebaseAuth.instance.currentUser?.photoURL) != null &&
                                          (userPhotoUrl ?? FirebaseAuth.instance.currentUser?.photoURL)!.trim().isNotEmpty)
                                      ? Image.network(
                                          (userPhotoUrl ?? FirebaseAuth.instance.currentUser?.photoURL)!,
                                          width: 140,
                                          height: 140,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  _buildAvatarFallback(),
                                        )
                                      : _buildAvatarFallback(),
                            ),
                          ),
                          if (PremiumService.isPremium)
                            Positioned(
                              bottom: 4,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: CrickXColors.limeSpark,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: CrickXColors.limeSpark.withValues(alpha: 0.45),
                                      blurRadius: 16,
                                      spreadRadius: 0.5,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star,
                                      color: CrickXColors.onLime,
                                      size: 13,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "ELITE",
                                      style: GoogleFonts.poppins(
                                        color: CrickXColors.onLime,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10.5,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _savedName.isNotEmpty ? _savedName : "Player",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PremiumScreen(
                                  entrySource: 'profile_name_go_elite',
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: CrickXColors.limeSpark,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: CrickXColors.limeSpark.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.workspace_premium_rounded,
                                  color: CrickXColors.onLime,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  PremiumService.isPremium ? "ELITE" : "GO ELITE",
                                  style: GoogleFonts.poppins(
                                    color: CrickXColors.onLime,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10.5,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (userEmail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          userEmail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.58),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 👤 PERSONAL INFORMATION (Dark Premium Style)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: CrickXColors.graphite,
                    border: Border.all(
                      color: CrickXColors.graphiteBorder,
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        blurRadius: 18,
                        spreadRadius: 1,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: CrickXColors.graphiteElevated,
                              border: Border.all(color: CrickXColors.graphiteBorder),
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Personal Information",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Secure & private account details",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: PremiumService.isPremium
                                  ? CrickXColors.limeSpark.withValues(alpha: 0.16)
                                  : Colors.white10,
                              border: Border.all(
                                color: PremiumService.isPremium
                                    ? CrickXColors.limeSpark
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              PremiumService.isPremium ? "PREMIUM" : "FREE",
                              style: GoogleFonts.poppins(
                                color: PremiumService.isPremium
                                    ? CrickXColors.limeSpark
                                    : Colors.white70,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: CrickXColors.graphiteBorder,
                      ),
                      const SizedBox(height: 16),
                      if (_isEditingProfile)
                        TextField(
                          controller: nameController,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                          decoration: inputStyle("Full Name").copyWith(
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              color: Colors.white54,
                            ),
                          ),
                          onChanged: (val) {
                            final trimmed = val.trim();
                            final dirty =
                                trimmed.isNotEmpty && trimmed != _savedName;
                            if (dirty != _nameDirty) {
                              setState(() {
                                _nameDirty = dirty;
                              });
                            }
                          },
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: CrickXColors.graphiteElevated,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: CrickXColors.graphiteBorder,
                              width: 1.1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                color: Color(0xFF94A3B8),
                                size: 19,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _savedName.isNotEmpty ? _savedName : "Player",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: CrickXColors.graphiteElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: CrickXColors.graphiteBorder,
                            width: 1.1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.mail_outline_rounded,
                              color: Color(0xFF94A3B8),
                              size: 19,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                userEmail ?? "Email not linked",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isEditingProfile && _nameDirty)
                        InkWell(
                          onTap: saveName,
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: CrickXColors.limeSpark,
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              child: Text(
                                "Save Profile",
                                style: GoogleFonts.poppins(
                                  color: CrickXColors.onLime,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (!_isEditingProfile)
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isEditingProfile = true;
                              _nameDirty = false;
                              nameController.text = _savedName;
                            });
                          },
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.white,
                            size: 16,
                          ),
                          label: Text(
                            "Edit Profile",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: CrickXColors.graphiteElevated,
                            side: const BorderSide(
                              color: CrickXColors.graphiteBorder,
                              width: 1.1,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // PREMIUM
              cardContainer(
                title: "Explore Premium",
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseAuth.instance.currentUser != null
                      ? FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser!.uid)
                          .snapshots()
                      : null,
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() ?? {};
                    final balanceMs = LiveNetsAccessCard.balanceMsFrom(data);
                    final hasEdgeBalance = balanceMs > 0;

                    return Column(
                      children: [
                        // 1. Cricket Edge (Live AI Nets)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: CrickXColors.graphiteElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CrickXColors.limeSpark.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: CrickXColors.limeSpark.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.sports_cricket_rounded,
                              color: CrickXColors.limeSpark,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                "Cricket Edge",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: CrickXColors.limeSpark.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  hasEdgeBalance ? "ACTIVE" : "LIVE NETS",
                                  style: GoogleFonts.poppins(
                                    color: CrickXColors.limeSpark,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              hasEdgeBalance
                                  ? "Balance: ${LiveNetsAccessCard.formatBalance(balanceMs)} • Live net session"
                                  : "Live snicko, ball tracking & match-speed nets",
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Color(0xFF71717A),
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LiveNetsTab(),
                              ),
                            );
                          },
                        ),

                        const Divider(
                          color: Color(0xFF23232A),
                          height: 20,
                        ),

                        // 2. Open Subscription Hub
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: CrickXColors.graphiteElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CrickXColors.limeSpark.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: CrickXColors.limeSpark.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.sports_score_rounded,
                              color: CrickXColors.limeSpark,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                "Subscription Hub",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: PremiumService.isPremiumActive
                                      ? CrickXColors.limeSpark.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: PremiumService.isPremiumActive
                                        ? CrickXColors.limeSpark.withValues(alpha: 0.5)
                                        : Colors.white24,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  PremiumService.isPremiumActive ? "PRO ACTIVE" : "ALL PLANS",
                                  style: GoogleFonts.poppins(
                                    color: PremiumService.isPremiumActive
                                        ? CrickXColors.limeSpark
                                        : Colors.white70,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              PremiumService.isPremiumActive
                                  ? "Manage your current plan • 100% Ad-Free"
                                  : "Compare all tiers, AI coach & 100% Ad-Free",
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Color(0xFF71717A),
                          ),
                          onTap: _openSubscriptionHub,
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // SUPPORT & RATING
              cardContainer(
                title: "Support & Rating",
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: CrickXColors.graphiteElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: CrickXColors.graphiteBorder,
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: CrickXColors.limeSpark,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        "Rate CricX AI",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        "Love using CricX? Give us 5 stars on Google Play",
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                              border: Border.all(
                                color: CrickXColors.limeSpark.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: CrickXColors.limeSpark,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  "5.0",
                                  style: GoogleFonts.poppins(
                                    color: CrickXColors.limeSpark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Color(0xFF71717A),
                          ),
                        ],
                      ),
                      onTap: _openRating,
                    ),
                    const Divider(color: Color(0xFF23232A), height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: CrickXColors.graphiteElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: CrickXColors.graphiteBorder,
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.support_agent_rounded,
                          color: CrickXColors.limeSpark,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        "Help & Customer Support",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        "Direct support chat with our dedicated team",
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF71717A),
                      ),
                      onTap: () {
                        _openDarkProfilePage(
                          context,
                          const EliteSupportChatScreen(),
                        );
                      },
                    ),
                    const Divider(color: Color(0xFF23232A), height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: CrickXColors.graphiteElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: CrickXColors.graphiteBorder,
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.help_outline_rounded,
                          color: Color(0xFFE2E8F0),
                          size: 19,
                        ),
                      ),
                      title: Text(
                        "FAQs & Help Guide",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        "Quick answers to common questions",
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF71717A),
                      ),
                      onTap: () {
                        _openDarkProfilePage(context, const FaqScreen());
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 📜 LEGAL & APP INFO
              cardContainer(
                title: "Legal & App Information",
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF27272E),
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.privacy_tip_outlined,
                          color: Color(0xFFE2E8F0),
                          size: 19,
                        ),
                      ),
                      title: Text(
                        "Privacy Policy",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF71717A),
                      ),
                      onTap: () {
                        _openDarkProfilePage(
                          context,
                          LegalInfoScreen(document: LegalDocument.privacy()),
                        );
                      },
                    ),
                    const Divider(color: Color(0xFF23232A), height: 16),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF27272E),
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: Color(0xFFE2E8F0),
                          size: 19,
                        ),
                      ),
                      title: Text(
                        "Terms & Conditions",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF71717A),
                      ),
                      onTap: () {
                        _openDarkProfilePage(
                          context,
                          LegalInfoScreen(document: LegalDocument.terms()),
                        );
                      },
                    ),
                    const Divider(color: Color(0xFF23232A), height: 16),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF27272E),
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.help_outline_rounded,
                          color: Color(0xFFE2E8F0),
                          size: 19,
                        ),
                      ),
                      title: Text(
                        "FAQs",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF71717A),
                      ),
                      onTap: () {
                        _openDarkProfilePage(context, const FaqScreen());
                      },
                    ),
                    const Divider(color: Color(0xFF23232A), height: 16),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF27272E),
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFFE2E8F0),
                          size: 19,
                        ),
                      ),
                      title: Text(
                        "About CricX AI",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF71717A),
                      ),
                      onTap: () {
                        _openDarkProfilePage(
                          context,
                          LegalInfoScreen(document: LegalDocument.about()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // LOG OUT
              cardContainer(
                title: "Account",
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF27272E),
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFEF4444),
                          size: 19,
                        ),
                      ),
                      title: Text(
                        "Log Out",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF71717A),
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: const Color(0xFF0D0D12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                              side: const BorderSide(
                                color: Color(0xFF23232A),
                                width: 1.2,
                              ),
                            ),
                            title: Text(
                              "Log Out",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            content: Text(
                              "Are you sure you want to log out?",
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF94A3B8),
                                fontSize: 13.5,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  "Go Back",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () async {
                                  Navigator.pop(context);
                                  try {
                                    await _resetOnboardingForNextLogin();
                                    await FirebaseAuth.instance.signOut();
                                    await _googleSignIn.signOut();
                                    await _googleSignIn.disconnect();
                                  } catch (_) {}

                                  if (!mounted) return;

                                  Navigator.of(this.context).pushAndRemoveUntil(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const LoginScreen(
                                            postLoginTarget: LoginPostLoginTarget.app,
                                          ),
                                    ),
                                    (route) => false,
                                  );
                                },
                                child: Text(
                                  "Yes, Log Out",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(color: Color(0xFF23232A), height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF27272E),
                            width: 1.1,
                          ),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 19,
                        ),
                      ),
                      title: Text(
                        "Remove My Account",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        "Permanently delete your account and user data",
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      onTap: _confirmRemoveAccount,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  "⚠️ AI Disclaimer:\nAll AI-generated insights, speed estimates, DRS decisions, and coaching feedback are provided for training and educational purposes only. Results may vary based on video quality, camera angle, lighting, and frame rate. CricX AI does not claim official match accuracy or replacement of professional umpires or coaches.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white38,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 📌 Helper Widgets
  void _openDarkProfilePage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: const Color(0xFF050505),
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: const Duration(milliseconds: 90),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ColoredBox(color: const Color(0xFF050505), child: page),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  Widget cardContainer({required String title, required Widget child}) {
    IconData headerIcon = Icons.dashboard_customize_outlined;
    Color headerAccent = CrickXColors.limeSpark;

    if (title == "Cricket Reels & History") {
      headerIcon = Icons.play_circle_outline_rounded;
      headerAccent = CrickXColors.limeSpark;
    } else if (title == "Explore Premium") {
      headerIcon = Icons.sports_cricket_rounded;
      headerAccent = CrickXColors.limeSpark;
    } else if (title == "Support & Rating") {
      headerIcon = Icons.star_outline_rounded;
      headerAccent = CrickXColors.limeSpark;
    } else if (title == "Legal & App Information") {
      headerIcon = Icons.shield_outlined;
      headerAccent = CrickXColors.limeSpark;
    } else if (title == "Account") {
      headerIcon = Icons.manage_accounts_outlined;
      headerAccent = const Color(0xFFEF4444);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CrickXColors.graphite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: CrickXColors.graphiteBorder,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: CrickXColors.graphiteElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: CrickXColors.graphiteBorder,
                      width: 1.1,
                    ),
                  ),
                  child: Icon(
                    headerIcon,
                    size: 19,
                    color: headerAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 1,
              width: double.infinity,
              color: CrickXColors.graphiteBorder,
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }

  InputDecoration inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: CrickXColors.graphiteElevated,
      labelStyle: GoogleFonts.poppins(color: CrickXColors.textMuted, fontSize: 13),
      floatingLabelStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
      hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CrickXColors.limeSpark, width: 1.2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
      ),
    );
  }

  Widget elevatedButton(String text, Function onTap, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? CrickXColors.limeSpark,
          foregroundColor: color != null ? Colors.white : CrickXColors.onLime,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () => onTap(),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    final displayChar = (_savedName.trim().isNotEmpty &&
            _savedName.trim().toLowerCase() != 'player')
        ? _savedName.trim()[0].toUpperCase()
        : (userEmail != null && userEmail!.trim().isNotEmpty)
            ? userEmail!.trim()[0].toUpperCase()
            : null;

    if (displayChar != null) {
      return Container(
        width: 140,
        height: 140,
        color: const Color(0xFF1B1D25),
        alignment: Alignment.center,
        child: Text(
          displayChar,
          style: GoogleFonts.poppins(
            color: CrickXColors.limeSpark,
            fontWeight: FontWeight.w700,
            fontSize: 48,
          ),
        ),
      );
    }
    return Container(
      width: 140,
      height: 140,
      color: const Color(0xFF1B1D25),
      child: const Icon(
        Icons.person,
        size: 76,
        color: Colors.white54,
      ),
    );
  }

  Widget _supportStarIcon() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CrickXColors.graphiteElevated,
        border: Border.all(
          color: CrickXColors.limeSpark.withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: CrickXColors.limeSpark.withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            colors: [CrickXColors.limeSpark, CrickXColors.limeSparkDim],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds);
        },
        child: const Icon(Icons.stars_rounded, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _supportBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: CrickXColors.limeSpark.withValues(alpha: 0.15),
        border: Border.all(
          color: CrickXColors.limeSpark.withValues(alpha: 0.4),
          width: 1.0,
        ),
      ),
      child: Text(
        "Help us grow",
        style: GoogleFonts.poppins(
          color: CrickXColors.limeSpark,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _ratingStarsRow({
    required int rating,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isFilled = starValue <= rating;
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(starValue),
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              isFilled ? Icons.star_rounded : Icons.star_border_rounded,
              color: isFilled ? CrickXColors.limeSpark : CrickXColors.textMuted,
              size: 22,
            ),
          ),
        );
      }),
    );
  }

  Widget socialButton(IconData icon, String text, Function onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 24, color: Colors.white70),
      title: Text(
        text,
        style: GoogleFonts.poppins(fontSize: 14, color: Colors.white),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: Color(0xFF71717A),
      ),
      onTap: () => onTap(),
    );
  }

  void showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Color(0xFF23232A), width: 1.2),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF27272E),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF27272E)),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    "Upload from Gallery",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Color(0xFF71717A),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? picked = await _picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (picked != null) {
                      final uid =
                          FirebaseAuth.instance.currentUser?.uid ?? "guest";
                      final box = await _getStatsBox(uid);
                      await box.put("profileImagePath", picked.path);
                      setState(() {
                        profileImage = File(picked.path);
                      });
                    }
                  },
                ),
                const Divider(color: Color(0xFF23232A), height: 12),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF27272E)),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    "Open Camera",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Color(0xFF71717A),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? picked = await _picker.pickImage(
                      source: ImageSource.camera,
                    );
                    if (picked != null) {
                      final uid =
                          FirebaseAuth.instance.currentUser?.uid ?? "guest";
                      final box = await _getStatsBox(uid);
                      await box.put("profileImagePath", picked.path);
                      setState(() {
                        profileImage = File(picked.path);
                      });
                    }
                  },
                ),
                if (profileImage != null) ...[
                  const Divider(color: Color(0xFF23232A), height: 12),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF27272E)),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFEF4444),
                        size: 18,
                      ),
                    ),
                    title: Text(
                      "Remove Profile Photo",
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFEF4444),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Color(0xFFEF4444),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      final uid =
                          FirebaseAuth.instance.currentUser?.uid ?? "guest";
                      final box = await _getStatsBox(uid);
                      await box.delete("profileImagePath");
                      setState(() {
                        profileImage = null;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metallicShimmerProgressBar({
    required double progress,
    required Color color,
  }) {
    return Container(
      height: 10,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF27272E), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      CrickXColors.limeSpark,
                      color,
                      CrickXColors.limeSparkDim,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _xpShimmerController,
              builder: (context, _) {
                final t = _xpShimmerController.value;
                return FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: ShaderMask(
                    blendMode: BlendMode.lighten,
                    shaderCallback: (rect) {
                      final start = (t - 0.12).clamp(0.0, 1.0);
                      final mid = t.clamp(0.0, 1.0);
                      final end = (t + 0.12).clamp(0.0, 1.0);
                      return LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: const [
                          Color(0x00FFFFFF),
                          Color(0x55FFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: [start, mid, end],
                      ).createShader(rect);
                    },
                    child: Container(color: Colors.white),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _levelGlowColor(int xp) {
    if (xp >= 25000) {
      return CrickXColors.limeSpark; // Elite Spark
    }
    return const Color(0xFFE2E8F0); // Sleek Platinum
  }

  String _getLevelTitle(int xp) {
    if (xp >= 2000000) return "Level 12: Immortal Master";
    if (xp >= 1500000) return "Level 11: World Dominator";
    if (xp >= 1000000) return "Level 10: Grand Champion";
    if (xp >= 750000) return "Level 9: Supreme Legend";
    if (xp >= 500000) return "Level 8: Master Blaster";
    if (xp >= 250000) return "Level 7: Elite Warrior";
    if (xp >= 50000) return "Level 6: Legendary";
    if (xp >= 25000) return "Level 5: Elite Player";
    if (xp >= 15000) return "Level 4: Rising Star";
    if (xp >= 8000) return "Level 3: Competitor";
    if (xp >= 3000) return "Level 2: Developing";
    return "Level 1: Beginner";
  }
}

class _PremiumFeature {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;

  const _PremiumFeature({
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
  });
}

class _PremiumBrochureSheet extends StatefulWidget {
  final VoidCallback onUpgrade;

  const _PremiumBrochureSheet({required this.onUpgrade});

  @override
  State<_PremiumBrochureSheet> createState() => _PremiumBrochureSheetState();
}

class _PremiumBrochureSheetState extends State<_PremiumBrochureSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  final List<_PremiumFeature> _features = const [
    _PremiumFeature(
      icon: Icons.block_rounded,
      title: "100% Ad-Free Experience",
      description: "Zero ads across all premium tiers.",
      badge: "ALL PLANS",
    ),
    _PremiumFeature(
      icon: Icons.flash_on_rounded,
      title: "Power Speed",
      description: "Physics-based KMPH tracking.",
    ),
    _PremiumFeature(
      icon: Icons.blur_circular_rounded,
      title: "Swing & Spin Mastery",
      description: "Inswing, Outswing, and spin revolutions.",
    ),
    _PremiumFeature(
      icon: Icons.auto_awesome_rounded,
      title: "CricX Coach",
      description: "Your personal cricket consultant.",
      badge: "ELITE",
    ),
    _PremiumFeature(
      icon: Icons.gavel_rounded,
      title: "DRS Call",
      description: "Elite-level ball trajectory simulation.",
      badge: "PRO",
    ),
    _PremiumFeature(
      icon: Icons.video_library_rounded,
      title: "Pro Video Compare",
      description: "Side-by-side comparison overlays.",
    ),
    _PremiumFeature(
      icon: Icons.insights_rounded,
      title: "Elite Growth Dashboard",
      description: "Graphs, power levels, and trends.",
    ),
    _PremiumFeature(
      icon: Icons.psychology_alt_rounded,
      title: "CricX Mistake Detection (Batting/Bowling)",
      description: "Instant batting & bowling flaw checks.",
    ),
    _PremiumFeature(
      icon: Icons.support_agent_rounded,
      title: "Direct Coach Access",
      description: "One-click WhatsApp support.",
    ),
    _PremiumFeature(
      icon: Icons.picture_as_pdf_rounded,
      title: "PDF Performance Reports",
      description: "Weekly progress reports.",
    ),
    _PremiumFeature(
      icon: Icons.rocket_launch_rounded,
      title: "Priority Processing",
      description: "2x faster Elite servers.",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 720 ? 3 : 2;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: CrickXColors.graphiteBg,
              gradient: RadialGradient(
                colors: [CrickXColors.graphiteElevated, CrickXColors.graphiteBg],
                radius: 1.3,
                center: Alignment(0.0, -0.2),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _PremiumMeshPainter())),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Column(
                    children: [
                      Text(
                        "Premium Benefits",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Unlock the full CricX Elite experience",
                        style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _GlowDivider(),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: _features.length,
                  itemBuilder: (context, index) {
                    final feature = _features[index];
                    return _PremiumFeatureTile(feature: feature, index: index);
                  },
                ),
                const SizedBox(height: 18),
                const _GlowDivider(),
                const SizedBox(height: 18),
                _ShimmerCtaButton(
                  controller: _shimmerController,
                  onTap: widget.onUpgrade,
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Close",
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _PremiumMeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CrickXColors.limeSpark.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    const spacing = 36.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }

    final overlay = Paint()
      ..color = CrickXColors.limeSpark.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width + size.height; x += spacing * 1.3) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        overlay,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumMeshPainter oldDelegate) => false;
}

class _GlowDivider extends StatelessWidget {
  const _GlowDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: const BoxDecoration(
        color: CrickXColors.graphiteBorder,
      ),
    );
  }
}

class _PremiumFeatureTile extends StatelessWidget {
  final _PremiumFeature feature;
  final int index;

  const _PremiumFeatureTile({required this.feature, required this.index});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CrickXColors.graphite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CrickXColors.graphiteBorder,
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GradientIcon(icon: feature.icon),
                  const SizedBox(height: 10),
                  Text(
                    feature.title,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    feature.description,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFA1A1AA),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              if (feature.badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: CrickXColors.limeSpark,
                      boxShadow: [
                        BoxShadow(
                          color: CrickXColors.limeSpark.withValues(alpha: 0.3),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      feature.badge!,
                      style: GoogleFonts.poppins(
                        color: CrickXColors.onLime,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
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

class _GradientIcon extends StatelessWidget {
  final IconData icon;

  const _GradientIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CrickXColors.graphiteElevated,
        border: Border.all(
          color: CrickXColors.graphiteBorder,
          width: 1,
        ),
      ),
      child: ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            colors: [CrickXColors.limeSpark, CrickXColors.limeSparkDim],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds);
        },
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ShimmerCtaButton extends StatelessWidget {
  final AnimationController controller;
  final VoidCallback onTap;

  const _ShimmerCtaButton({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Container(
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [CrickXColors.limeSpark, CrickXColors.limeSparkDim],
                ),
                boxShadow: [
                  BoxShadow(
                    color: CrickXColors.limeSpark.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                "Unlock Elite Perks",
                style: GoogleFonts.poppins(
                  color: CrickXColors.onLime,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return FractionallySizedBox(
                    widthFactor: 0.35,
                    alignment: Alignment(-1 + (2 * controller.value), 0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  int totalXP = 0;

  bool jerseyClaimed = false;
  DateTime? claimDate;
  int xpAtClaim = 0;

  @override
  void initState() {
    super.initState();
    _loadXP();
  }

  Future<void> _loadXP() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    if (uid == "guest") return;

    final box = await Hive.openBox("local_stats_$uid");
    final xp = box.get("xp", defaultValue: 0);
    final claimMillis = box.get("claimDateMillis");
    final claimed50 = box.get("claimed_50000", defaultValue: false);
    final claimed5L = box.get("claimed_500000", defaultValue: false);
    final claimed10L = box.get("claimed_1000000", defaultValue: false);
    final claimed20L = box.get("claimed_2000000", defaultValue: false);

    DateTime? savedClaimDate;
    if (claimMillis != null) {
      savedClaimDate = DateTime.fromMillisecondsSinceEpoch(claimMillis);
    }

    setState(() {
      totalXP = xp;
      xpAtClaim = box.get("xpAtClaim", defaultValue: 0);
      claimDate = savedClaimDate;
      jerseyClaimed = claimed50;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isEligible(int threshold) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
      if (uid == "guest") return false;
      final box = Hive.box("local_stats_$uid");

      final alreadyClaimed = box.get("claimed_$threshold", defaultValue: false);
      if (alreadyClaimed) return false;

      return totalXP >= threshold;
    }

    int extraXPFor(int threshold) {
      return totalXP > threshold ? (totalXP - threshold) : 0;
    }

    return Scaffold(
      backgroundColor: CrickXColors.graphiteBg,
      appBar: AppBar(
        backgroundColor: CrickXColors.graphiteBg,
        title: Text(
          "Rewards & Milestones",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _rewardCard(
              title: "Official CricX Jersey",
              description:
                  "Unlock at 50,000 XP milestone. Includes Official Jersey + Special Gift.",
              threshold: 50000,
              eligible: isEligible(50000),
              extraXP: extraXPFor(50000),
              gradientColors: const [CrickXColors.limeSpark, CrickXColors.limeSparkDim],
              icon: Icons.workspace_premium,
            ),
            const SizedBox(height: 16),
            _rewardCard(
              title: "Batting Gloves + Special Gift",
              description: "Unlock at 5 Lakh XP milestone.",
              threshold: 500000,
              eligible: isEligible(500000),
              extraXP: extraXPFor(500000),
              gradientColors: const [CrickXColors.limeSpark, CrickXColors.limeSparkDim],
              icon: Icons.sports_cricket,
            ),
            const SizedBox(height: 16),
            _rewardCard(
              title: "Full Cricket Kit + Special Gift",
              description: "Unlock at 10 Lakh XP milestone.",
              threshold: 1000000,
              eligible: isEligible(1000000),
              extraXP: extraXPFor(1000000),
              gradientColors: const [CrickXColors.limeSpark, CrickXColors.limeSparkDim],
              icon: Icons.inventory,
            ),
            const SizedBox(height: 16),
            _rewardCard(
              title: "English Willow Bat + Special Gift",
              description:
                  "Unlock at 20 Lakh XP milestone. Delivered in 30–45 days.",
              threshold: 2000000,
              eligible: isEligible(2000000),
              extraXP: extraXPFor(2000000),
              gradientColors: const [CrickXColors.limeSpark, CrickXColors.limeSparkDim],
              icon: Icons.emoji_events,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardCard({
    required String title,
    required String description,
    required int threshold,
    required bool eligible,
    required int extraXP,
    required List<Color> gradientColors,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: eligible ? null : CrickXColors.graphite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: eligible ? Colors.transparent : CrickXColors.graphiteBorder,
          width: 1.2,
        ),
        gradient: eligible
            ? LinearGradient(colors: gradientColors)
            : null,
        boxShadow: [
          if (eligible)
            BoxShadow(
              color: gradientColors.first.withOpacity(0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            )
          else
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: eligible
                      ? Colors.black.withOpacity(0.12)
                      : CrickXColors.graphiteElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: eligible
                        ? Colors.black.withOpacity(0.15)
                        : CrickXColors.graphiteBorder,
                  ),
                ),
                child: Icon(
                  icon,
                  color: eligible ? CrickXColors.onLime : CrickXColors.limeSpark,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: eligible ? CrickXColors.onLime : Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            eligible
                ? (extraXP > 0
                      ? "Unlocked! You have $extraXP XP above $threshold."
                      : "Congratulations! You unlocked this reward.")
                : description,
            style: GoogleFonts.poppins(
              color: eligible ? CrickXColors.onLime : const Color(0xFFA1A1AA),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          // Delivery status indicator
          if (jerseyClaimed && claimDate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Builder(
                builder: (_) {
                  final daysPassed = DateTime.now()
                      .difference(claimDate!)
                      .inDays;
                  final daysRemaining = 30 - daysPassed;
                  final safeRemaining = daysRemaining < 0 ? 0 : daysRemaining;

                  return Text(
                    safeRemaining > 0
                        ? "📦 Order received. Delivering in $safeRemaining days"
                        : "🎉 Delivered Successfully",
                    style: GoogleFonts.poppins(
                      color: CrickXColors.limeSpark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  );
                },
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: eligible
                  ? () {
                      showClaimBottomSheet(context, title, threshold);
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: eligible ? CrickXColors.onLime : CrickXColors.graphiteElevated,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: eligible ? Colors.transparent : CrickXColors.graphiteBorder,
                  ),
                ),
                child: Text(
                  eligible ? "Claim Now" : "Locked",
                  style: GoogleFonts.poppins(
                    color: eligible ? CrickXColors.limeSpark : CrickXColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showClaimBottomSheet(
    BuildContext context,
    String rewardTitle,
    int threshold,
  ) {
    final rewardsContext = context;
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final pincodeController = TextEditingController();
    final houseController = TextEditingController();
    final roadController = TextEditingController();
    final landmarkController = TextEditingController();
    final cityStateController = TextEditingController();
    String selectedCountryCode = "+91";
    String selectedSize = "M";
    String selectedGlovesSize = "Men";
    String selectedPadsSize = "Men";
    String selectedHelmetSize = "Men";
    String selectedBatCompany = "SS";
    String selectedBatWeight = "Medium (1130–1200g)";
    String selectedBatSize = "SH";
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: CrickXColors.graphite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: CrickXColors.limeSpark.withValues(alpha: 0.3)),
                                ),
                                child: const Icon(
                                  Icons.workspace_premium,
                                  color: CrickXColors.limeSpark,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Claim Your Official Jersey",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        _premiumField(
                          controller: nameController,
                          label: "Full Name",
                          icon: Icons.person,
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Visibility(
                              visible: false,
                              maintainState: true,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    dropdownColor: const Color(0xFF141418),
                                    value: selectedCountryCode,
                                    style: GoogleFonts.poppins(color: Colors.white),
                                    items:
                                        const [
                                          "+1",
                                          "+7",
                                          "+20",
                                          "+27",
                                          "+30",
                                          "+31",
                                          "+32",
                                          "+33",
                                          "+34",
                                          "+36",
                                          "+39",
                                          "+40",
                                          "+41",
                                          "+43",
                                          "+44",
                                          "+45",
                                          "+46",
                                          "+47",
                                          "+48",
                                          "+49",
                                          "+51",
                                          "+52",
                                          "+53",
                                          "+54",
                                          "+55",
                                          "+56",
                                          "+57",
                                          "+58",
                                          "+60",
                                          "+61",
                                          "+62",
                                          "+63",
                                          "+64",
                                          "+65",
                                          "+66",
                                          "+81",
                                          "+82",
                                          "+84",
                                          "+86",
                                          "+90",
                                          "+91",
                                          "+93",
                                          "+94",
                                          "+95",
                                          "+98",
                                          "+211",
                                          "+212",
                                          "+213",
                                          "+216",
                                          "+218",
                                          "+220",
                                          "+221",
                                          "+222",
                                          "+223",
                                          "+224",
                                          "+225",
                                          "+226",
                                          "+227",
                                          "+228",
                                          "+229",
                                          "+230",
                                          "+231",
                                          "+232",
                                          "+233",
                                          "+234",
                                          "+235",
                                          "+236",
                                          "+237",
                                          "+238",
                                          "+239",
                                          "+240",
                                          "+241",
                                          "+242",
                                          "+243",
                                          "+244",
                                          "+245",
                                          "+246",
                                          "+248",
                                          "+249",
                                          "+250",
                                          "+251",
                                          "+252",
                                          "+253",
                                          "+254",
                                          "+255",
                                          "+256",
                                          "+257",
                                          "+258",
                                          "+260",
                                          "+261",
                                          "+262",
                                          "+263",
                                          "+264",
                                          "+265",
                                          "+266",
                                          "+267",
                                          "+268",
                                          "+269",
                                          "+290",
                                          "+291",
                                          "+297",
                                          "+298",
                                          "+299",
                                          "+350",
                                          "+351",
                                          "+352",
                                          "+353",
                                          "+354",
                                          "+355",
                                          "+356",
                                          "+357",
                                          "+358",
                                          "+359",
                                          "+370",
                                          "+371",
                                          "+372",
                                          "+373",
                                          "+374",
                                          "+375",
                                          "+376",
                                          "+377",
                                          "+378",
                                          "+380",
                                          "+381",
                                          "+382",
                                          "+383",
                                          "+385",
                                          "+386",
                                          "+387",
                                          "+389",
                                          "+420",
                                          "+421",
                                          "+423",
                                          "+500",
                                          "+501",
                                          "+502",
                                          "+503",
                                          "+504",
                                          "+505",
                                          "+506",
                                          "+507",
                                          "+508",
                                          "+509",
                                          "+590",
                                          "+591",
                                          "+592",
                                          "+593",
                                          "+594",
                                          "+595",
                                          "+596",
                                          "+597",
                                          "+598",
                                          "+599",
                                          "+670",
                                          "+672",
                                          "+673",
                                          "+674",
                                          "+675",
                                          "+676",
                                          "+677",
                                          "+678",
                                          "+679",
                                          "+680",
                                          "+681",
                                          "+682",
                                          "+683",
                                          "+685",
                                          "+686",
                                          "+687",
                                          "+688",
                                          "+689",
                                          "+690",
                                          "+691",
                                          "+692",
                                          "+850",
                                          "+852",
                                          "+853",
                                          "+855",
                                          "+856",
                                          "+880",
                                          "+886",
                                          "+960",
                                          "+961",
                                          "+962",
                                          "+963",
                                          "+964",
                                          "+965",
                                          "+966",
                                          "+967",
                                          "+968",
                                          "+970",
                                          "+971",
                                          "+972",
                                          "+973",
                                          "+974",
                                          "+975",
                                          "+976",
                                          "+977",
                                          "+992",
                                          "+993",
                                          "+994",
                                          "+995",
                                          "+996",
                                          "+998",
                                        ].map((code) {
                                          return DropdownMenuItem(
                                            value: code,
                                            child: Text(code),
                                          );
                                        }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        selectedCountryCode = value!;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox.shrink(),
                             Expanded(
                              child: TextFormField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.phone,
                                    color: CrickXColors.limeSpark,
                                  ),
                                  labelText:
                                      "Mobile Number (with country code)",
                                  labelStyle: GoogleFonts.poppins(
                                    color: const Color(0xFFA1A1AA),
                                    fontSize: 13,
                                  ),
                                  helperText: "Example: +91XXXXXXXXXX",
                                  helperStyle: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                  filled: true,
                                  fillColor: CrickXColors.graphiteBg,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: CrickXColors.limeSpark, width: 1.2),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
                                  ),
                                ),
                                validator: (value) {
                                  final raw = (value ?? "").trim();
                                  if (raw.isEmpty) {
                                    return "Contact number required";
                                  }
                                  if (!raw.startsWith("+")) {
                                    return "Add country code (example: +91)";
                                  }
                                  final normalized =
                                      "+${raw.substring(1).replaceAll(RegExp(r'\\D'), '')}";
                                  if (normalized.length < 8) {
                                    return "Enter valid number";
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: pincodeController,
                          label: "Pincode",
                          icon: Icons.pin,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: houseController,
                          label: "Flat, House no., Building",
                          icon: Icons.home,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: roadController,
                          label: "Area, Colony, Street, Sector",
                          icon: Icons.map,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: landmarkController,
                          label: "Landmark",
                          icon: Icons.place,
                        ),
                        const SizedBox(height: 16),

                        _premiumField(
                          controller: cityStateController,
                          label: "City / State",
                          icon: Icons.location_city,
                        ),

                        // Jersey Size ONLY for 50K
                        if (threshold == 50000) ...[
                          const SizedBox(height: 20),
                          Text(
                            "Select Jersey Size",
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFA1A1AA),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children:
                                [
                                  "S",
                                  "M",
                                  "L",
                                  "XL",
                                  "XXL",
                                  "2XL",
                                  "3XL",
                                  "4XL",
                                ].map((size) {
                                  final bool isSelected = selectedSize == size;
                                  return ChoiceChip(
                                    label: Text(size),
                                    selected: isSelected,
                                    selectedColor: CrickXColors.limeSpark,
                                    backgroundColor: const Color(0xFF141418),
                                    side: BorderSide(
                                      color: isSelected
                                          ? CrickXColors.limeSpark
                                          : const Color(0xFF23232A),
                                    ),
                                    labelStyle: GoogleFonts.poppins(
                                      color: isSelected
                                          ? CrickXColors.onLime
                                          : Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onSelected: (_) {
                                      setState(() {
                                        selectedSize = size;
                                      });
                                    },
                                  );
                                }).toList(),
                          ),
                        ],

                        // Gloves Size for 5 Lakh
                        if (threshold == 500000) ...[
                          const SizedBox(height: 20),
                          Text(
                            "Select Gloves Size",
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFA1A1AA),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children: ["Small", "Youth", "Men"].map((size) {
                              final bool isSelected =
                                  selectedGlovesSize == size;
                              return ChoiceChip(
                                label: Text(size),
                                selected: isSelected,
                                selectedColor: CrickXColors.limeSpark,
                                backgroundColor: const Color(0xFF141418),
                                side: BorderSide(
                                  color: isSelected
                                      ? CrickXColors.limeSpark
                                      : const Color(0xFF23232A),
                                ),
                                labelStyle: GoogleFonts.poppins(
                                  color: isSelected
                                      ? CrickXColors.onLime
                                      : Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    selectedGlovesSize = size;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],

                        // Kit Equipment Sizes for 10 Lakh
                        if (threshold == 1000000) ...[
                          const SizedBox(height: 20),
                          Text(
                            "Cricket Kit Sizes",
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFA1A1AA),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _kitDropdown(
                            label: "Batting Pads Size",
                            value: selectedPadsSize,
                            options: ["Small", "Youth", "Men"],
                            onChanged: (val) =>
                                setState(() => selectedPadsSize = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Batting Gloves Size",
                            value: selectedGlovesSize,
                            options: ["Small", "Youth", "Men"],
                            onChanged: (val) =>
                                setState(() => selectedGlovesSize = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Helmet Size",
                            value: selectedHelmetSize,
                            options: ["Small", "Youth", "Men"],
                            onChanged: (val) =>
                                setState(() => selectedHelmetSize = val),
                          ),
                        ],

                        // Bat Options for 20 Lakh
                        if (threshold == 2000000) ...[
                          const SizedBox(height: 20),
                          Text(
                            "Bat Preferences",
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFA1A1AA),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Delivered in 30–45 days",
                            style: GoogleFonts.poppins(
                              color: Colors.white54,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _kitDropdown(
                            label: "Bat Company",
                            value: selectedBatCompany,
                            options: ["SS", "SG", "MRF", "GM", "Kookaburra"],
                            onChanged: (val) =>
                                setState(() => selectedBatCompany = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Bat Weight",
                            value: selectedBatWeight,
                            options: [
                              "Light (1080–1120g)",
                              "Medium (1130–1200g)",
                              "Heavy (1200g+)",
                            ],
                            onChanged: (val) =>
                                setState(() => selectedBatWeight = val),
                          ),
                          const SizedBox(height: 12),
                          _kitDropdown(
                            label: "Bat Size",
                            value: selectedBatSize,
                            options: ["SH", "LH"],
                            onChanged: (val) =>
                                setState(() => selectedBatSize = val),
                          ),
                        ],

                        const SizedBox(height: 30),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CrickXColors.limeSpark,
                              foregroundColor: CrickXColors.onLime,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                final orderSummary =
                                    '''
Reward: $rewardTitle
${threshold == 50000 ? "Jersey Size: $selectedSize" : ""}
${threshold == 500000 ? "Gloves Size: $selectedGlovesSize" : ""}
${threshold == 1000000 ? "Pads: $selectedPadsSize\nGloves: $selectedGlovesSize\nHelmet: $selectedHelmetSize" : ""}
${threshold == 2000000 ? "Bat Company: $selectedBatCompany\nBat Weight: $selectedBatWeight\nBat Size: $selectedBatSize" : ""}

Full Name: ${nameController.text}
Phone: ${phoneController.text}

Address:
Pincode: ${pincodeController.text}
House/Building: ${houseController.text}
Road/Area: ${roadController.text}
Landmark: ${landmarkController.text}
City/State: ${cityStateController.text}

Total XP: $totalXP
''';

                                final subject = "CricX Jersey Order";

                                final Uri emailUri = Uri.parse(
                                  'mailto:urmiladukare0@gmail.com'
                                  '?subject=${Uri.encodeComponent(subject)}'
                                  '&body=${Uri.encodeComponent(orderSummary)}',
                                );

                                if (await canLaunchUrl(emailUri)) {
                                  await launchUrl(emailUri);
                                }

                                if (!mounted) return;

                                final uid =
                                    FirebaseAuth.instance.currentUser?.uid ??
                                    "guest";
                                final box = await Hive.openBox(
                                  "local_stats_$uid",
                                );

                                final currentXP =
                                    box.get("xp", defaultValue: 0) as int;
                                final now = DateTime.now();

                                final isJersey = threshold == 50000;
                                if (isJersey) {
                                  // Do NOT reset XP. Keep cumulative progress.
                                  await box.put("xpAtClaim", currentXP);
                                  await box.put(
                                    "claimDateMillis",
                                    now.millisecondsSinceEpoch,
                                  );
                                }
                                await box.put("claimed_$threshold", true);
                                await box.flush();

                                if (mounted) {
                                  this.setState(() {
                                    if (isJersey) {
                                      jerseyClaimed = true;
                                      claimDate = now;
                                      xpAtClaim = currentXP;
                                    }
                                    totalXP = currentXP;
                                  });
                                }

                                Navigator.pop(context);

                                await showDialog(
                                  context: rewardsContext,
                                  barrierDismissible: false,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: CrickXColors.graphiteBg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(22),
                                      side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
                                    ),
                                    title: Text(
                                      "🎉 Milestone Unlocked!",
                                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.celebration,
                                          color: CrickXColors.limeSpark,
                                          size: 56,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          "Reward claimed successfully!\nKeep climbing to the next milestone 🚀",
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFFA1A1AA),
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(rewardsContext),
                                        child: Text(
                                          "OK",
                                          style: GoogleFonts.poppins(
                                            color: CrickXColors.limeSpark,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (!mounted) return;
                                Navigator.of(rewardsContext).pop();
                              }
                            },
                            child: Text(
                              "Submit",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: CrickXColors.onLime,
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
          },
        );
      },
    );
  }

  Widget _premiumField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: CrickXColors.limeSpark),
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: const Color(0xFFA1A1AA), fontSize: 13),
        filled: true,
        fillColor: CrickXColors.graphiteElevated,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CrickXColors.limeSpark, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return "This field is required";
        }
        return null;
      },
    );
  }
}

Widget _kitDropdown({
  required String label,
  required String value,
  required List<String> options,
  required Function(String) onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.poppins(color: const Color(0xFFA1A1AA), fontSize: 13),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: CrickXColors.graphiteElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            dropdownColor: CrickXColors.graphiteElevated,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
            isExpanded: true,
            items: options
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) {
              if (val != null) onChanged(val);
            },
          ),
        ),
      ),
    ],
  );
}
