import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cricknova_notification_service.dart';
import '../services/greeting_controller.dart';
import '../services/premium_service.dart';
import '../premium/premium_screen.dart';
import '../premium/elite_status_screen.dart';
import '../upload/upload_screen.dart';
import '../compare/analyse_yourself_screen.dart';
import '../premium/premium_expired_screen.dart';
import '../navigation/main_navigation.dart';
import 'bowling_analyse_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userName;

  const HomeScreen({super.key, required this.userName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int totalUploadedSessions = 0;
  List<double> speedHistory = [];
  double _cachedTopSpeed = 0.0;
  bool _lastPremiumState = PremiumService.isPremiumActive;
  bool _showEliteWelcomeHeader = false;
  bool _notificationPromptStarted = false;

  final PageController _statsPageController = PageController(
    viewportFraction: 0.9,
  );
  Timer? _statsTimer;
  bool _quickStatsSyncInProgress = false;
  StreamSubscription? _statsBoxSub;
  StreamSubscription? _speedBoxSub;
  int _currentStatsPage = 0;
  late final AnimationController _eliteHeaderController;
  late final AnimationController _diamondController;
  late final AnimationController _pulseController;
  bool _homeAnimationsActive = false;
  GreetingPayload _greeting = GreetingController.build("Player");
  Timer? _greetingTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userName.trim() != oldWidget.userName.trim()) {
      _syncGreetingNameFromWidget();
    }
  }

  void _onPremiumChanged() {
    if (!mounted) return;
    final next = PremiumService.isPremiumActive;
    final premiumStateChanged = next != _lastPremiumState;
    _lastPremiumState = next;
    unawaited(_saveQuickStatsToHive());
    if (premiumStateChanged) {
      _checkExpiryPopup();
      setState(() {});
      return;
    }

    if (_isHomeTabVisible) {
      final bool membershipDisplayChanged = _quickStats.any(
        (_QuickStatData stat) =>
            stat.metric == "Membership" &&
            stat.value != (PremiumService.isPremiumActive ? "Elite" : "Free"),
      );
      if (membershipDisplayChanged) {
        setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _greeting = GreetingController.build(widget.userName);
    WidgetsBinding.instance.addObserver(_lifeCycleObserver);
    _eliteHeaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _diamondController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);

    PremiumService.premiumNotifier.addListener(_onPremiumChanged);
    PremiumService.premiumNotifier.addListener(_checkExpiryPopup);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkExpiryPopup();
    });

    MainNavigation.activeTabNotifier.addListener(_handleTabVisibilityChange);
    if (_isHomeTabVisible) {
      _startStatsAutoSlide();
      _resumeHomeAnimations();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initRealtimeQuickStatsListeners());
      unawaited(_prepareInitialHomeState());
      unawaited(_prepareEliteWelcomeHeader());
      unawaited(_maybeHandleNotificationOptIn());
      unawaited(_loadGreetingState());
    });
    _scheduleGreetingRefresh();
  }

  bool get _isHomeTabVisible => MainNavigation.activeTabNotifier.value == 0;

  void _handleTabVisibilityChange() {
    if (_isHomeTabVisible) {
      _startStatsAutoSlide();
      _resumeHomeAnimations();
      _scheduleGreetingRefresh();
      _refreshGreeting();
      unawaited(_syncQuickStats());
      return;
    }
    _statsTimer?.cancel();
    _greetingTimer?.cancel();
    _pauseHomeAnimations();
  }

  void _resumeHomeAnimations() {
    if (_homeAnimationsActive) return;
    _homeAnimationsActive = true;
    if (!_diamondController.isAnimating) {
      _diamondController.repeat();
    }
    if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _pauseHomeAnimations() {
    if (!_homeAnimationsActive) return;
    _homeAnimationsActive = false;
    _diamondController.stop();
    _pulseController.stop();
  }

  late final WidgetsBindingObserver _lifeCycleObserver = _HomeLifecycleObserver(
    onResumed: _syncQuickStats,
  );

  Future<void> _prepareInitialHomeState() async {
    await _loadQuickStatsFromHive();
    if (mounted) {
      setState(() {});
    }
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || !_isHomeTabVisible) return;
      unawaited(_bootstrapAuthAndData());
    });
  }

  Future<void> _loadGreetingState() async {
    final cachedName = await GreetingController.loadCachedUserName(
      fallback: widget.userName,
    );
    if (!mounted) return;
    setState(() {
      _greeting = GreetingController.build(cachedName);
    });
    await GreetingController.cacheUserName(cachedName);
  }

  void _syncGreetingNameFromWidget() {
    final nextName = widget.userName.trim().isEmpty
        ? "Player"
        : widget.userName.trim();
    setState(() {
      _greeting = GreetingController.build(nextName);
    });
    unawaited(GreetingController.cacheUserName(nextName));
  }

  void _refreshGreeting() {
    if (!mounted) return;
    final resolvedName = _greeting.userName.trim().isEmpty
        ? widget.userName
        : _greeting.userName;
    setState(() {
      _greeting = GreetingController.build(resolvedName);
    });
  }

  void _scheduleGreetingRefresh() {
    _greetingTimer?.cancel();
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _greetingTimer = Timer(nextMinute.difference(now), () {
      _refreshGreeting();
      _scheduleGreetingRefresh();
    });
  }

  Future<void> _bootstrapAuthAndData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (!PremiumService.isLoaded) {
        await PremiumService.restoreOnLaunch();
      }
      _checkExpiryPopup();
    }

    await Future.wait<void>([loadSpeedHistory(), loadTrainingVideos()]);
    await _saveQuickStatsToHive();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _maybeHandleNotificationOptIn() async {
    if (_notificationPromptStarted) return;
    _notificationPromptStarted = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted || !_isHomeTabVisible) {
      return;
    }

    final notificationService = CrickNovaNotificationService.instance;
    await notificationService.handleAppOpened(user.uid);

    final shouldPrompt = await notificationService.shouldPromptForOptIn(
      user.uid,
    );
    if (!shouldPrompt || !mounted || !_isHomeTabVisible) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || !_isHomeTabVisible) return;

    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1220),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Allow CrickNova Notifications?',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Let CrickNova AI send playful match-day nudges, analysis-complete alerts, and personal-best hype moments. No spam. Just smart cricket reminders.',
            style: GoogleFonts.poppins(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not Now',
                style: GoogleFonts.poppins(color: Colors.white60),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              child: Text(
                'Allow',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (allow == true) {
      final granted = await notificationService.enableForUser(user.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'CrickNova notifications are on. The banter begins now.'
                : 'Notifications are still blocked on this device. You can enable them later in settings.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await notificationService.disableForUser(user.uid);
  }

  String _eliteHeaderSeenKey(String uid) => 'home_elite_header_seen_$uid';

  Future<void> _prepareEliteWelcomeHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final createdAt = user.metadata.creationTime;
    final lastSignInAt = user.metadata.lastSignInTime;
    final isBrandNew =
        createdAt != null &&
        lastSignInAt != null &&
        lastSignInAt.difference(createdAt).abs() <= const Duration(minutes: 2);

    if (!isBrandNew) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_eliteHeaderSeenKey(user.uid)) ?? false;
    if (alreadySeen || !mounted) return;

    await prefs.setBool(_eliteHeaderSeenKey(user.uid), true);
    setState(() {
      _showEliteWelcomeHeader = true;
    });
    _eliteHeaderController.forward(from: 0);
  }

  String _currentUid() => FirebaseAuth.instance.currentUser?.uid ?? "guest";

  void _checkExpiryPopup() {
    if (!mounted) return;

    if (PremiumService.justExpired) {
      PremiumService.justExpired = false;

      debugPrint("🔥 Showing Expiry Popup");

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PremiumExpiredScreen()));
      });
    }
  }

  Future<void> loadSpeedHistory() async {
    final uid = _currentUid();
    final speedBox = await Hive.openBox('speedBox');
    final stored = speedBox.get('allSpeeds_$uid') as List?;
    final allSpeeds = stored == null
        ? <double>[]
        : stored.map((e) => (e as num).toDouble()).toList();

    if (allSpeeds.length > 6) {
      speedHistory = allSpeeds.sublist(allSpeeds.length - 6);
    } else {
      speedHistory = allSpeeds;
    }
  }

  Future<void> loadTrainingVideos() async {
    final uid = _currentUid();
    final statsBox = await Hive.openBox("local_stats_$uid");
    if (!mounted) return;
    totalUploadedSessions =
        (statsBox.get('totalVideos', defaultValue: 0) as num).toInt();
  }

  String _cacheSessionsKey(String uid) => 'sessionsUploaded_$uid';
  String _cacheTopSpeedKey(String uid) => 'topBallSpeed_$uid';
  String _cacheMemberKey(String uid) => 'membership_$uid';
  String _cacheAnalyseUsedKey(String uid) => 'analyseUsed_$uid';
  String _cacheAnalyseLimitKey(String uid) => 'analyseLimit_$uid';
  String _cacheUpdatedAtKey(String uid) => 'updatedAt_$uid';

  Future<void> _loadQuickStatsFromHive() async {
    final uid = _currentUid();
    final box = await Hive.openBox('quick_stats_cache');
    totalUploadedSessions =
        (box.get(_cacheSessionsKey(uid), defaultValue: totalUploadedSessions)
                as num)
            .toInt();
    _cachedTopSpeed =
        (box.get(_cacheTopSpeedKey(uid), defaultValue: _cachedTopSpeed) as num)
            .toDouble();
  }

  Future<void> _saveQuickStatsToHive() async {
    final uid = _currentUid();
    final box = await Hive.openBox('quick_stats_cache');
    final topSpeed = speedHistory.isEmpty
        ? _cachedTopSpeed
        : speedHistory.reduce((a, b) => a > b ? a : b);
    _cachedTopSpeed = topSpeed;

    await box.put(_cacheSessionsKey(uid), totalUploadedSessions);
    await box.put(_cacheTopSpeedKey(uid), topSpeed);
    await box.put(
      _cacheMemberKey(uid),
      PremiumService.isPremiumActive ? 'Elite' : 'Free',
    );
    await box.put(_cacheAnalyseUsedKey(uid), PremiumService.compareUsed);
    await box.put(_cacheAnalyseLimitKey(uid), PremiumService.compareLimit);
    await box.put(_cacheUpdatedAtKey(uid), DateTime.now().toIso8601String());
  }

  Future<void> _initRealtimeQuickStatsListeners() async {
    final uid = _currentUid();
    final statsBox = await Hive.openBox("local_stats_$uid");
    final speedBox = await Hive.openBox("speedBox");

    _statsBoxSub?.cancel();
    _speedBoxSub?.cancel();

    _statsBoxSub = statsBox.watch().listen((event) {
      if (!mounted) return;
      if (event.key == 'totalVideos' || event.key == 'maxSpeed') {
        _syncQuickStats();
      }
    });

    _speedBoxSub = speedBox.watch(key: 'allSpeeds_$uid').listen((_) {
      if (!mounted) return;
      _syncQuickStats();
    });
  }

  void _openEliteStatusScreen() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) =>
            EliteStatusScreen(userName: widget.userName),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  void _startStatsAutoSlide() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_statsPageController.hasClients) return;
      final stats = _quickStats;
      if (stats.length <= 1) return;

      _currentStatsPage = (_currentStatsPage + 1) % stats.length;
      _statsPageController.animateToPage(
        _currentStatsPage,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _syncQuickStats() async {
    if (!mounted || _quickStatsSyncInProgress) return;
    _quickStatsSyncInProgress = true;
    try {
      final previousSessions = totalUploadedSessions;
      final previousSpeed = speedHistory;

      await loadSpeedHistory();
      await loadTrainingVideos();
      if (!mounted) return;

      final bool videosChanged = previousSessions != totalUploadedSessions;
      final bool speedChanged = !_sameDoubleList(previousSpeed, speedHistory);

      await _saveQuickStatsToHive();

      if (videosChanged || speedChanged) {
        setState(() {});
      }
    } finally {
      _quickStatsSyncInProgress = false;
    }
  }

  bool _sameDoubleList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<_QuickStatData> get _quickStats {
    final maxSpeed = speedHistory.isEmpty
        ? _cachedTopSpeed
        : speedHistory.reduce((a, b) => a > b ? a : b);
    return [
      _QuickStatData(
        title: "Quick Stats",
        value: "$totalUploadedSessions",
        metric: "Sessions Uploaded",
        accent: const [Color(0xFF8DE0FF), Color(0xFF2FA2FF)],
      ),
      _QuickStatData(
        title: "Quick Stats",
        value: maxSpeed <= 0 ? "--" : maxSpeed.toStringAsFixed(1),
        metric: "Top Ball Speed",
        suffix: maxSpeed <= 0 ? "" : " km/h",
        accent: const [Color(0xFF67F7C0), Color(0xFF11C981)],
      ),
      _QuickStatData(
        title: "Quick Stats",
        value: PremiumService.isPremiumActive ? "Elite" : "Free",
        metric: "Membership",
        accent: const [Color(0xFFFFE295), Color(0xFFF2B439)],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF02040B), Color(0xFF040A18), Color(0xFF010204)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: -120,
            child: _meshOrb(
              size: 360,
              colors: const [Color(0x332A66FF), Color(0x00000000)],
            ),
          ),
          Positioned(
            top: 120,
            right: -100,
            child: _meshOrb(
              size: 280,
              colors: const [Color(0x22218AA8), Color(0x00000000)],
            ),
          ),
          Positioned(
            bottom: -200,
            left: -80,
            child: _meshOrb(
              size: 300,
              colors: const [Color(0x1F0F4D88), Color(0x00000000)],
            ),
          ),
          RefreshIndicator(
            color: const Color(0xFF00FF88),
            backgroundColor: const Color(0xFF0F172A),
            notificationPredicate: (notification) {
              return PremiumService.isPremiumActive && notification.depth == 0;
            },
            onRefresh: () async {
              if (!PremiumService.isPremiumActive) return;
              await PremiumService.refresh();
              await _bootstrapAuthAndData();

              if (mounted) {
                setState(() {});
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                bottom: kBottomNavigationBarHeight + 24,
              ),
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    60,
                    20,
                    _showEliteWelcomeHeader ? 34 : 32,
                  ),
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: _showEliteWelcomeHeader ? 290 : 220,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF0A1020).withValues(alpha: 0.9),
                        const Color(0xFF0A0F1B).withValues(alpha: 0.72),
                        const Color(0xFF060A13).withValues(alpha: 0.56),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 34,
                        spreadRadius: 1,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _premiumWelcomeHeader(
                        isEliteWelcome: _showEliteWelcomeHeader,
                      ),
                      const SizedBox(height: 14),
                      if (!PremiumService.isLoaded)
                        _checkingPlanBadge()
                      else if (PremiumService.isPremiumActive)
                        _eliteNameBadge()
                      else
                        _risingStarBadge(),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: 130,
                    child: Column(
                      children: [
                        Expanded(
                          child: PageView.builder(
                            controller: _statsPageController,
                            itemCount: _quickStats.length,
                            onPageChanged: (index) {
                              setState(() {
                                _currentStatsPage = index;
                              });
                            },
                            itemBuilder: (context, index) {
                              final stat = _quickStats[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: _quickStatsCard(stat: stat),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_quickStats.length, (index) {
                            final active = index == _currentStatsPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: active ? 22 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100),
                                color: active
                                    ? const Color(0xFFBBD4FF)
                                    : Colors.white.withValues(alpha: 0.25),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _actionCard(
                        title: "Upload Training Video",
                        subtitle: "AI will analyze your batting or bowling",
                        icon: Icons.cloud_upload_rounded,
                        iconGradient: const [
                          Color(0xFF7FDBFF),
                          Color(0xFF2B77FF),
                        ],
                        onTap: () {
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const UploadScreen(),
                                ),
                              )
                              .then((_) => _syncQuickStats());
                        },
                      ),
                      const SizedBox(height: 14),
                      _actionCard(
                        title: "Analyse Yourself",
                        subtitle: "Compare two videos and see differences",
                        icon: Icons.analytics_rounded,
                        iconGradient: const [
                          Color(0xFFF7D173),
                          Color(0xFFEE8F2A),
                        ],
                        onTap: () {
                          if (!PremiumService.isLoaded) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Checking premium status..."),
                              ),
                            );
                            return;
                          }

                          if (!PremiumService.hasCompareAccess) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PremiumScreen(entrySource: "analyse"),
                              ),
                            );
                            return;
                          }

                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const AnalyseYourselfScreen(),
                                ),
                              )
                              .then((_) => _syncQuickStats());
                        },
                      ),
                      const SizedBox(height: 14),
                      _actionCard(
                        title: "Bowling Analysis",
                        subtitle:
                            "Open bowling mistake detection and compare in one place",
                        icon: Icons.sports_baseball_rounded,
                        iconGradient: const [
                          Color(0xFF7CF0D5),
                          Color(0xFF1AAE8B),
                        ],
                        onTap: () {
                          if (!PremiumService.isLoaded) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Checking premium status..."),
                              ),
                            );
                            return;
                          }

                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const BowlingAnalyseScreen(),
                                ),
                              )
                              .then((_) => _syncQuickStats());
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 50),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Remaining Features",
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Premium",
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      PremiumService.isPremium
                                          ? "Premium"
                                          : "Free",
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: PremiumService.isPremium
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _usageRow(
                                  label: "CrickNova Coach Chats",
                                  used: PremiumService.chatUsed,
                                  total: PremiumService.chatLimit,
                                ),
                                const SizedBox(height: 10),
                                _usageRow(
                                  label: "Mistake Detection",
                                  used: PremiumService.mistakeUsed,
                                  total: PremiumService.mistakeLimit,
                                ),
                                const SizedBox(height: 10),
                                _usageRow(
                                  label: "Analyse Yourself",
                                  used: PremiumService.compareUsed,
                                  total: PremiumService.compareLimit,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meshOrb({required double size, required List<Color> colors}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  Widget _quickStatsCard({required _QuickStatData stat}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1C000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: LinearGradient(
                    colors: stat.accent,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      stat.title,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: stat.value,
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: stat.suffix,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      stat.metric,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.64),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> iconGradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          debugPrint('ACTION CARD TAPPED → $title');
          onTap();
        },
        borderRadius: BorderRadius.circular(22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 14,
                    spreadRadius: 1,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _isometricFeatureIcon(icon: icon, gradient: iconGradient),
                  const SizedBox(width: 18),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.78),
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
      ),
    );
  }

  Widget _isometricFeatureIcon({
    required IconData icon,
    required List<Color> gradient,
  }) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 10,
            child: Transform(
              transform: Matrix4.identity()..setEntry(0, 1, -0.15),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: gradient
                        .map((e) => e.withValues(alpha: 0.42))
                        .toList(),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            top: 4,
            child: Transform(
              transform: Matrix4.identity()
                ..rotateZ(-0.12)
                ..setEntry(3, 2, 0.001),
              alignment: Alignment.center,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.34),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, size: 23, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _usageRow({
    required String label,
    required int used,
    required int total,
  }) {
    final displayTotal = total == 0 ? "-" : total.toString();
    final bool isLimitReached = total > 0 && used >= total;

    IconData iconData;

    if (label.contains("Chat")) {
      iconData = Icons.smart_toy_outlined;
    } else if (label.contains("Mistake")) {
      iconData = Icons.track_changes_outlined;
    } else {
      iconData = Icons.analytics_outlined;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(iconData, size: 18, color: Colors.white70),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "$used/$displayTotal",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isLimitReached
                      ? Colors.redAccent
                      : const Color(0xFFFFD700),
                ),
              ),
              if (isLimitReached) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.lock_rounded,
                  size: 16,
                  color: Colors.redAccent,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _premiumWelcomeHeader({required bool isEliteWelcome}) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _eliteHeaderController,
        _diamondController,
        _pulseController,
      ]),
      builder: (context, _) {
        final progress = isEliteWelcome ? _eliteHeaderController.value : 1.0;
        final welcomeOpacity = isEliteWelcome
            ? ((_eliteHeaderController.value - 0.05) / 0.20).clamp(0.0, 1.0)
            : 1.0;
        final eliteSlide = isEliteWelcome
            ? Curves.easeOutCubic.transform(
                ((_eliteHeaderController.value - 0.18) / 0.34).clamp(0.0, 1.0),
              )
            : 1.0;
        final lineProgress = isEliteWelcome
            ? Curves.easeOutCubic.transform(
                ((_eliteHeaderController.value - 0.36) / 0.22).clamp(0.0, 1.0),
              )
            : 1.0;
        final pulse = 0.82 + (_pulseController.value * 0.18);
        final greetingTheme = _greeting.theme;
        final isMidnightTheme = greetingTheme.slot == GreetingTimeSlot.midnight;
        final accentColors = greetingTheme.accentColors
            .map((value) => Color(value))
            .toList(growable: false);
        final backgroundColors = greetingTheme.backgroundColors
            .map((value) => Color(value))
            .toList(growable: false);
        final shortGreeting = GreetingController.getShortGreetingLabel();
        final shortParts = shortGreeting.split(' ');
        final lineOne = shortParts.isNotEmpty
            ? shortParts.first
            : shortGreeting;
        final lineTwo = shortParts.length > 1
            ? shortParts.sublist(1).join(' ')
            : (isEliteWelcome ? "Elite" : "");
        final subtitle = isEliteWelcome && !isMidnightTheme
            ? "Your elite cricket AI system is ready."
            : _greeting.message;
        final accentGlow = accentColors.first;

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: backgroundColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EliteStadiumBackdropPainter(
                      opacity: 0.42 * progress,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: 4,
                child: Opacity(
                  opacity: 0.5 * progress,
                  child: Transform.rotate(
                    angle: _diamondController.value * math.pi * 2,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(
                          math.sin(_diamondController.value * math.pi * 2) *
                              0.65,
                        ),
                      child: const Icon(
                        Icons.diamond_outlined,
                        color: Color(0xFFF0D9A4),
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 24, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Opacity(
                      opacity: welcomeOpacity,
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: accentColors,
                          ).createShader(bounds);
                        },
                        child: Text(
                          lineOne,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.0,
                            shadows: isMidnightTheme
                                ? [
                                    Shadow(
                                      color: accentGlow.withValues(
                                        alpha: 0.34 * pulse,
                                      ),
                                      blurRadius: 22,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(22 * (1 - eliteSlide), 0),
                      child: Opacity(
                        opacity: eliteSlide,
                        child: Stack(
                          children: [
                            Positioned(
                              right: -8,
                              top: 6,
                              child: Opacity(
                                opacity: 1 - eliteSlide,
                                child: Container(
                                  width: 44,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        accentColors.first.withValues(
                                          alpha: 0.0,
                                        ),
                                        accentColors.last.withValues(
                                          alpha: 0.5,
                                        ),
                                        accentColors.first.withValues(
                                          alpha: 0.0,
                                        ),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                            ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  colors: accentColors,
                                ).createShader(bounds);
                              },
                              child: Text(
                                lineTwo,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.0,
                                  shadows: isMidnightTheme
                                      ? [
                                          Shadow(
                                            color: accentGlow.withValues(
                                              alpha: 0.38 * pulse,
                                            ),
                                            blurRadius: 24,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 160 * lineProgress,
                        height: 1.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: accentColors),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: accentGlow.withValues(alpha: 0.28),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _greeting.userName,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color.lerp(
                          const Color(0xFFEAF6FF),
                          Colors.white,
                          pulse,
                        ),
                        shadows: [
                          Shadow(
                            color: accentGlow.withValues(
                              alpha: (isMidnightTheme ? 0.44 : 0.22) * pulse,
                            ),
                            blurRadius: isMidnightTheme ? 20 : 14,
                          ),
                          if (isMidnightTheme)
                            Shadow(
                              color: accentColors.last.withValues(
                                alpha: 0.28 * pulse,
                              ),
                              blurRadius: 28,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(
                          alpha: isMidnightTheme ? 0.86 : 0.72,
                        ),
                        height: 1.4,
                        shadows: isMidnightTheme
                            ? [
                                Shadow(
                                  color: accentGlow.withValues(alpha: 0.24),
                                  blurRadius: 18,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _eliteNameBadge() {
    return EliteStatusHeroBadge(onTap: _openEliteStatusScreen);
  }

  Widget _checkingPlanBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            "CHECKING PLAN...",
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _risingStarBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: Color(0xFF22C55E)),
          const SizedBox(width: 8),
          Text(
            "RISING STAR",
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _greetingTimer?.cancel();
    _pauseHomeAnimations();
    MainNavigation.activeTabNotifier.removeListener(_handleTabVisibilityChange);
    _statsBoxSub?.cancel();
    _speedBoxSub?.cancel();
    _statsPageController.dispose();
    _eliteHeaderController.dispose();
    _diamondController.dispose();
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(_lifeCycleObserver);
    PremiumService.premiumNotifier.removeListener(_onPremiumChanged);
    PremiumService.premiumNotifier.removeListener(_checkExpiryPopup);
    super.dispose();
  }
}

class _EliteStadiumBackdropPainter extends CustomPainter {
  final double opacity;

  _EliteStadiumBackdropPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final floodPaint = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x44A8CFFF), Color(0x00000000)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.22, size.height * 0.06),
              radius: size.width * 0.35,
            ),
          )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    canvas.drawCircle(
      Offset(size.width * 0.22, size.height * 0.06),
      size.width * 0.22,
      floodPaint..color = const Color(0x66A8CFFF).withValues(alpha: opacity),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.09),
      size.width * 0.18,
      Paint()
        ..shader =
            const RadialGradient(
              colors: [Color(0x3399C7FF), Color(0x00000000)],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * 0.82, size.height * 0.09),
                radius: size.width * 0.28,
              ),
            )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    final fieldArc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = const Color(0xFF8FB9E8).withValues(alpha: opacity * 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final rect = Rect.fromLTWH(
      -size.width * 0.12,
      size.height * 0.52,
      size.width * 1.24,
      size.height * 0.70,
    );
    canvas.drawArc(rect, math.pi, math.pi, false, fieldArc);

    final railPaint = Paint()
      ..color = const Color(0xFFB5D8FF).withValues(alpha: opacity * 0.12)
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.46),
      Offset(size.width * 0.92, size.height * 0.38),
      railPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _EliteStadiumBackdropPainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}

class _HomeLifecycleObserver extends WidgetsBindingObserver {
  final Future<void> Function() onResumed;

  _HomeLifecycleObserver({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}

class _QuickStatData {
  final String title;
  final String value;
  final String metric;
  final String suffix;
  final List<Color> accent;

  const _QuickStatData({
    required this.title,
    required this.value,
    required this.metric,
    this.suffix = "",
    required this.accent,
  });
}
