import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/premium_service.dart';
import '../premium/premium_screen.dart';
import '../premium/elite_status_screen.dart';
import '../upload/upload_screen.dart';
import '../compare/analyse_yourself_screen.dart';
import '../premium/premium_expired_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userName;

  const HomeScreen({super.key, required this.userName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int totalUploadedSessions = 0;
  List<double> speedHistory = [];
  double _cachedTopSpeed = 0.0;
  bool _lastPremiumState = PremiumService.isPremiumActive;

  final PageController _statsPageController = PageController(
    viewportFraction: 0.9,
  );
  Timer? _statsTimer;
  Timer? _quickStatsSyncTimer;
  bool _quickStatsSyncInProgress = false;
  StreamSubscription? _statsBoxSub;
  StreamSubscription? _speedBoxSub;
  int _currentStatsPage = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _onPremiumChanged() {
    if (!mounted) return;
    final next = PremiumService.isPremiumActive;
    if (next == _lastPremiumState) return;
    _lastPremiumState = next;
    _saveQuickStatsToHive();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifeCycleObserver);

    PremiumService.premiumNotifier.addListener(_onPremiumChanged);
    PremiumService.premiumNotifier.addListener(_checkExpiryPopup);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkExpiryPopup();
    });

    _startStatsAutoSlide();
    _startQuickStatsSync();
    _initRealtimeQuickStatsListeners();
    _bootstrapAuthAndData();
  }

  late final WidgetsBindingObserver _lifeCycleObserver = _HomeLifecycleObserver(
    onResumed: _syncQuickStats,
  );

  Future<void> _bootstrapAuthAndData() async {
    await _loadQuickStatsFromHive();
    if (mounted) setState(() {});

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final String? token = await user.getIdToken(true);
      if (token != null && token.isNotEmpty) {
        // Token refresh succeeded.
      } else {
        debugPrint("⚠️ HOME SCREEN: Firebase token is null or empty");
      }

      await PremiumService.restoreOnLaunch();
      _checkExpiryPopup();
    }

    await loadSpeedHistory();
    await loadTrainingVideos();
    await _saveQuickStatsToHive();
    if (!mounted) return;
    setState(() {});
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

  void _startQuickStatsSync() {
    _quickStatsSyncTimer?.cancel();
    _quickStatsSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _syncQuickStats();
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
            onRefresh: () async {
              await PremiumService.restoreOnLaunch();
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
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 28),
                  width: double.infinity,
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
                      Text(
                        "Welcome back, ${widget.userName}",
                        style: GoogleFonts.poppins(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Ready for today’s cricket analysis?",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.64),
                        ),
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

                          if (!PremiumService.isPremiumActive) {
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
                                  label: "AI Coach Chats",
                                  used: PremiumService.chatUsed,
                                  total: PremiumService.chatLimit,
                                ),
                                const SizedBox(height: 10),
                                _usageRow(
                                  label: "Mistake Detection",
                                  used: PremiumService.mistakeUsed,
                                  total: PremiumService.mistakeLimit,
                                ),
                                if (PremiumService.compareLimit > 0) ...[
                                  const SizedBox(height: 10),
                                  _usageRow(
                                    label: "Analyse Yourself",
                                    used: PremiumService.compareUsed,
                                    total: PremiumService.compareLimit,
                                  ),
                                ],
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
    _quickStatsSyncTimer?.cancel();
    _statsBoxSub?.cancel();
    _speedBoxSub?.cancel();
    _statsPageController.dispose();
    WidgetsBinding.instance.removeObserver(_lifeCycleObserver);
    PremiumService.premiumNotifier.removeListener(_onPremiumChanged);
    PremiumService.premiumNotifier.removeListener(_checkExpiryPopup);
    super.dispose();
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
