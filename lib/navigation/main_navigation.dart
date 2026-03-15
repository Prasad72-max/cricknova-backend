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
  late List<Widget> _screens;
  DateTime? _activeSince;
  Timer? _minuteTimer;

  void goHome() {
    if (_index != 0) {
      setState(() {
        _index = 0;
      });
    }
  }

  void setTab(int index) {
    if (!mounted) return;
    setState(() {
      _index = index;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeSince = DateTime.now();
    _startMinuteTimer();
    _screens = _buildScreens();
    _bootstrapSession();
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
      PremiumService.refresh().catchError((_) {});
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      _screens = _buildScreens();
    });
  }

  List<Widget> _buildScreens() {
    return [
      HomeScreen(key: const ValueKey("home"), userName: userName), // 0
      const InsightsScreen(key: ValueKey("insights")), // 1
      const AICoachScreen(key: ValueKey("coach")), // 2 (premium)
      const PremiumScreen(entrySource: "tab", key: ValueKey("premium")), // 3
      const ProfileScreen(key: ValueKey("profile")), // 4
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              backgroundColor: (_index == 1 || _index == 2)
                  ? Colors.black
                  : Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: (_index == 1 || _index == 2)
                  ? null
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF050A1E),
                            Color(0xFF0E1A36),
                            Color(0xFF1E3A8A),
                            Color(0xFF3B82F6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: goHome,
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                "CrickNova AI",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              centerTitle: true,
            ),
      body: IndexedStack(index: _index, children: _screens),

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

        items: [
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
          BottomNavigationBarItem(
            label: "Premium",
            icon: _navIcon(Icons.star_outline, 3),
          ),
          BottomNavigationBarItem(
            label: "Profile",
            icon: _navIcon(Icons.person_outline, 4),
          ),
        ],
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
