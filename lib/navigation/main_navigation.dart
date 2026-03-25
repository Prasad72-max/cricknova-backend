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

class MainNavigation extends StatefulWidget {
  final String userName;
  static final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);

  const MainNavigation({super.key, required this.userName});

  static _MainNavigationState? of(BuildContext context) {
    return context.findAncestorStateOfType<_MainNavigationState>();
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _index = 0;
  String userName = "Player";
  late List<Widget?> _screenCache;
  DateTime? _activeSince;
  Timer? _minuteTimer;

  void goHome() {
    if (_index != 0) {
      setState(() {
        _index = 0;
      });
      MainNavigation.activeTabNotifier.value = _index;
    }
  }

  void setTab(int index) {
    if (!mounted) return;
    setState(() {
      _index = index;
    });
    MainNavigation.activeTabNotifier.value = _index;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PremiumService.premiumNotifier.addListener(_handlePremiumStateChanged);
    _activeSince = DateTime.now();
    _startMinuteTimer();
    _screenCache = List<Widget?>.filled(_tabCount(), null);
    _screenCache[_index] = _buildScreenAt(_index);
    MainNavigation.activeTabNotifier.value = _index;
    _bootstrapSession();
  }

  void _handlePremiumStateChanged() {
    if (!mounted) return;
    final maxIndex = _tabCount() - 1;
    setState(() {
      _screenCache = List<Widget?>.filled(_tabCount(), null);
      if (_index > maxIndex) {
        _index = maxIndex;
      }
      _screenCache[_index] = _buildScreenAt(_index);
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
    // 🔐 Ensure Firebase auth & ID token are ready
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.getIdToken(true);
      await WeeklyStatsService.recordAppOpen(user.uid);
    }

    await loadUser();

    if (!mounted) return;
    setState(() {});
    _evaluatePremiumAlerts();
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
    setState(() {
      userName = (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : widget.userName;
      _screenCache = List<Widget?>.filled(_tabCount(), null);
      _screenCache[_index] = _buildScreenAt(_index);
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
      featureLabel: 'Mistake Detection',
      remaining: PremiumService.mistakeLimit - PremiumService.mistakeUsed,
      total: PremiumService.mistakeLimit,
    );

    await maybeShowUsageAlert(
      featureKey: 'compare',
      featureLabel: 'Compare Analysis',
      remaining: PremiumService.compareLimit - PremiumService.compareUsed,
      total: PremiumService.compareLimit,
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

  int _tabCount() => PremiumService.isPremiumActive ? 4 : 5;

  Widget _buildScreenAt(int index) {
    if (index == 0) {
      return HomeScreen(key: const ValueKey("home"), userName: userName);
    }
    if (index == 1) {
      return const InsightsScreen(key: ValueKey("insights"));
    }
    if (index == 2) {
      return const AICoachScreen(key: ValueKey("coach"));
    }
    if (!PremiumService.isPremiumActive && index == 3) {
      return const PremiumScreen(entrySource: "tab", key: ValueKey("premium"));
    }
    return const ProfileScreen(key: ValueKey("profile"));
  }

  Widget _screenAt(int index) {
    final existing = _screenCache[index];
    if (existing != null) return existing;
    final built = _buildScreenAt(index);
    _screenCache[index] = built;
    return built;
  }

  @override
  Widget build(BuildContext context) {
    final navItems = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        label: "Home",
        icon: _navIcon(Icons.home_outlined, 0),
      ),
      BottomNavigationBarItem(
        label: "Insights",
        icon: _navIcon(Icons.insights_outlined, 1),
      ),
      BottomNavigationBarItem(
        label: "AI Coach",
        icon: _navIcon(Icons.auto_awesome_outlined, 2),
      ),
    ];
    if (!PremiumService.isPremiumActive) {
      navItems.add(
        BottomNavigationBarItem(
          label: "Premium",
          icon: _navIcon(Icons.star_outline, 3),
        ),
      );
    }
    navItems.add(
      BottomNavigationBarItem(
        label: "Profile",
        icon: _navIcon(
          Icons.person_outline,
          PremiumService.isPremiumActive ? 3 : 4,
        ),
      ),
    );

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(
          _tabCount(),
          (i) => i == _index || _screenCache[i] != null
              ? TickerMode(
                  enabled: i == _index,
                  child: _screenAt(i),
                )
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.white60,
        selectedIconTheme: const IconThemeData(size: 22),
        unselectedIconTheme: const IconThemeData(size: 20),
        type: BottomNavigationBarType.fixed,

        onTap: (i) async {
          if (i == _index) return;
          debugPrint(
            "BOTTOM_NAV tap=$i isPremium=${PremiumService.isPremiumActive}",
          );

          if (!mounted) return;
          setTab(i);
        },
        items: navItems,
      ),
    );
  }

  Widget _navIcon(IconData icon, int tabIndex) {
    final bool isActive = _index == tabIndex;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isActive)
          Container(
            height: 3,
            width: 24,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Colors.amber, blurRadius: 8, spreadRadius: 1),
              ],
            ),
          ),
        Icon(icon),
      ],
    );
  }
}
