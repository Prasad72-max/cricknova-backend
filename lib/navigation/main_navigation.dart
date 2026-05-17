import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../home/home_screen.dart';
import '../ai/ai_coach_screen.dart';
import '../premium/premium_screen.dart';
import '../profile/profile_screen.dart';
import '../services/premium_service.dart';
import '../services/weekly_stats_service.dart';
import 'dart:async';
import '../insights/insights_screen.dart';

abstract class MainNavigationController {
  void setTab(int index);
  void goHome();
}

class MainNavigation extends StatefulWidget {
  final String userName;
  final int initialIndex;
  static final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);

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
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    PremiumService.premiumNotifier.addListener(_handlePremiumStateChanged);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapSession());
    });
  }

  List<Widget?> _buildScreenCache(int tabCount) {
    return List<Widget?>.generate(tabCount, _buildScreenAt);
  }

  int get _coachTabIndex => 2;

  int get _profileTabIndex {
    return PremiumService.isPremiumActive ? 3 : 4;
  }

  void _handlePremiumStateChanged() {
    if (!mounted) return;
    final bool premiumChanged =
        PremiumService.isPremiumActive != _lastPremiumActive;
    final bool billingChanged =
        PremiumService.billingState != _lastBillingState ||
        PremiumService.accessState != _lastAccessState;
    final int nextTabCount = _tabCount();
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
    }

    // Don't block the first few frames; load username opportunistically.
    unawaited(loadUser());
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      unawaited(_evaluatePremiumAlerts());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PremiumService.premiumNotifier.removeListener(_handlePremiumStateChanged);
    _stopMinuteTimer();
    _flushUsageMinutes();
    super.dispose();
  }

  Future<void> loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "guest";
    String? name;
    try {
      final box = await Hive.openBox("local_stats_$uid");
      name = box.get("profileName") as String?;
    } catch (_) {}
    if (name == null || name.trim().isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString("profileName");
    }
    final String nextUserName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : widget.userName;
    if (nextUserName == userName) {
      return;
    }
    setState(() {
      userName = nextUserName;
      if (_screenCache.isNotEmpty) {
        _screenCache[0] = _buildScreenAt(0);
      }
    });
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
              color: const Color(0xFF0B1118),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
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
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: Color(0xFF7DD3FC),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white70,
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
                        color: Color(0xFF7DD3FC),
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
    return PremiumService.isPremiumActive ? 4 : 5;
  }

  Widget _buildScreenAt(int index) {
    if (index == 0) {
      return HomeScreen(key: const ValueKey("home"), userName: userName);
    }
    if (index == 1) {
      return const InsightsScreen(key: ValueKey("insights"));
    }
    if (index == _coachTabIndex) {
      return const AICoachScreen(key: ValueKey("CrickNovacoach"));
    }
    if (!PremiumService.isPremiumActive && index == 3) {
      return const PremiumScreen(entrySource: "tab", key: ValueKey("premium"));
    }
    return const ProfileScreen(key: ValueKey("profile"));
  }

  @override
  Widget build(BuildContext context) {
    final navItems = <_NavTabData>[
      _NavTabData(label: "Home", icon: Icons.home_outlined, index: 0),
      _NavTabData(label: "Insights", icon: Icons.insights_outlined, index: 1),
      _NavTabData(
        label: "CrickNova Coach",
        icon: Icons.auto_awesome_outlined,
        index: _coachTabIndex,
      ),
    ];
    if (!PremiumService.isPremiumActive) {
      navItems.add(
        _NavTabData(label: "Premium", icon: Icons.star_outline, index: 3),
      );
    }
    navItems.add(
      _NavTabData(
        label: "Profile",
        icon: Icons.person_outline,
        index: _profileTabIndex,
      ),
    );

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(
          _tabCount(),
          (i) => i == _index || _screenCache[i] != null
              ? RepaintBoundary(
                  child: TickerMode(
                    enabled: i == _index,
                    child: _screenCache[i] ?? const _DeferredTabLoader(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 64,
          color: Colors.black,
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
    final color = isActive ? Colors.amber : Colors.white60;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (item.index == _index) return;
          debugPrint(
            "BOTTOM_NAV tap=${item.index} isPremium=${PremiumService.isPremiumActive}",
          );
          if (!mounted) return;
          setTab(item.index);
        },
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 7,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    width: isActive ? 24 : 0,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isActive
                          ? const [
                              BoxShadow(
                                color: Colors.amber,
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              Icon(item.icon, color: color, size: isActive ? 22 : 20),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
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

class _NavTabData {
  final String label;
  final IconData icon;
  final int index;

  const _NavTabData({
    required this.label,
    required this.icon,
    required this.index,
  });
}

class _DeferredTabLoader extends StatelessWidget {
  const _DeferredTabLoader();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.black);
  }
}
