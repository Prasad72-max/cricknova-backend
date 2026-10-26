import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../home/home_screen.dart';
import '../ai/ai_coach_screen.dart';
import '../profile/profile_screen.dart';
import '../services/premium_service.dart';
import '../services/weekly_stats_service.dart';
import '../services/app_analytics.dart';
import 'dart:async';
import 'dart:math' as math;
import '../insights/insights_screen.dart';
import '../premium/premium_screen.dart';
import '../live/live_nets_tab.dart';
import '../onboarding/onboarding_ui_tokens.dart';
import '../reels/screens/reels_screen.dart';
import '../theme/crickx_colors.dart';

abstract class MainNavigationController {
  void setTab(int index);
  void goHome();
}

class _CrickNovaEdgeIntroScreen extends StatefulWidget {
  const _CrickNovaEdgeIntroScreen();

  @override
  State<_CrickNovaEdgeIntroScreen> createState() =>
      _CrickNovaEdgeIntroScreenState();
}

class _CrickNovaEdgeIntroScreenState extends State<_CrickNovaEdgeIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset? _pointer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const spaceAccent = CrickXColors.limeSpark;
    const spaceAccentSoft = Color(0xFFE2FFA6);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            setState(() => _pointer = details.localPosition),
        onPanDown: (details) =>
            setState(() => _pointer = details.localPosition),
        onPanUpdate: (details) =>
            setState(() => _pointer = details.localPosition),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final spin = _controller.value;
            return Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF040405), Color(0xFF000000)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _EdgeIntroBackdropPainter(
                        progress: spin,
                        pointer: _pointer,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close_rounded),
                            color: OnboardingColors.textSecondary,
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                math.sin(spin * math.pi * 2) * 8,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Transform.rotate(
                                    angle: spin * math.pi * 2,
                                    child: Container(
                                      width: 218,
                                      height: 218,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: spaceAccent.withValues(
                                            alpha: 0.28,
                                          ),
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: spaceAccent.withValues(
                                              alpha: 0.12,
                                            ),
                                            blurRadius: 44,
                                            spreadRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 144,
                                    height: 144,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const RadialGradient(
                                        center: Alignment(-0.35, -0.45),
                                        colors: [
                                          Color(0xFFEFF7FF),
                                          Color(0xFF2F7AA8),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.15,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(4, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.sports_cricket_rounded,
                                      color: Colors.black,
                                      size: 58,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: spaceAccent.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: spaceAccent.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            'LIVE AI NET COACHING',
                            style: OnboardingTextStyles.uiMono(
                              color: spaceAccentSoft,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Meet CrickNova Edge',
                          textAlign: TextAlign.center,
                          style: OnboardingTextStyles.serif(
                            color: OnboardingColors.textPrimary,
                            fontSize: 34,
                            height: 1.1,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        const SizedBox(height: 11),
                        Text(
                          'Train while CrickX watches. Get live coaching feedback without stopping your net session.',
                          textAlign: TextAlign.center,
                          style: OnboardingTextStyles.uiSans(
                            color: OnboardingColors.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _EdgeBenefitChip(
                              icon: Icons.videocam_rounded,
                              label: '10-sec clip reviews',
                            ),
                            _EdgeBenefitChip(
                              icon: Icons.record_voice_over_rounded,
                              label: 'Coach voice',
                            ),
                            _EdgeBenefitChip(
                              icon: Icons.closed_caption_rounded,
                              label: 'Captions + saved reviews',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OnboardingColors.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Go Edge',
                              style: OnboardingTextStyles.uiSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            'Continue without Edge',
                            style: OnboardingTextStyles.uiSans(
                              color: OnboardingColors.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EdgeBenefitChip extends StatelessWidget {
  const _EdgeBenefitChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: OnboardingColors.bgSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: OnboardingColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: OnboardingColors.accent, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: OnboardingTextStyles.uiSans(
              color: OnboardingColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeIntroBackdropPainter extends CustomPainter {
  const _EdgeIntroBackdropPainter({
    required this.progress,
    required this.pointer,
  });

  final double progress;
  final Offset? pointer;

  @override
  void paint(Canvas canvas, Size size) {
    const spaceAccent = CrickXColors.limeSpark;
    final baseCenter = Offset(size.width / 2, size.height * 0.34);
    final pointerShift = pointer == null
        ? Offset.zero
        : Offset(
            (pointer!.dx - size.width / 2) * 0.10,
            (pointer!.dy - size.height / 2) * 0.08,
          );
    final center = baseCenter + pointerShift;
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              spaceAccent.withValues(alpha: 0.10),
              spaceAccent.withValues(alpha: 0.02),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.longestSide * 0.92),
          );
    canvas.drawCircle(center, size.longestSide * 0.92, glow);

    final lowerGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [Colors.white.withValues(alpha: 0.03), Colors.transparent],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.62, size.height * 0.78),
              radius: size.longestSide * 0.58,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.62, size.height * 0.78),
      size.longestSide * 0.58,
      lowerGlow,
    );

    final starPaint = Paint()..style = PaintingStyle.fill;
    const stars = <Offset>[
      Offset(0.12, 0.16),
      Offset(0.24, 0.28),
      Offset(0.38, 0.12),
      Offset(0.52, 0.22),
      Offset(0.68, 0.14),
      Offset(0.82, 0.26),
      Offset(0.18, 0.62),
      Offset(0.34, 0.78),
      Offset(0.56, 0.66),
      Offset(0.74, 0.84),
      Offset(0.88, 0.58),
      Offset(0.46, 0.48),
      Offset(0.08, 0.44),
      Offset(0.30, 0.40),
      Offset(0.60, 0.42),
      Offset(0.92, 0.40),
    ];
    for (int i = 0; i < stars.length; i++) {
      final s = stars[i];
      final twinkle =
          0.22 + 0.12 * (math.sin(progress * 0.8 + i * 0.5) * 0.5 + 0.5);
      starPaint.color = Colors.white.withValues(alpha: twinkle);
      canvas.drawCircle(
        Offset(size.width * s.dx, size.height * s.dy) + pointerShift,
        i.isEven ? 1.2 : 0.9,
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeIntroBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pointer != pointer;
  }
}

class MainNavigation extends StatefulWidget {
  final String userName;
  final int initialIndex;
  static final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<String> userNameNotifier = ValueNotifier<String>(
    'Player',
  );

  const MainNavigation({
    super.key,
    required this.userName,
    this.initialIndex = 0,
  });

  static MainNavigationController? of(BuildContext context) {
    return context.findAncestorStateOfType<_MainNavigationState>();
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver
    implements MainNavigationController {
  int _index = 0;
  String userName = "Player";
  late List<Widget?> _screenCache;
  late bool _lastPremiumActive;
  late String _lastBillingState;
  late SubscriptionAccessState _lastAccessState;
  late int _lastKnownTabCount;
  DateTime? _activeSince;
  Timer? _minuteTimer;
  bool _edgeIntroChecked = false;
  bool _isEdgeIntroOpen = false;

  @override
  void goHome() {
    if (_index != 0) {
      setState(() {
        _index = 0;
      });
      MainNavigation.activeTabNotifier.value = _index;
    }
  }

  @override
  void setTab(int index) {
    if (!mounted) return;
    if (index < 0 || index >= _screenCache.length) return;
    setState(() {
      _screenCache[index] ??= _buildScreenAt(index);
      _index = index;
    });
    MainNavigation.activeTabNotifier.value = _index;
    unawaited(AppAnalytics.logScreenOpen(_screenNameForIndex(_index)));
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    userName = widget.userName.trim().isEmpty
        ? "Player"
        : widget.userName.trim();
    WidgetsBinding.instance.addObserver(this);
    PremiumService.premiumNotifier.addListener(_handlePremiumStateChanged);
    MainNavigation.userNameNotifier.value = widget.userName;
    MainNavigation.userNameNotifier.addListener(_handleUserNameChanged);
    _lastPremiumActive = PremiumService.isPremiumActive;
    _lastBillingState = PremiumService.billingState;
    _lastAccessState = PremiumService.accessState;
    _lastKnownTabCount = _tabCount();
    if (_index >= _lastKnownTabCount) {
      _index = _lastKnownTabCount - 1;
    }
    _activeSince = DateTime.now();
    _startMinuteTimer();

    _screenCache = _buildScreenCache(_lastKnownTabCount);

    MainNavigation.activeTabNotifier.value = _index;
    unawaited(AppAnalytics.logScreenOpen(_screenNameForIndex(_index)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapSession());
    });
  }

  List<Widget?> _buildScreenCache(int tabCount) {
    // Lazy-load tabs: only initialize current tab to prevent background video/audio playback
    final cache = List<Widget?>.filled(tabCount, null);
    if (_index >= 0 && _index < tabCount) {
      cache[_index] = _buildScreenAt(_index);
    }
    return cache;
  }

  int get _reelsTabIndex => 1;
  int get _analyticsTabIndex => 2;
  int get _coachTabIndex => 3;
  int get _profileTabIndex => 4;

  /// Premium tab removed from bottom nav; accessed via Profile "Go Elite".
  bool get _showPremiumTab => false;
  bool get _showEdgeTab => false;

  void _handlePremiumStateChanged() {
    if (!mounted) return;
    final bool premiumChanged =
        PremiumService.isPremiumActive != _lastPremiumActive;
    final bool billingChanged =
        PremiumService.billingState != _lastBillingState ||
        PremiumService.accessState != _lastAccessState;
    final int nextTabCount = _tabCount();
    final int previousTabCount = _lastKnownTabCount;
    final bool tabCountChanged = nextTabCount != _lastKnownTabCount;

    if (!premiumChanged && !billingChanged && !tabCountChanged) {
      _evaluatePremiumAlerts();
      return;
    }

    _lastPremiumActive = PremiumService.isPremiumActive;
    _lastBillingState = PremiumService.billingState;
    _lastAccessState = PremiumService.accessState;
    _lastKnownTabCount = nextTabCount;
    final maxIndex = nextTabCount - 1;
    setState(() {
      if (previousTabCount == 4 &&
          nextTabCount == 5 &&
          _index == 3 &&
          widget.initialIndex >= 4) {
        _index = 4;
      }
      if (_index > maxIndex) {
        _index = maxIndex;
      }
      _screenCache = _buildScreenCache(nextTabCount);
    });
    MainNavigation.activeTabNotifier.value = _index;
    _evaluatePremiumAlerts();
  }

  void _startMinuteTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      try {
        await WeeklyStatsService.addAppMinutes(user.uid, 1);
      } catch (_) {}
      _activeSince = DateTime.now();
    });
  }

  void _stopMinuteTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Always refresh premium from Firestore when app returns to foreground.
      PremiumService.refresh()
          .then((_) => _evaluatePremiumAlerts())
          .catchError((_) {});
      _activeSince = DateTime.now();
      _startMinuteTimer();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopMinuteTimer();
      _flushUsageMinutes();
    }
  }

  Future<void> _flushUsageMinutes() async {
    final started = _activeSince;
    if (started == null) return;
    _activeSince = null;

    final minutes = DateTime.now().difference(started).inMinutes;
    if (minutes <= 0) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await WeeklyStatsService.addAppMinutes(user.uid, minutes);
    } catch (_) {}
  }

  Future<void> _bootstrapSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      unawaited(user.getIdToken());
      unawaited(WeeklyStatsService.recordAppOpen(user.uid));
      unawaited(_warmUserHomeBoxes(user.uid));
    }

    // Don't block the first few frames; load username opportunistically.
    unawaited(loadUser());
    unawaited(_restoreAccessAndMaybeShowEdgeIntro());
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      unawaited(_evaluatePremiumAlerts());
    });
  }

  Future<void> _warmUserHomeBoxes(String uid) async {
    try {
      await Future.wait([
        Hive.openBox("local_stats_$uid"),
        Hive.openBox("speedBox"),
        Hive.openBox("quick_stats_cache"),
      ]);
    } catch (_) {}
  }

  Future<void> _restoreAccessAndMaybeShowEdgeIntro() async {
    try {
      await PremiumService.restoreOnLaunch();
      await PremiumService.refreshLiveEdgeBalance();
    } catch (_) {}
    if (!mounted || _edgeIntroChecked) return;
    _edgeIntroChecked = true;
    final prefs = await SharedPreferences.getInstance();
    final edgeIntroSeenOnce = prefs.getBool('edge_intro_seen_once') ?? false;
    if (edgeIntroSeenOnce) return;
    if (PremiumService.hasCrickNovaEdgeAccess ||
        PremiumService.isAccountBanned) {
      return;
    }
    await prefs.setBool('edge_intro_seen_once', true);
    await _showEdgeIntro();
  }

  Future<void> _showEdgeIntro() async {
    if (!mounted || _isEdgeIntroOpen) return;
    _isEdgeIntroOpen = true;
    final goEdge = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, animation, secondaryAnimation) =>
            const _CrickNovaEdgeIntroScreen(),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    _isEdgeIntroOpen = false;
    if (!mounted || goEdge != true) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const PremiumScreen(entrySource: 'features', initialAccessTab: 1),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PremiumService.premiumNotifier.removeListener(_handlePremiumStateChanged);
    MainNavigation.userNameNotifier.removeListener(_handleUserNameChanged);
    _stopMinuteTimer();
    _flushUsageMinutes();
    super.dispose();
  }

  void _handleUserNameChanged() {
    if (!mounted) return;
    final nextName = MainNavigation.userNameNotifier.value;
    if (nextName != userName) {
      setState(() {
        userName = nextName;
        if (_screenCache.isNotEmpty) {
          _screenCache[0] = _buildScreenAt(0);
        }
      });
    }
  }

  Future<void> loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "guest";
    String? name;
    try {
      final box = await Hive.openBox("local_stats_$uid");
      name = (box.get("profileName") as String?)?.trim();
    } catch (_) {}
    if (name == null || name.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString("profileName_$uid")?.trim();
    }
    if (name == null || name.isEmpty) {
      name = user?.displayName?.trim();
    }
    if (name == null || name.isEmpty) {
      name = _nameFromEmail(user?.email);
    }
    if (uid == "guest" && (name == null || name.isEmpty)) {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString("profileName")?.trim();
    }
    final String nextUserName =
        (name != null && name.isNotEmpty && name.toLowerCase() != "player")
        ? name
        : widget.userName;
    MainNavigation.userNameNotifier.value = nextUserName;
  }

  String? _nameFromEmail(String? email) {
    final raw = email?.trim();
    if (raw == null || raw.isEmpty || !raw.contains('@')) return null;
    final local = raw.split('@').first.trim();
    return local.isEmpty ? null : local;
  }

  Future<void> _evaluatePremiumAlerts() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    Future<void> maybeShowUsageAlert({
      required String featureKey,
      required String featureLabel,
      required int remaining,
      required int total,
    }) async {
      final alertKey = 'low_usage_alert_${PremiumService.plan}_$featureKey';
      final today = DateTime.now();
      final dayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final exhaustedKey =
          'exhausted_usage_alert_${PremiumService.plan}_${featureKey}_$dayKey';

      if (total <= 0) {
        await prefs.remove(alertKey);
        return;
      }

      if (remaining > 9) {
        await prefs.remove(alertKey);
        return;
      }

      if (remaining <= 0) {
        await prefs.remove(alertKey);
        final shownCount = prefs.getInt(exhaustedKey) ?? 0;
        if (shownCount >= 2 || !mounted) return;
        await prefs.setInt(exhaustedKey, shownCount + 1);
        if (!mounted) return;
        await _showClassyAlert(
          title: '$featureLabel Limit Reached',
          message:
              '$featureLabel has been fully used. Upgrade or renew to continue using this feature.',
        );
        return;
      }

      final alreadyShown = prefs.getBool(alertKey) ?? false;
      if (alreadyShown || !mounted) return;

      await prefs.setBool(alertKey, true);
      if (!mounted) return;
      await _showClassyAlert(
        title: '$featureLabel Almost Exhausted',
        message:
            'Only $remaining of $total remain for $featureLabel. Renew or upgrade now to avoid interruption.',
      );
    }

    await maybeShowUsageAlert(
      featureKey: 'chat',
      featureLabel: 'AI Chat',
      remaining: PremiumService.chatLimit - PremiumService.chatUsed,
      total: PremiumService.chatLimit,
    );

    await maybeShowUsageAlert(
      featureKey: 'mistake',
      featureLabel: 'Cricknova Mistake Detection',
      remaining: PremiumService.mistakeLimit - PremiumService.mistakeUsed,
      total: PremiumService.mistakeLimit,
    );

    final expiry = PremiumService.expiryDate;
    if (expiry == null) return;
    final daysLeft = expiry.difference(DateTime.now()).inDays;
    final expiryKey = 'expiry_warning_${expiry.toIso8601String()}';
    if (daysLeft > 4 || daysLeft < 0) {
      await prefs.remove(expiryKey);
      return;
    }
    final alreadyShown = prefs.getBool(expiryKey) ?? false;
    if (alreadyShown || !mounted) return;
    await prefs.setBool(expiryKey, true);
    if (!mounted) return;
    await _showClassyAlert(
      title: 'Premium Ends Soon',
      message:
          'Your premium plan expires in $daysLeft day${daysLeft == 1 ? '' : 's'}. Renew before expiry to keep uninterrupted access.',
    );
  }

  Future<void> _showClassyAlert({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: CrickXColors.graphite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: CrickXColors.limeSpark.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: CrickXColors.limeSpark.withValues(alpha: 0.12),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: CrickXColors.limeSpark,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: CrickXColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: const TextStyle(
                    color: CrickXColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Understood',
                      style: TextStyle(
                        color: CrickXColors.limeSpark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _tabCount() {
    // 5 standard tabs: Home | Reels | Analytics | Coach | Profile
    return 5;
  }

  Widget _buildScreenAt(int index) {
    if (index == 0) {
      return HomeScreen(key: const ValueKey('home'), userName: userName);
    }
    if (index == _reelsTabIndex) {
      return ValueListenableBuilder<int>(
        valueListenable: MainNavigation.activeTabNotifier,
        builder: (context, activeTab, _) {
          return ReelsScreen(
            key: const ValueKey('reels_feed'),
            isTabActive: activeTab == _reelsTabIndex,
          );
        },
      );
    }
    if (index == _analyticsTabIndex) {
      return const InsightsScreen(key: ValueKey('insights'));
    }
    if (index == _coachTabIndex) {
      return const AICoachScreen(key: ValueKey('CrickNovacoach'));
    }
    return const ProfileScreen(key: ValueKey('profile'));
  }

  String _screenNameForIndex(int index) {
    if (index == 0) return 'Home';
    if (index == _reelsTabIndex) return 'Reels';
    if (index == _analyticsTabIndex) return 'Analytics';
    if (index == _coachTabIndex) return 'AI Coach';
    if (index == _profileTabIndex) return 'Profile';
    return 'Tab $index';
  }

  Widget _buildTabScreen(int index) {
    if (index == _reelsTabIndex) {
      return ValueListenableBuilder<int>(
        valueListenable: MainNavigation.activeTabNotifier,
        builder: (context, activeTab, _) {
          return ReelsScreen(
            key: const ValueKey('reels_feed'),
            isTabActive: activeTab == _reelsTabIndex,
          );
        },
      );
    }
    return _screenCache[index] ?? const _DeferredTabLoader();
  }

  @override
  Widget build(BuildContext context) {
    final navItems = <_NavTabData>[
      const _NavTabData(
        label: 'Home',
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        index: 0,
      ),
      const _NavTabData(
        label: 'Reels',
        icon: Icons.play_circle_outline_rounded,
        activeIcon: Icons.play_circle_rounded,
        index: 1,
      ),
      const _NavTabData(
        label: 'Analytics',
        icon: Icons.insights_outlined,
        activeIcon: Icons.insights_rounded,
        index: 2,
      ),
      _NavTabData(
        label: 'Coach',
        icon: Icons.sports_cricket_outlined,
        activeIcon: Icons.sports_cricket_rounded,
        index: _coachTabIndex,
      ),
      _NavTabData(
        label: 'Profile',
        icon: Icons.person_outline,
        activeIcon: Icons.person_rounded,
        index: _profileTabIndex,
        isProfile: true,
      ),
    ];

    return Scaffold(
      backgroundColor: CrickXColors.graphiteBg,
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(
          _tabCount(),
          (i) => _screenCache[i] != null
              ? RepaintBoundary(
                  child: TickerMode(
                    enabled: i == _index,
                    child: _buildTabScreen(i),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: CrickXColors.graphite,
            border: Border(
              top: BorderSide(
                color: CrickXColors.graphiteBorder,
                width: 1.0,
              ),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                blurRadius: 20,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Row(
            children: [
              for (final item in navItems) Expanded(child: _buildNavTab(item)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavTab(_NavTabData item) {
    final bool isActive = _index == item.index;
    final List<Color> indicatorGradient = const [
      CrickXColors.limeSpark,
      CrickXColors.limeSpark,
    ];

    final Color glowColor = CrickXColors.limeSpark;

    const Color activeColor = CrickXColors.limeSpark;
    const Color inactiveColor = CrickXColors.textMuted;

    final Color textColor = isActive ? activeColor : inactiveColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (item.index == _index) return;
          if (!mounted) return;
          setTab(item.index);
        },
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Top active indicator line with glow
              SizedBox(
                height: 5,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    width: isActive ? 22 : 0,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: indicatorGradient),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: glowColor.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),

              // Icon or special badge
              if (item.isProfile)
                _profileNavIcon(isActive: isActive)
              else if (item.isEdge)
                _edgeNavIcon(isActive: isActive)
              else
                Icon(
                  isActive ? item.activeIcon : item.icon,
                  color: isActive ? activeColor : inactiveColor,
                  size: isActive ? 23 : 21,
                ),

              // Tab text label
              AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: isActive ? 1.0 : 0.85,
                child: Container(
                  height: 17,
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: textColor,
                        fontSize: 10.5,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
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

  Widget _profileNavIcon({required bool isActive}) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    final uid = user?.uid;
    String? localImgPath;
    if (uid != null && Hive.isBoxOpen('profile_$uid')) {
      localImgPath = Hive.box('profile_$uid').get('profileImagePath') as String?;
    }

    final initial = (userName.trim().isNotEmpty && userName.trim().toLowerCase() != 'player')
        ? userName.trim()[0].toUpperCase()
        : (user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()[0].toUpperCase()
            : null);

    return Container(
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive
              ? CrickXColors.limeSpark
              : const Color(0xFF52525B),
          width: isActive ? 2.0 : 1.1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: CrickXColors.limeSpark.withValues(alpha: 0.5),
                  blurRadius: 7,
                  spreadRadius: 0.8,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: localImgPath != null && File(localImgPath).existsSync()
            ? Image.file(
                File(localImgPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarFallback(initial, isActive),
              )
            : (photoUrl != null && photoUrl.isNotEmpty)
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(initial, isActive),
                  )
                : _avatarFallback(initial, isActive),
      ),
    );
  }

  Widget _avatarFallback(String? initial, bool isActive) {
    if (initial != null && initial.isNotEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive
                ? const [CrickXColors.limeSpark, Color(0xFF8CE600)]
                : const [Color(0xFF2B2F3A), Color(0xFF1D2028)],
          ),
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: isActive ? CrickXColors.onLime : Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Container(
      alignment: Alignment.center,
      color: isActive ? CrickXColors.limeSpark.withValues(alpha: 0.2) : const Color(0xFF1D2028),
      child: Icon(
        Icons.person_rounded,
        size: 15,
        color: isActive ? CrickXColors.limeSpark : CrickXColors.textMuted,
      ),
    );
  }

  Widget _edgeNavIcon({required bool isActive}) {
    return Icon(
      Icons.sports_cricket_rounded,
      color: isActive ? CrickXColors.limeSpark : CrickXColors.textMuted,
      size: isActive ? 24 : 22,
    );
  }
}

class _NavTabData {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int index;
  final bool isPremium;
  final bool isEdge;
  final bool isProfile;

  const _NavTabData({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.index,
    this.isPremium = false,
    this.isEdge = false,
    this.isProfile = false,
  });
}

class _DeferredTabLoader extends StatelessWidget {
  const _DeferredTabLoader();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.black);
  }
}
