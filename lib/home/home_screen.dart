import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cricknova_notification_service.dart';
import '../services/app_analytics.dart';
import '../services/greeting_controller.dart';
import '../services/premium_service.dart';
import '../premium/premium_screen.dart';
import '../premium/elite_status_screen.dart';
import '../upload/upload_screen.dart';
import '../services/analysis_credit_service.dart';
import '../compare/analyse_yourself_screen.dart';
import '../premium/premium_expired_screen.dart';
import '../navigation/main_navigation.dart';
import 'package:CrickNova_Ai/analysis/analyzing_videos_screen.dart';
import 'package:CrickNova_Ai/models/pending_video.dart';
import 'bowling_analyse_screen.dart';
import '../theme/crickx_colors.dart';

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
  Timer? _analysisCountdownTicker;
  final ValueNotifier<int> _analysisClockTick = ValueNotifier<int>(0);
  bool _quickStatsSyncInProgress = false;
  StreamSubscription? _statsBoxSub;
  StreamSubscription? _speedBoxSub;
  StreamSubscription<BoxEvent>? _pendingVideosSub;
  int _currentStatsPage = 0;
  late final AnimationController _eliteHeaderController;
  late final AnimationController _diamondController;
  late final AnimationController _pulseController;
  bool _homeAnimationsActive = false;
  GreetingPayload _greeting = GreetingController.build("Player");
  Timer? _greetingTimer;
  final Map<String, Timer> _analysisTwoMinuteTimers = {};
  bool _analysisReminderSyncing = false;

  static const Duration _analysisUploadReminderDelay = Duration(minutes: 2);
  static const String _analysisTimerStartedPrefix =
      'analysis_two_min_timer_started_';
  static const String _analysisMessageShownPrefix =
      'analysis_two_min_message_shown_';

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
            stat.metric == "Membership" && stat.value != _currentPlanStatValue,
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
    _primeInitialHomeFromOpenCaches();
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
      _startAnalysisCountdownTicker();
      _resumeHomeAnimations();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AppAnalytics.log('home_opened'));
      unawaited(_initRealtimeQuickStatsListeners());
      unawaited(_prepareInitialHomeState());
      unawaited(_prepareEliteWelcomeHeader());
      unawaited(_maybeHandleNotificationOptIn());
      unawaited(_loadGreetingState());
      unawaited(_syncAnalysisTwoMinuteReminders());
    });
    _pendingVideosSub = Hive.box<PendingVideo>(
      'pending_videos',
    ).watch().listen((_) => unawaited(_syncAnalysisTwoMinuteReminders()));
    _scheduleGreetingRefresh();
  }

  void _primeInitialHomeFromOpenCaches() {
    final uid = _currentUid();
    if (Hive.isBoxOpen('quick_stats_cache')) {
      final box = Hive.box('quick_stats_cache');
      totalUploadedSessions =
          (box.get(_cacheSessionsKey(uid), defaultValue: 0) as num).toInt();
      _cachedTopSpeed =
          (box.get(_cacheTopSpeedKey(uid), defaultValue: 0.0) as num)
              .toDouble();
    }
    if (Hive.isBoxOpen('speedBox')) {
      final stored = Hive.box('speedBox').get('allSpeeds_$uid');
      if (stored is List) {
        final speeds = stored.whereType<num>().map((value) {
          return value.toDouble();
        }).toList();
        speedHistory = speeds.length > 6
            ? speeds.sublist(speeds.length - 6)
            : speeds;
      }
    }
  }

  bool get _isHomeTabVisible => MainNavigation.activeTabNotifier.value == 0;

  void _handleTabVisibilityChange() {
    if (_isHomeTabVisible) {
      _startStatsAutoSlide();
      _startAnalysisCountdownTicker();
      _resumeHomeAnimations();
      _scheduleGreetingRefresh();
      _refreshGreeting();
      unawaited(_syncQuickStats());
      unawaited(_syncAnalysisTwoMinuteReminders());
      return;
    }
    _statsTimer?.cancel();
    _analysisCountdownTicker?.cancel();
    _analysisCountdownTicker = null;
    _greetingTimer?.cancel();
    _pauseHomeAnimations();
  }

  void _startAnalysisCountdownTicker() {
    if (_analysisCountdownTicker != null) return;
    _analysisCountdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isHomeTabVisible) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final hasActiveAnalysis = Hive.box<PendingVideo>('pending_videos').values
          .any(
            (video) =>
                uid != null &&
                video.userId == uid &&
                (video.status == 'pending' || video.status == 'uploading'),
          );
      if (hasActiveAnalysis) {
        _analysisClockTick.value++;
      }
    });
  }

  String _analysisTimerStartedKey(String jobId) {
    return '$_analysisTimerStartedPrefix$jobId';
  }

  String _analysisMessageShownKey(String jobId) {
    return '$_analysisMessageShownPrefix$jobId';
  }

  DateTime _analysisReminderDueAt(PendingVideo video) {
    return DateTime.fromMillisecondsSinceEpoch(
      video.timestamp,
    ).add(_analysisUploadReminderDelay);
  }

  Duration _analysisReminderRemaining(PendingVideo video) {
    final remaining = _analysisReminderDueAt(video).difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatAnalysisReminder(Duration remaining) {
    final totalSeconds = remaining.inSeconds
        .clamp(0, _analysisUploadReminderDelay.inSeconds)
        .toInt();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _syncAnalysisTwoMinuteReminders() async {
    if (_analysisReminderSyncing) return;
    _analysisReminderSyncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final box = Hive.box<PendingVideo>('pending_videos');
      final activeIds = <String>{};
      final uid = FirebaseAuth.instance.currentUser?.uid;

      for (final video in box.values) {
        if (uid == null || video.userId != uid) {
          continue;
        }
        if (!(prefs.getBool(_analysisTimerStartedKey(video.id)) ?? false)) {
          continue;
        }
        if (prefs.getBool(_analysisMessageShownKey(video.id)) ?? false) {
          continue;
        }
        if (video.status == 'complete') {
          await prefs.setBool(_analysisMessageShownKey(video.id), true);
          continue;
        }
        if (video.status == 'failed') {
          await prefs.setBool(_analysisMessageShownKey(video.id), true);
          continue;
        }
        if (video.status != 'pending' && video.status != 'uploading') {
          continue;
        }

        activeIds.add(video.id);
        if (_analysisTwoMinuteTimers.containsKey(video.id)) continue;

        final remaining = _analysisReminderDueAt(
          video,
        ).difference(DateTime.now());
        if (remaining.isNegative || remaining == Duration.zero) {
          unawaited(_showAnalysisTwoMinuteMessage(video));
        } else {
          _analysisTwoMinuteTimers[video.id] = Timer(remaining, () {
            _analysisTwoMinuteTimers.remove(video.id);
            unawaited(_showAnalysisTwoMinuteMessage(video));
          });
        }
      }

      for (final entry in _analysisTwoMinuteTimers.entries.toList()) {
        if (!activeIds.contains(entry.key)) {
          entry.value.cancel();
          _analysisTwoMinuteTimers.remove(entry.key);
        }
      }
    } finally {
      _analysisReminderSyncing = false;
    }
  }

  Future<void> _showAnalysisTwoMinuteMessage(PendingVideo video) async {
    if (!mounted || !_isHomeTabVisible) return;

    final prefs = await SharedPreferences.getInstance();
    final shownKey = _analysisMessageShownKey(video.id);
    if (prefs.getBool(shownKey) ?? false) return;
    await prefs.setBool(shownKey, true);

    if (!mounted || !_isHomeTabVisible) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CrickXColors.graphite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
        duration: const Duration(milliseconds: 1700),
        content: Text(
          'Analysis update ready. Open your video queue.',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: CrickXColors.textPrimary),
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: CrickXColors.limeSpark,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AnalyzingVideosScreen()),
            );
          },
        ),
      ),
    );
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
            'We\'ll use notifications for things like analysis-complete alerts, practice nudges, and (if you start a free trial) a reminder 1 day before your trial ends. You can turn these off anytime in your phone settings.',
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
          duration: const Duration(milliseconds: 1700),
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
        accent: const [CrickXColors.limeSpark, Color(0xFF8CE600)],
      ),
      _QuickStatData(
        title: "Quick Stats",
        value: maxSpeed <= 0 ? "--" : maxSpeed.toStringAsFixed(1),
        metric: "Top Ball Speed",
        suffix: maxSpeed <= 0 ? "" : " km/h",
        accent: const [Color(0xFFD0FF66), CrickXColors.limeSpark],
      ),
      _QuickStatData(
        title: "Quick Stats",
        value: _currentPlanStatValue,
        metric: "Membership",
        accent: const [CrickXColors.limeSpark, Color(0xFF6EDC00)],
      ),
    ];
  }

  String get _currentPlanStatValue =>
      "Current Plan: ${PremiumService.isPremiumActive ? "Elite" : "Free"}";

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CrickXColors.graphiteBg,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: -120,
            child: _meshOrb(
              size: 360,
              colors: const [Colors.transparent, Colors.transparent],
            ),
          ),
          Positioned(
            top: 120,
            right: -100,
            child: _meshOrb(
              size: 280,
              colors: const [Colors.transparent, Colors.transparent],
            ),
          ),
          Positioned(
            bottom: -200,
            left: -80,
            child: _meshOrb(
              size: 300,
              colors: const [Colors.transparent, Colors.transparent],
            ),
          ),
          RefreshIndicator(
            color: CrickXColors.limeSpark,
            backgroundColor: CrickXColors.graphite,
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
                    16,
                    54,
                    16,
                    _showEliteWelcomeHeader ? 28 : 24,
                  ),
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: _showEliteWelcomeHeader ? 260 : 200,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
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
                                    ? CrickXColors.limeSpark
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
                      ValueListenableBuilder<int>(
                        valueListenable:
                            AnalysisCreditService.instance.creditsNotifier,
                        builder: (context, credits, _) {
                          final sub = !PremiumService.isPremiumActive
                              ? (credits > 0
                                  ? "$credits AI Analysis credit${credits > 1 ? 's' : ''} available"
                                  : "Watch Ad to Unlock 4 AI Analyses")
                              : "Upload Video & Get AI Analysis";
                          return _actionCard(
                            title: "Analyze My Cricket Video",
                            subtitle: sub,
                            icon: Icons.cloud_upload_rounded,
                            iconGradient: const [
                              CrickXColors.limeSpark,
                              Color(0xFF8CE600),
                            ],
                            onTap: () {
                              unawaited(
                                AppAnalytics.log(
                                  'upload_clicked',
                                  parameters: {'source': 'home'},
                                ),
                              );
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => const UploadScreen(),
                                    ),
                                  )
                                  .then((_) => _syncQuickStats());
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _actionCard(
                        title: "Cricknova Analyse Yourself",
                        subtitle:
                            "Compare batting clips and find technique gaps",
                        icon: Icons.analytics_rounded,
                        iconGradient: const [
                          CrickXColors.limeSpark,
                          Color(0xFF6EDC00),
                        ],
                        onTap: () {
                          if (!PremiumService.isLoaded) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Checking premium status..."),
                                duration: Duration(milliseconds: 1700),
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
                                PageRouteBuilder(
                                  transitionDuration: const Duration(
                                    milliseconds: 320,
                                  ),
                                  pageBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) => const AnalyseYourselfScreen(),
                                  transitionsBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale:
                                                Tween<double>(
                                                  begin: 0.98,
                                                  end: 1.0,
                                                ).animate(
                                                  CurvedAnimation(
                                                    parent: animation,
                                                    curve: Curves.easeOut,
                                                  ),
                                                ),
                                            child: child,
                                          ),
                                        );
                                      },
                                ),
                              )
                              .then((_) => _syncQuickStats());
                        },
                      ),
                      const SizedBox(height: 14),
                      _actionCard(
                        title: "Bowling Analysis",
                        subtitle:
                            "Check bowling speed, swing, spin and mistake detection",
                        icon: Icons.sports_baseball_rounded,
                        iconGradient: const [
                          CrickXColors.limeSpark,
                          Color(0xFF8CE600),
                        ],
                        onTap: () {
                          if (!PremiumService.isLoaded) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Checking premium status..."),
                                duration: Duration(milliseconds: 1700),
                              ),
                            );
                            return;
                          }

                          Navigator.of(context)
                              .push(
                                PageRouteBuilder(
                                  transitionDuration: const Duration(
                                    milliseconds: 320,
                                  ),
                                  pageBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) => const BowlingAnalyseScreen(),
                                  transitionsBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale:
                                                Tween<double>(
                                                  begin: 0.98,
                                                  end: 1.0,
                                                ).animate(
                                                  CurvedAnimation(
                                                    parent: animation,
                                                    curve: Curves.easeOut,
                                                  ),
                                                ),
                                            child: child,
                                          ),
                                        );
                                      },
                                ),
                              )
                              .then((_) => _syncQuickStats());
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                _exclusiveTrainingVidSection(),

                const SizedBox(height: 50),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _remainingFeaturesSection(),
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
    return Container(
      padding: const EdgeInsets.all(16),
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
            offset: const Offset(0, 8),
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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: stat.value,
                          style: GoogleFonts.poppins(
                            fontSize: stat.metric == "Membership" ? 21 : 28,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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

  Widget _remainingFeaturesSection() {
    return Column(
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
        _remainingFeaturesCard(),
      ],
    );
  }

  Widget _remainingFeaturesCard() {
    final content = Container(
      padding: const EdgeInsets.all(16),
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
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Premium",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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
            label: "Cricknova Mistake Detection",
            used: PremiumService.mistakeUsed,
            total: PremiumService.mistakeLimit,
          ),
          const SizedBox(height: 10),
          _usageRow(
            label: "Cricknova Analyse Yourself",
            used: PremiumService.compareUsed,
            total: PremiumService.compareLimit,
          ),
        ],
      ),
    );

    if (PremiumService.isPremium) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _openPremiumFromRemainingFeatures,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: _lockedRemainingFeaturesPreview(),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    border: Border.all(
                      color: Colors.white12,
                      width: 1,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: CrickXColors.graphite,
                  border: Border.all(
                    color: CrickXColors.limeSpark.withValues(alpha: 0.55),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_open_rounded,
                      color: CrickXColors.limeSpark,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Access All Features",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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

  Widget _lockedRemainingFeaturesPreview() {
    Widget softLine(double widthFactor, {double height = 14}) {
      return FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.26),
                Colors.white.withValues(alpha: 0.09),
              ],
            ),
          ),
        ),
      );
    }

    Widget hiddenRow(double widthFactor, Color accent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.34),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: softLine(widthFactor)),
            const SizedBox(width: 18),
            SizedBox(width: 48, child: softLine(1, height: 12)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CrickXColors.graphite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: CrickXColors.graphiteBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: softLine(0.34, height: 16)),
              SizedBox(width: 68, child: softLine(1, height: 16)),
            ],
          ),
          const SizedBox(height: 14),
          hiddenRow(0.72, CrickXColors.limeSpark),
          const SizedBox(height: 10),
          hiddenRow(0.86, CrickXColors.limeSpark),
          const SizedBox(height: 10),
          hiddenRow(0.78, CrickXColors.limeSpark),
        ],
      ),
    );
  }

  void _openPremiumFromRemainingFeatures() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PremiumScreen(entrySource: "remaining_features"),
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
                      : Colors.white,
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
          child: Container(
            decoration: BoxDecoration(
              color: CrickXColors.graphite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: CrickXColors.graphiteBorder),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _EliteStadiumBackdropPainter(
                        opacity: 0.35 * progress,
                        slot: greetingTheme.slot,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  top: 14,
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
                          color: CrickXColors.limeSpark,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: welcomeOpacity,
                        child: Text(
                          shortGreeting,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.15,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 140 * lineProgress,
                          height: 1.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: accentColors),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _greeting.userName.isNotEmpty
                            ? _greeting.userName
                            : "Player",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color.lerp(
                            const Color(0xFFEAF6FF),
                            Colors.white,
                            pulse,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

  Widget _exclusiveTrainingVidSection() {
    void openAnalysisQueue() {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AnalyzingVideosScreen()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                PremiumService.isElite
                    ? "Exclusive Training Vid"
                    : "Training Videos",
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              GestureDetector(
                onTap: openAnalysisQueue,
                child: Text(
                  "See All",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CrickXColors.limeSpark,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: ValueListenableBuilder(
            valueListenable: Hive.box<PendingVideo>(
              'pending_videos',
            ).listenable(),
            builder: (context, Box<PendingVideo> box, _) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              final videos = box.values
                  .where((video) => uid != null && video.userId == uid)
                  .toList()
                  .reversed
                  .take(5)
                  .toList();

              if (videos.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: CrickXColors.graphiteBorder,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.video_library_outlined,
                          color: Colors.white30,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "No videos analyzed yet",
                          style: GoogleFonts.poppins(
                            color: Colors.white30,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  final bool isReady = video.status == 'complete';

                  return GestureDetector(
                    onTap: isReady
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AnalysisResultScreen(jobId: video.id),
                              ),
                            );
                          }
                        : () => _showTrackingInProgressDialog(video),
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: CrickXColors.graphite,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isReady
                              ? CrickXColors.limeSpark.withValues(alpha: 0.5)
                              : CrickXColors.graphiteBorder,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isReady
                                ? CrickXColors.limeSpark.withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: 0.6),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF2B2F3A),
                                          Color(0xFF1B1D25),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.sports_cricket_rounded,
                                    color: isReady
                                        ? CrickXColors.limeSpark
                                        : Colors.white24,
                                    size: 40,
                                  ),
                                  if (!isReady)
                                    const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: CrickXColors.limeSpark,
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
                                ValueListenableBuilder<int>(
                                  valueListenable: _analysisClockTick,
                                  builder: (context, _, child) {
                                    final liveRemaining =
                                        _analysisReminderRemaining(video);
                                    final liveStatusText = isReady
                                        ? "Ready"
                                        : liveRemaining == Duration.zero
                                        ? "2 min complete"
                                        : "Timer ${_formatAnalysisReminder(liveRemaining)}";
                                    return Text(
                                      liveStatusText,
                                      style: GoogleFonts.poppins(
                                        color: isReady
                                            ? CrickXColors.limeSpark
                                            : Colors.white60,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  video.localFilePath
                                      .split(RegExp(r'[\\/]'))
                                      .last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showTrackingInProgressDialog(PendingVideo video) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: CrickXColors.graphite,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 200,
                        width: double.infinity,
                        color: Colors.black54,
                        child: const Icon(
                          Icons.videocam_outlined,
                          color: Colors.white24,
                          size: 60,
                        ),
                      ),
                      const SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: CrickXColors.limeSpark,
                        ),
                      ),
                      Column(
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: CrickXColors.limeSpark,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "TRACKING ACTIVE",
                            style: GoogleFonts.poppins(
                              color: CrickXColors.limeSpark,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        "AI Analysis in Progress",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "CrickNova is currently tracking trajectory, swing, and spin for ${video.localFilePath.split(RegExp(r'[\\/]')).last}.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white60,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Center(
                            child: Text(
                              "Close",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
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
    );
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _analysisCountdownTicker?.cancel();
    _analysisClockTick.dispose();
    for (final timer in _analysisTwoMinuteTimers.values) {
      timer.cancel();
    }
    _analysisTwoMinuteTimers.clear();
    _greetingTimer?.cancel();
    _pauseHomeAnimations();
    MainNavigation.activeTabNotifier.removeListener(_handleTabVisibilityChange);
    _statsBoxSub?.cancel();
    _speedBoxSub?.cancel();
    _pendingVideosSub?.cancel();
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
  final GreetingTimeSlot slot;

  _EliteStadiumBackdropPainter({required this.opacity, required this.slot});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final now = DateTime.now();
    final isNight = slot == GreetingTimeSlot.midnight;
    final sunProgress = _sunProgress(now);
    final sunCenter = Offset(
      size.width * sunProgress,
      size.height * (isNight ? 0.62 : 0.18),
    );
    final moonVisible = isNight && _moonIllumination(now) > 0.14;
    final moonCenter = Offset(size.width * 0.72, size.height * 0.17);

    final skyOrb = Paint()
      ..shader =
          RadialGradient(
            colors: isNight
                ? [
                    const Color(0xFFBFD8FF).withValues(alpha: 0.20 * opacity),
                    Colors.transparent,
                  ]
                : [
                    const Color(0xFFFFF0B0).withValues(alpha: 0.22 * opacity),
                    Colors.transparent,
                  ],
          ).createShader(
            Rect.fromCircle(center: sunCenter, radius: size.width * 0.28),
          )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(sunCenter, size.width * 0.10, skyOrb);

    if (moonVisible) {
      final moonGlow = Paint()
        ..shader =
            const RadialGradient(
              colors: [Color(0xAAFFFFFF), Color(0x00FFFFFF)],
            ).createShader(
              Rect.fromCircle(center: moonCenter, radius: size.width * 0.16),
            )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(moonCenter, size.width * 0.05, moonGlow);

      final moon = Paint()
        ..color = Colors.white.withValues(alpha: 0.82 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(moonCenter, size.width * 0.035, moon);
    }

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

    if (!isNight) {
      final cloudPaint = Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      _drawCloud(
        canvas,
        Offset(size.width * 0.20, size.height * 0.14),
        1.0,
        cloudPaint,
      );
      _drawCloud(
        canvas,
        Offset(size.width * 0.64, size.height * 0.10),
        0.82,
        cloudPaint,
      );
    } else if (moonVisible) {
      final mistPaint = Paint()
        ..color = const Color(0xFF9DB4D6).withValues(alpha: opacity * 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      _drawCloud(
        canvas,
        Offset(size.width * 0.26, size.height * 0.12),
        0.78,
        mistPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EliteStadiumBackdropPainter oldDelegate) {
    return oldDelegate.opacity != opacity || oldDelegate.slot != slot;
  }

  double _sunProgress(DateTime now) {
    final minutes = (now.hour * 60) + now.minute + (now.second / 60.0);
    final clamped = minutes.clamp(300.0, 1260.0);
    return (clamped - 300.0) / (1260.0 - 300.0);
  }

  double _moonIllumination(DateTime now) {
    final epochDays =
        now.toUtc().millisecondsSinceEpoch / Duration.millisecondsPerDay;
    final synodicMonth = 29.53058867;
    final phase = (epochDays / synodicMonth) % 1.0;
    final illuminated = (1 - (math.cos(phase * math.pi * 2) * -1));
    return (illuminated / 2).clamp(0.0, 1.0);
  }

  void _drawCloud(Canvas canvas, Offset origin, double scale, Paint paint) {
    final r = 18.0 * scale;
    canvas.drawCircle(origin + Offset(-r * 0.7, 0), r * 0.72, paint);
    canvas.drawCircle(origin + Offset(0, -r * 0.26), r, paint);
    canvas.drawCircle(origin + Offset(r * 0.72, 0), r * 0.78, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: origin, width: r * 3.0, height: r * 1.45),
        Radius.circular(r),
      ),
      paint,
    );
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
