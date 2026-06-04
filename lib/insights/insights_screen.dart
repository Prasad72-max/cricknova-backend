import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:confetti/confetti.dart';
import 'performance_certificate.dart';
import 'certificate_preview_screen.dart';
import 'dart:math' as math;
import '../services/premium_service.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<double> speedHistory = [];
  int currentSessionIndex = 0;
  List<List<double>> sessions = [];
  String userName = "Player";
  String? _currentUid;
  StreamSubscription<User?>? _authSub;
  late ConfettiController _confettiController;
  late AnimationController _entranceController;
  late Box _speedBox;
  Box? _statsBox;
  bool _loadingSpeedHistory = false;
  DateTime? _lastSpeedLoadAt;

  String get _storageUid =>
      FirebaseAuth.instance.currentUser?.uid ?? (_currentUid ?? "guest");

  Future<Box> _getStatsBox(String uid) async {
    final boxName = "local_stats_$uid";
    if (_statsBox != null && _statsBox!.name == boxName) {
      return _statsBox!;
    }
    _statsBox = await Hive.openBox(boxName);
    return _statsBox!;
  }

  Future<void> _loadCertificateName() async {
    final uid = _storageUid;
    _currentUid = uid;
    String resolved = "Player";
    try {
      final box = await _getStatsBox(uid);
      final name = (box.get("profileName") as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        resolved = name;
      } else {
        final email = FirebaseAuth.instance.currentUser?.email?.trim();
        if (email != null && email.isNotEmpty) resolved = email;
      }
    } catch (_) {
      final email = FirebaseAuth.instance.currentUser?.email?.trim();
      if (email != null && email.isNotEmpty) resolved = email;
    }

    userName = resolved;
  }

  @override
  void initState() {
    super.initState();
    _initHive();

    WidgetsBinding.instance.addObserver(this);

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    // Listen to auth changes so graph updates when user changes
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;

      if (user == null) {
        // User logged out → clear UI safely
        _currentUid = null;
        speedHistory = <double>[];
        sessions = <List<double>>[];
        currentSessionIndex = 0;
        if (mounted) setState(() {});
        return;
      }

      final newUid = user.uid;

      if (_currentUid == newUid) return;

      _currentUid = newUid;
      if (Hive.isBoxOpen('speedBox')) {
        await _loadSpeedHistory();
      }
    });
  }

  Future<void> _initHive() async {
    _speedBox = await Hive.openBox('speedBox');

    final user = FirebaseAuth.instance.currentUser;
    _currentUid = user?.uid ?? "guest";

    await _loadSpeedHistory();
  }

  Future<void> _loadSpeedHistory() async {
    if (_loadingSpeedHistory) return;
    final now = DateTime.now();
    if (_lastSpeedLoadAt != null &&
        now.difference(_lastSpeedLoadAt!).inMilliseconds < 800) {
      return;
    }
    _loadingSpeedHistory = true;
    try {
      if (!Hive.isBoxOpen('speedBox')) return;
      sessions = <List<double>>[];
      speedHistory = <double>[];
      currentSessionIndex = 0;

      final uid = _storageUid;
      _currentUid = uid;
      final storedSpeeds = _speedBox.get('allSpeeds_$uid') as List?;

      if (storedSpeeds != null) {
        final List<double> flatSpeeds = storedSpeeds
            .map((e) => (e as num).toDouble())
            .toList();

        sessions = <List<double>>[];

        for (int i = 0; i < flatSpeeds.length; i += 6) {
          final end = (i + 6 <= flatSpeeds.length) ? i + 6 : flatSpeeds.length;
          sessions.add(flatSpeeds.sublist(i, end));
        }

        if (sessions.isNotEmpty) {
          currentSessionIndex = sessions.length - 1;
          speedHistory = sessions[currentSessionIndex];
        }
      }

      _syncCurrentSessionViews();

      await _loadCertificateName();
      _lastSpeedLoadAt = DateTime.now();
      if (mounted) setState(() {});
    } finally {
      _loadingSpeedHistory = false;
    }
  }

  Future<void> _clearAllSessions() async {
    await _speedBox.delete('allSpeeds_$_storageUid');
    sessions = <List<double>>[];
    speedHistory = <double>[];
    currentSessionIndex = 0;

    if (mounted) setState(() {});
  }

  Future<void> _deleteCurrentSession() async {
    if (_sessionCount == 0) return;

    sessions.removeAt(currentSessionIndex);

    // rebuild flat list after deletion
    final List<double> rebuiltFlat = sessions.expand((e) => e).toList();
    await _speedBox.put('allSpeeds_$_storageUid', rebuiltFlat);

    if (sessions.isNotEmpty) {
      if (currentSessionIndex >= sessions.length) {
        currentSessionIndex = sessions.length - 1;
      }
      speedHistory = sessions[currentSessionIndex];
    } else {
      currentSessionIndex = 0;
      speedHistory = <double>[];
    }

    if (mounted) setState(() {});
  }

  Future<void> addNewSession(List<double> newSpeeds) async {
    if (newSpeeds.isEmpty) return;

    final storedSpeeds = _speedBox.get('allSpeeds_$_storageUid') as List?;
    List<double> flatSpeeds = [];

    if (storedSpeeds != null) {
      flatSpeeds = storedSpeeds.map((e) => (e as num).toDouble()).toList();
    }

    flatSpeeds.addAll(newSpeeds);

    await _speedBox.put('allSpeeds_$_storageUid', flatSpeeds);

    // Rebuild sessions
    sessions = <List<double>>[];

    for (int i = 0; i < flatSpeeds.length; i += 6) {
      final end = (i + 6 <= flatSpeeds.length) ? i + 6 : flatSpeeds.length;
      sessions.add(flatSpeeds.sublist(i, end));
    }

    currentSessionIndex = sessions.length - 1;
    speedHistory = sessions.last;

    if (mounted) setState(() {});
  }

  void _syncCurrentSessionViews() {
    speedHistory = currentSessionIndex < sessions.length
        ? sessions[currentSessionIndex]
        : <double>[];
  }

  int get _sessionCount => sessions.length;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _confettiController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSpeedHistory();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Reload speeds whenever returning to this screen
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Future.microtask(() => _loadSpeedHistory());
    }
  }

  List<double> _deriveAccuracyScores(List<double> speeds) {
    if (speeds.isEmpty) return <double>[];
    final mean = speeds.reduce((a, b) => a + b) / speeds.length;
    final deltas = speeds.map((s) => (s - mean).abs()).toList();
    final maxDelta = deltas.reduce(math.max);
    if (maxDelta == 0) {
      return List<double>.filled(speeds.length, 95);
    }
    return deltas.map((d) {
      final score = 100 - ((d / maxDelta) * 25);
      return score.clamp(60, 100).toDouble();
    }).toList();
  }

  double _avgAccuracyPercent(List<double> speeds) {
    final scores = _deriveAccuracyScores(speeds);
    if (scores.isEmpty) return 0;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  double _averageSpeed(List<double> speeds) {
    if (speeds.isEmpty) return 0;
    return speeds.reduce((a, b) => a + b) / speeds.length;
  }

  double _topSpeed(List<double> speeds) {
    if (speeds.isEmpty) return 0;
    return speeds.reduce(math.max).toDouble();
  }

  List<double> get _allSpeeds =>
      sessions.expand((session) => session).toList(growable: false);

  double _consistencyPercent(List<double> speeds) {
    if (speeds.isEmpty) return 0;
    final accuracy = _avgAccuracyPercent(speeds);
    final avg = _averageSpeed(speeds);
    final variance =
        speeds.map((s) => math.pow(s - avg, 2)).reduce((a, b) => a + b) /
        speeds.length;
    final stability = 100 - (math.sqrt(variance) * 2.8);
    return ((accuracy * 0.55) + (stability.clamp(0, 100) * 0.45)).clamp(0, 100);
  }

  int _performanceScore(double topSpeed, double accuracy, double consistency) {
    final speedScore = (topSpeed / 140 * 100).clamp(0, 100);
    return ((speedScore * 0.42) + (accuracy * 0.32) + (consistency * 0.26))
        .round()
        .clamp(0, 100);
  }

  int _longestConsistencyStreak() {
    var best = 0;
    var current = 0;
    for (final session in sessions) {
      for (final score in _deriveAccuracyScores(session)) {
        if (score >= 85) {
          current++;
          best = math.max(best, current);
        } else {
          current = 0;
        }
      }
    }
    return best;
  }

  List<String> _buildInsightLines(List<double> speeds, double accuracy) {
    if (speeds.isEmpty) {
      return const [
        "Complete a session to unlock CrickNova's performance readout.",
        "Speed, accuracy and consistency will be profiled together.",
        "Your next tracked ball starts the analytics timeline.",
      ];
    }
    final top = _topSpeed(speeds);
    final last = speeds.last;
    final first = speeds.first;
    final recoveryText = speeds.length >= 3 && speeds.last > speeds[1]
        ? "You recovered strongly after Ball 2."
        : "Your pace profile stayed composed across the session.";
    final finishText = (top - last).abs() < 0.6
        ? "Your final delivery matched your session-best speed."
        : last >= first
        ? "You finished faster than you started."
        : "Your peak pace arrived earlier, with a controlled finish.";
    final accuracyText = accuracy >= 80
        ? "Accuracy remained stable throughout the session."
        : "Accuracy has room to tighten as pace increases.";
    return [recoveryText, finishText, accuracyText];
  }

  String _sessionDurationLabel() {
    if (speedHistory.isEmpty) return "--";
    final seconds = math.max(45, speedHistory.length * 28);
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    if (minutes == 0) return "${remaining}s";
    return "${minutes}m ${remaining}s";
  }

  Future<void> _showDeleteOptions() async {
    if (_sessionCount == 0) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF07111F),
        title: const Text(
          "Delete Options",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Choose what you want to remove.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, "specific"),
            child: const Text(
              "This Session",
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, "all"),
            child: const Text(
              "All Sessions",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    final title = choice == "specific"
        ? "Delete This Session?"
        : "Delete All Sessions?";
    final body = choice == "specific"
        ? "Session ${currentSessionIndex + 1} will be permanently deleted."
        : "This will permanently delete all your bowling sessions.";
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF07111F),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          "$body This cannot be recovered.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (choice == "specific") {
      await _deleteCurrentSession();
    } else {
      await _clearAllSessions();
    }
  }

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF07111F),
        content: Text(
          "$label will be available soon.",
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  Future<void> _generateCertificate() async {
    if (speedHistory.isEmpty) return;
    final currentSpeeds = List<double>.from(speedHistory);
    final double top = _topSpeed(currentSpeeds);
    final double avg = _averageSpeed(currentSpeeds);
    final accuracyPercent = _avgAccuracyPercent(currentSpeeds);

    if (top < 95 || accuracyPercent <= 72) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF111827),
          content: Text(
            "Certificate unlocks at 95+ KMPH and above 72% accuracy. "
            "Your session: ${top.toStringAsFixed(0)} KMPH, ${accuracyPercent.toStringAsFixed(0)}%.",
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
          ),
        ),
      );
      return;
    }

    _confettiController.play();
    final sessionXp = currentSpeeds.length * 12;
    final sessionId = "${DateTime.now().millisecondsSinceEpoch}";
    const appLink = "https://cricknova-5f94f.web.app";
    final serial = buildCertificateSerial(sessionId);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CertificatePreviewScreen(
          playerName: userName,
          topSpeed: top,
          avgSpeed: avg,
          accuracyPercent: accuracyPercent,
          sessionXp: sessionXp,
          speedSeries: currentSpeeds,
          sessionId: sessionId,
          appLink: appLink,
          certificateSerial: serial,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionCount = _sessionCount;
    final accuracyScores = _deriveAccuracyScores(speedHistory);
    final avgAccuracy = _avgAccuracyPercent(speedHistory);
    final topSpeed = _topSpeed(speedHistory);
    final avgSpeed = _averageSpeed(speedHistory);
    final consistency = _consistencyPercent(speedHistory);
    final performanceScore = _performanceScore(
      topSpeed,
      avgAccuracy,
      consistency,
    );
    final allSpeeds = _allSpeeds;
    final fastestEver = _topSpeed(allSpeeds);
    final bestAccuracyEver = sessions.isEmpty
        ? 0.0
        : sessions
              .map(_avgAccuracyPercent)
              .fold<double>(0, (best, value) => math.max(best, value));
    final hasPersonalBest =
        speedHistory.isNotEmpty && fastestEver > 0 && topSpeed >= fastestEver;
    final canGenerateCertificate =
        speedHistory.isNotEmpty && topSpeed >= 95 && avgAccuracy > 72;
    final goalProgress = (topSpeed / 140).clamp(0.0, 1.0).toDouble();
    final insightLines = _buildInsightLines(speedHistory, avgAccuracy);

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF22D3EE),
          backgroundColor: const Color(0xFF0F172A),
          notificationPredicate: (notification) {
            return PremiumService.isPremiumActive && notification.depth == 0;
          },
          onRefresh: () async {
            if (!PremiumService.isPremiumActive) return;
            await PremiumService.refresh();
            await _loadSpeedHistory();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              _AnalyticsHeader(
                sessionCount: sessionCount,
                onMenuSelected: (value) {
                  if (value == "delete") {
                    _showDeleteOptions();
                  } else if (value == "share") {
                    _showComingSoon("Share Session");
                  } else if (value == "export") {
                    _showComingSoon("Export Data");
                  }
                },
              ),
              const SizedBox(height: 18),
              _Entrance(
                controller: _entranceController,
                order: 0,
                child: _HeroPerformanceCard(
                  score: performanceScore,
                  topSpeed: topSpeed,
                  accuracy: avgAccuracy,
                  consistency: consistency,
                  isPersonalBest: hasPersonalBest,
                ),
              ),
              const SizedBox(height: 16),
              _Entrance(
                controller: _entranceController,
                order: 1,
                child: _AiInsightCard(lines: insightLines),
              ),
              const SizedBox(height: 16),

              if (sessionCount > 1)
                _SessionSwitcher(
                  label: "Session ${currentSessionIndex + 1}/$sessionCount",
                  canGoBack: currentSessionIndex > 0,
                  canGoForward: currentSessionIndex < sessionCount - 1,
                  onBack: () {
                    setState(() {
                      currentSessionIndex--;
                      _syncCurrentSessionViews();
                    });
                  },
                  onForward: () {
                    setState(() {
                      currentSessionIndex++;
                      _syncCurrentSessionViews();
                    });
                  },
                ),

              const SizedBox(height: 16),
              _Entrance(
                controller: _entranceController,
                order: 2,
                child: _ChartTelemetryCard(
                  title: "Speed Trend",
                  subtitle:
                      "Session average ${avgSpeed.toStringAsFixed(1)} km/h",
                  accent: const Color(0xFF22D3EE),
                  child: speedHistory.isEmpty
                      ? const _EmptyAnalyticsState(
                          message: "No speed data yet.",
                        )
                      : InteractiveSpeedChart(speeds: speedHistory),
                ),
              ),
              const SizedBox(height: 16),
              _Entrance(
                controller: _entranceController,
                order: 3,
                child: _ChartTelemetryCard(
                  title: "Accuracy Trend",
                  subtitle: "Derived from release-speed consistency",
                  accent: const Color(0xFFFFD166),
                  height: 260,
                  child: accuracyScores.isEmpty
                      ? const _EmptyAnalyticsState(
                          message: "No accuracy data yet.",
                        )
                      : InteractiveAccuracyChart(accuracy: accuracyScores),
                ),
              ),
              const SizedBox(height: 16),
              _Entrance(
                controller: _entranceController,
                order: 4,
                child: _SessionDetailsCard(
                  date: DateTime.now(),
                  duration: _sessionDurationLabel(),
                  ballsTracked: speedHistory.length,
                  trainingType: "Bowling Analytics",
                ),
              ),
              const SizedBox(height: 16),
              _Entrance(
                controller: _entranceController,
                order: 5,
                child: _PersonalRecordsCard(
                  fastestBall: fastestEver,
                  bestAccuracy: bestAccuracyEver,
                  longestStreak: _longestConsistencyStreak(),
                ),
              ),
              const SizedBox(height: 16),
              _Entrance(
                controller: _entranceController,
                order: 6,
                child: _GoalTrackerCard(
                  speed: topSpeed,
                  target: 140,
                  progress: goalProgress,
                ),
              ),
              const SizedBox(height: 16),
              _Entrance(
                controller: _entranceController,
                order: 7,
                child: _AchievementsCard(
                  topSpeed: topSpeed,
                  accuracy: avgAccuracy,
                  consistency: consistency,
                ),
              ),
              const SizedBox(height: 20),
              _PremiumCertificateButton(
                enabled: speedHistory.isNotEmpty,
                unlocked: canGenerateCertificate,
                onPressed: _generateCertificate,
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({
    required this.sessionCount,
    required this.onMenuSelected,
  });

  final int sessionCount;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Analytics",
                style: GoogleFonts.poppins(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sessionCount == 0
                    ? "Elite cricket performance telemetry"
                    : "$sessionCount tracked session${sessionCount == 1 ? '' : 's'}",
                style: GoogleFonts.poppins(
                  color: const Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          color: const Color(0xFF07111F),
          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
          onSelected: onMenuSelected,
          itemBuilder: (context) => const [
            PopupMenuItem(value: "share", child: Text("Share Session")),
            PopupMenuItem(value: "export", child: Text("Export Data")),
            PopupMenuDivider(),
            PopupMenuItem(
              value: "delete",
              child: Text(
                "Delete Session",
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.controller,
    required this.order,
    required this.child,
  });

  final AnimationController controller;
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (order * 0.065).clamp(0.0, 0.7);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor = const Color(0x2638BDF8),
    this.gradient,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color borderColor;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            gradient:
                gradient ??
                LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.095),
                    Colors.white.withValues(alpha: 0.035),
                  ],
                ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22D3EE).withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AnimatedMetricText extends StatelessWidget {
  const _AnimatedMetricText({
    required this.value,
    required this.suffix,
    required this.style,
    this.decimals = 0,
  });

  final double value;
  final String suffix;
  final TextStyle style;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return Text(
          "${animated.toStringAsFixed(decimals)}$suffix",
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

class _HeroPerformanceCard extends StatelessWidget {
  const _HeroPerformanceCard({
    required this.score,
    required this.topSpeed,
    required this.accuracy,
    required this.consistency,
    required this.isPersonalBest,
  });

  final int score;
  final double topSpeed;
  final double accuracy;
  final double consistency;
  final bool isPersonalBest;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(20),
      borderColor: const Color(0x6638BDF8),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF082032).withValues(alpha: 0.95),
          const Color(0xFF020617).withValues(alpha: 0.92),
          const Color(0xFF111827).withValues(alpha: 0.9),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Performance Score",
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFBAE6FD),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isPersonalBest)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.65, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOut,
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD166).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFFFFD166).withValues(alpha: 0.55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD166).withValues(alpha: 0.2),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Text(
                      "🚀 New Personal Best",
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFFFD166),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AnimatedMetricText(
                value: score.toDouble(),
                suffix: "",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  "/100",
                  style: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            score >= 75
                ? "Strong session. Pace and control are trending upward."
                : "Building session. Lock rhythm, then push pace.",
            style: GoogleFonts.poppins(
              color: const Color(0xFFCBD5E1),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroMiniMetric(
                  label: "Top Speed",
                  value: topSpeed,
                  suffix: " km/h",
                  decimals: 1,
                  color: const Color(0xFF22D3EE),
                ),
              ),
              Expanded(
                child: _HeroMiniMetric(
                  label: "Accuracy",
                  value: accuracy,
                  suffix: "%",
                  color: const Color(0xFFFFD166),
                ),
              ),
              Expanded(
                child: _HeroMiniMetric(
                  label: "Consistency",
                  value: consistency,
                  suffix: "%",
                  color: const Color(0xFF34D399),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMiniMetric extends StatelessWidget {
  const _HeroMiniMetric({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
    this.decimals = 0,
  });

  final String label;
  final double value;
  final String suffix;
  final Color color;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnimatedMetricText(
          value: value,
          suffix: suffix,
          decimals: decimals,
          style: GoogleFonts.poppins(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white54,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      borderColor: const Color(0x5538BDF8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF22D3EE).withValues(alpha: 0.14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22D3EE).withValues(alpha: 0.22),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF22D3EE),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "CrickNova Insight",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      color: Color(0xFF22D3EE),
                      size: 6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFDDE7F3),
                        fontSize: 12.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
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

class _SessionSwitcher extends StatelessWidget {
  const _SessionSwitcher({
    required this.label,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final String label;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoBack ? onBack : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: const Color(0xFF22D3EE),
            disabledColor: Colors.white24,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: canGoForward ? onForward : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: const Color(0xFF22D3EE),
            disabledColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}

class _ChartTelemetryCard extends StatelessWidget {
  const _ChartTelemetryCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.child,
    this.height = 300,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              color: Colors.white54,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

class _EmptyAnalyticsState extends StatelessWidget {
  const _EmptyAnalyticsState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
      ),
    );
  }
}

class _SessionDetailsCard extends StatelessWidget {
  const _SessionDetailsCard({
    required this.date,
    required this.duration,
    required this.ballsTracked,
    required this.trainingType,
  });

  final DateTime date;
  final String duration;
  final int ballsTracked;
  final String trainingType;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/${date.year}";
    return _InfoGridCard(
      title: "Session Details",
      items: [
        ("Session Date", dateLabel),
        ("Duration", duration),
        ("Balls Tracked", ballsTracked == 0 ? "--" : "$ballsTracked"),
        ("Training Type", trainingType),
      ],
    );
  }
}

class _PersonalRecordsCard extends StatelessWidget {
  const _PersonalRecordsCard({
    required this.fastestBall,
    required this.bestAccuracy,
    required this.longestStreak,
  });

  final double fastestBall;
  final double bestAccuracy;
  final int longestStreak;

  @override
  Widget build(BuildContext context) {
    return _InfoGridCard(
      title: "Personal Records",
      gold: true,
      items: [
        (
          "Fastest Ball Ever",
          fastestBall == 0 ? "--" : "${fastestBall.toStringAsFixed(1)} km/h",
        ),
        (
          "Best Accuracy Ever",
          bestAccuracy == 0 ? "--" : "${bestAccuracy.toStringAsFixed(0)}%",
        ),
        (
          "Longest Consistency Streak",
          longestStreak == 0 ? "--" : "$longestStreak balls",
        ),
      ],
    );
  }
}

class _InfoGridCard extends StatelessWidget {
  const _InfoGridCard({
    required this.title,
    required this.items,
    this.gold = false,
  });

  final String title;
  final List<(String, String)> items;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final accent = gold ? const Color(0xFFFFD166) : const Color(0xFF22D3EE);
    return _GlassCard(
      borderColor: accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            runSpacing: 12,
            spacing: 12,
            children: [
              for (final item in items)
                SizedBox(
                  width: MediaQuery.sizeOf(context).width > 420
                      ? (MediaQuery.sizeOf(context).width - 76) / 2
                      : double.infinity,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.$2,
                          style: GoogleFonts.poppins(
                            color: accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalTrackerCard extends StatelessWidget {
  const _GoalTrackerCard({
    required this.speed,
    required this.target,
    required this.progress,
  });

  final double speed;
  final double target;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      borderColor: const Color(0x6638BDF8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Road to ${target.toStringAsFixed(0)} km/h",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                minHeight: 12,
                value: value,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF22D3EE)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "${speed.toStringAsFixed(1)} / ${target.toStringAsFixed(0)} km/h",
            style: GoogleFonts.poppins(
              color: const Color(0xFFBAE6FD),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({
    required this.topSpeed,
    required this.accuracy,
    required this.consistency,
  });

  final double topSpeed;
  final double accuracy;
  final double consistency;

  @override
  Widget build(BuildContext context) {
    final achievements = [
      ("🔥", "100+ km/h Club", topSpeed >= 100),
      ("🎯", "Accuracy Above 80%", accuracy >= 80),
      ("⚡", "Consistency Master", consistency >= 85),
    ];
    return _GlassCard(
      borderColor: const Color(0x44FFD166),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Achievements",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in achievements)
                _AchievementBadge(
                  icon: item.$1,
                  label: item.$2,
                  unlocked: item.$3,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.icon,
    required this.label,
    required this.unlocked,
  });

  final String icon;
  final String label;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final color = unlocked ? const Color(0xFFFFD166) : Colors.white38;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: unlocked
            ? const Color(0xFFFFD166).withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: unlocked ? 0.55 : 0.25),
        ),
        boxShadow: unlocked
            ? [
                BoxShadow(
                  color: const Color(0xFFFFD166).withValues(alpha: 0.18),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumCertificateButton extends StatelessWidget {
  const _PremiumCertificateButton({
    required this.enabled,
    required this.unlocked,
    required this.onPressed,
  });

  final bool enabled;
  final bool unlocked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: unlocked
              ? const [Color(0xFFFFD166), Color(0xFF22D3EE)]
              : const [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        boxShadow: [
          if (unlocked)
            BoxShadow(
              color: const Color(0xFF22D3EE).withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.emoji_events_rounded),
        label: const Text("🏆 Generate Performance Certificate"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: unlocked ? Colors.black : Colors.white70,
          disabledForegroundColor: Colors.white38,
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

// ===== SAME CHART AS HOME =====

class InteractiveSpeedChart extends StatefulWidget {
  const InteractiveSpeedChart({super.key, required this.speeds});
  final List<double> speeds;

  @override
  State<InteractiveSpeedChart> createState() => _InteractiveSpeedChartState();
}

class _InteractiveSpeedChartState extends State<InteractiveSpeedChart> {
  int? _selectedIndex;
  Timer? _clearTimer;

  void _scheduleClear() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _selectedIndex = null);
    });
  }

  void _setFromLocal(Offset local, Size size) {
    if (widget.speeds.isEmpty) return;
    final usableWidth = size.width - 40;
    if (usableWidth <= 0) return;
    final t = ((local.dx - 40) / usableWidth).clamp(0.0, 1.0);
    final idx = (t * (widget.speeds.length - 1)).round().clamp(
      0,
      widget.speeds.length - 1,
    );
    if (_selectedIndex != idx) setState(() => _selectedIndex = idx);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _setFromLocal(d.localPosition, size);
            _scheduleClear();
          },
          onPanDown: (d) => _setFromLocal(d.localPosition, size),
          onPanUpdate: (d) => _setFromLocal(d.localPosition, size),
          onPanEnd: (_) => _scheduleClear(),
          onPanCancel: _scheduleClear,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(widget.speeds.join(',')),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) {
              return CustomPaint(
                painter: SpeedChartPainter(
                  widget.speeds,
                  selectedIndex: _selectedIndex,
                  progress: progress,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        );
      },
    );
  }
}

class InteractiveAccuracyChart extends StatefulWidget {
  const InteractiveAccuracyChart({super.key, required this.accuracy});
  final List<double> accuracy;

  @override
  State<InteractiveAccuracyChart> createState() =>
      _InteractiveAccuracyChartState();
}

class _InteractiveAccuracyChartState extends State<InteractiveAccuracyChart> {
  int? _selectedIndex;
  Timer? _clearTimer;

  void _scheduleClear() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _selectedIndex = null);
    });
  }

  void _setFromLocal(Offset local, Size size) {
    if (widget.accuracy.isEmpty) return;
    final usableWidth = size.width - 40;
    if (usableWidth <= 0) return;
    final t = ((local.dx - 40) / usableWidth).clamp(0.0, 1.0);
    final idx = (t * (widget.accuracy.length - 1)).round().clamp(
      0,
      widget.accuracy.length - 1,
    );
    if (_selectedIndex != idx) setState(() => _selectedIndex = idx);
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _setFromLocal(d.localPosition, size);
            _scheduleClear();
          },
          onPanDown: (d) => _setFromLocal(d.localPosition, size),
          onPanUpdate: (d) => _setFromLocal(d.localPosition, size),
          onPanEnd: (_) => _scheduleClear(),
          onPanCancel: _scheduleClear,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(widget.accuracy.join(',')),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) {
              return CustomPaint(
                painter: AccuracyChartPainter(
                  widget.accuracy,
                  selectedIndex: _selectedIndex,
                  progress: progress,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        );
      },
    );
  }
}

class SpeedChartPainter extends CustomPainter {
  final List<double> speeds;
  final int? selectedIndex;
  final double progress;

  SpeedChartPainter(this.speeds, {this.selectedIndex, this.progress = 1});

  Path _smoothCurve(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.addOval(Rect.fromCircle(center: points.first, radius: 1));
      return path;
    }

    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final mx = (p0.dx + p1.dx) / 2;
      final my = (p0.dy + p1.dy) / 2;
      path.quadraticBezierTo(p0.dx, p0.dy, mx, my);
    }
    path.quadraticBezierTo(
      points[points.length - 2].dx,
      points[points.length - 2].dy,
      points.last.dx,
      points.last.dy,
    );
    return path;
  }

  void _paintValuePill({
    required Canvas canvas,
    required Size size,
    required Offset anchor,
    required String text,
    required Color bg,
    required Color fg,
  }) {
    final tp = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      text: TextSpan(
        text: text,
        style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.w800),
      ),
    )..layout();

    const padX = 6.0;
    const padY = 3.0;
    final w = tp.width + (padX * 2);
    final h = tp.height + (padY * 2);

    var left = anchor.dx - (w / 2);
    left = left.clamp(40.0, size.width - w);

    // Prefer above, fallback below if near top.
    var top = anchor.dy - h - 8;
    if (top < 0) top = anchor.dy + 8;
    top = top.clamp(0.0, size.height - h);

    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(999),
    );

    canvas.drawRRect(
      r,
      Paint()
        ..color = bg
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    tp.paint(canvas, Offset(left + padX, top + padY));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (speeds.isEmpty) return;

    const double minSpeed = 40;
    const double maxSpeed = 160;

    final axisPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.55)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        colors: [Color(0xFF00FF88), Color(0xFF38BDF8)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final glowLinePaint = Paint()
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF00FF88).withValues(alpha: 0.18)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 10);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00FF88).withValues(alpha: 0.18),
          const Color(0xFF00FF88).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final textPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );

    for (int value = 40; value <= 160; value += 20) {
      final normalized = ((value - minSpeed) / (maxSpeed - minSpeed)).clamp(
        0.0,
        1.0,
      );
      final double y = size.height - (normalized * size.height);

      canvas.drawLine(Offset(40, y), Offset(size.width, y), axisPaint);

      textPainter.text = TextSpan(
        text: value.toString(),
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - 6));
    }

    final int ballsToShow = speeds.length;
    final double usableWidth = size.width - 40;
    final double stepX = ballsToShow > 1 ? usableWidth / (ballsToShow - 1) : 0;

    final List<Offset> points = <Offset>[];

    for (int i = 0; i < ballsToShow; i++) {
      final normalized = ((speeds[i] - minSpeed) / (maxSpeed - minSpeed)).clamp(
        0.0,
        1.0,
      );

      final double x = 40 + (stepX * i);
      final double y = size.height - (normalized * size.height);
      points.add(Offset(x, y));

      if (selectedIndex == null) {
        textPainter.text = TextSpan(
          text: "Ball ${i + 1}",
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - 15, size.height + 4));
      }
    }

    double peakSpeed = speeds.reduce((a, b) => a > b ? a : b);
    int peakIndex = speeds.indexOf(peakSpeed);
    final averageSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
    final avgNormalized = ((averageSpeed - minSpeed) / (maxSpeed - minSpeed))
        .clamp(0.0, 1.0);
    final avgY = size.height - (avgNormalized * size.height);

    final avgPaint = Paint()
      ..color = const Color(0xFFFFD166).withValues(alpha: 0.48)
      ..strokeWidth = 1.2;
    for (double x = 40; x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x, avgY),
        Offset(math.min(x + 6, size.width), avgY),
        avgPaint,
      );
    }
    _paintValuePill(
      canvas: canvas,
      size: size,
      anchor: Offset(size.width - 36, avgY),
      text: "Avg ${averageSpeed.toStringAsFixed(0)}",
      bg: const Color(0xFF1F1402).withValues(alpha: 0.72),
      fg: const Color(0xFFFFD166),
    );

    // Avoid collisions: the peak point gets a single "Top" pill instead of
    // drawing both the Top label and the per-dot value pill.

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, size.width * progress, size.height + 30),
    );

    if (points.length > 1) {
      final curvePath = _smoothCurve(points);
      final fillPath = Path.from(curvePath)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(curvePath, glowLinePaint);
      canvas.drawPath(curvePath, linePaint);
    }

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isSel = selectedIndex == i;
      final glowDot = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: isSel ? 0.32 : 0.20)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, isSel ? 14 : 10);
      canvas.drawCircle(p, isSel ? 12 : 10, glowDot);
      canvas.drawCircle(
        p,
        isSel ? 6 : 5,
        Paint()..color = const Color(0xFF38BDF8),
      );
      canvas.drawCircle(
        p,
        isSel ? 3 : 2.2,
        Paint()..color = const Color(0xFF00FF88),
      );
    }
    canvas.restore();

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < points.length) {
      final p = points[selectedIndex!];
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10)
          ..strokeWidth = 1.2,
      );
      final hand = Path()
        ..moveTo(p.dx, p.dy - 18)
        ..lineTo(p.dx - 7, p.dy - 5)
        ..lineTo(p.dx + 7, p.dy - 5)
        ..close();
      canvas.drawPath(
        hand,
        Paint()
          ..color = const Color(0xFFFFD700).withValues(alpha: 0.85)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
      );

      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -34),
        text:
            "Ball ${selectedIndex! + 1}: ${speeds[selectedIndex!].toStringAsFixed(0)}",
        bg: const Color(0xFF0B1220).withValues(alpha: 0.90),
        fg: const Color(0xFF38BDF8),
      );
    } else if (peakIndex >= 0 && peakIndex < points.length) {
      final p = points[peakIndex];
      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -14),
        text: "Top ${peakSpeed.toStringAsFixed(0)}",
        bg: const Color(0xFF1F1402).withValues(alpha: 0.86),
        fg: const Color(0xFFFFD700),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AccuracyChartPainter extends CustomPainter {
  final List<double> accuracy;
  final int? selectedIndex;
  final double progress;

  AccuracyChartPainter(this.accuracy, {this.selectedIndex, this.progress = 1});

  Path _smoothCurve(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.addOval(Rect.fromCircle(center: points.first, radius: 1));
      return path;
    }

    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final mx = (p0.dx + p1.dx) / 2;
      final my = (p0.dy + p1.dy) / 2;
      path.quadraticBezierTo(p0.dx, p0.dy, mx, my);
    }
    path.quadraticBezierTo(
      points[points.length - 2].dx,
      points[points.length - 2].dy,
      points.last.dx,
      points.last.dy,
    );
    return path;
  }

  void _paintValuePill({
    required Canvas canvas,
    required Size size,
    required Offset anchor,
    required String text,
    required Color bg,
    required Color fg,
  }) {
    final tp = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      text: TextSpan(
        text: text,
        style: TextStyle(color: fg, fontSize: 9.5, fontWeight: FontWeight.w800),
      ),
    )..layout();

    const padX = 6.0;
    const padY = 3.0;
    final w = tp.width + (padX * 2);
    final h = tp.height + (padY * 2);

    var left = anchor.dx - (w / 2);
    left = left.clamp(40.0, size.width - w);

    var top = anchor.dy - h - 8;
    if (top < 0) top = anchor.dy + 8;
    top = top.clamp(0.0, size.height - h);

    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(999),
    );

    canvas.drawRRect(r, Paint()..color = bg);
    canvas.drawRRect(
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    tp.paint(canvas, Offset(left + padX, top + padY));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (accuracy.isEmpty) return;

    const double minVal = 0;
    const double maxVal = 100;

    final axisPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.55)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFF00FF88)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final glowLinePaint = Paint()
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.18)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 10);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFFD700).withValues(alpha: 0.18),
          const Color(0xFFFFD700).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final textPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );

    for (int value = 0; value <= 100; value += 20) {
      final normalized = ((value - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
      final double y = size.height - (normalized * size.height);
      canvas.drawLine(Offset(40, y), Offset(size.width, y), axisPaint);

      textPainter.text = TextSpan(
        text: "$value%",
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - 6));
    }

    final int points = accuracy.length;
    final double usableWidth = size.width - 40;
    final double stepX = points > 1 ? usableWidth / (points - 1) : 0;

    final List<Offset> pts = <Offset>[];

    for (int i = 0; i < points; i++) {
      final normalized = ((accuracy[i] - minVal) / (maxVal - minVal)).clamp(
        0.0,
        1.0,
      );
      final double x = 40 + (stepX * i);
      final double y = size.height - (normalized * size.height);
      pts.add(Offset(x, y));

      if (selectedIndex == null) {
        textPainter.text = TextSpan(
          text: "Ball ${i + 1}",
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - 15, size.height + 4));
      }
    }

    final avgAccuracy = accuracy.reduce((a, b) => a + b) / accuracy.length;
    final avgNormalized = ((avgAccuracy - minVal) / (maxVal - minVal)).clamp(
      0.0,
      1.0,
    );
    final avgY = size.height - (avgNormalized * size.height);
    final avgPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.46)
      ..strokeWidth = 1.2;
    for (double x = 40; x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x, avgY),
        Offset(math.min(x + 6, size.width), avgY),
        avgPaint,
      );
    }
    _paintValuePill(
      canvas: canvas,
      size: size,
      anchor: Offset(size.width - 36, avgY),
      text: "Avg ${avgAccuracy.toStringAsFixed(0)}%",
      bg: const Color(0xFF07111F).withValues(alpha: 0.78),
      fg: const Color(0xFF38BDF8),
    );

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, size.width * progress, size.height + 30),
    );

    if (pts.length > 1) {
      final curvePath = _smoothCurve(pts);
      final fillPath = Path.from(curvePath)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(curvePath, glowLinePaint);
      canvas.drawPath(curvePath, linePaint);
    }

    final bestAcc = accuracy.reduce((a, b) => a > b ? a : b);
    final bestIndex = accuracy.indexOf(bestAcc);

    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];
      final isSel = selectedIndex == i;
      final glowDot = Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: isSel ? 0.32 : 0.20)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, isSel ? 14 : 10);
      canvas.drawCircle(p, isSel ? 12 : 10, glowDot);
      canvas.drawCircle(
        p,
        isSel ? 6 : 5,
        Paint()..color = const Color(0xFFFFD700),
      );
      canvas.drawCircle(
        p,
        isSel ? 3 : 2.2,
        Paint()..color = const Color(0xFF00FF88),
      );
    }
    canvas.restore();

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < pts.length) {
      final p = pts[selectedIndex!];
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10)
          ..strokeWidth = 1.2,
      );

      final hand = Path()
        ..moveTo(p.dx, p.dy - 18)
        ..lineTo(p.dx - 7, p.dy - 5)
        ..lineTo(p.dx + 7, p.dy - 5)
        ..close();
      canvas.drawPath(
        hand,
        Paint()
          ..color = const Color(0xFFFFD700).withValues(alpha: 0.85)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
      );

      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -34),
        text:
            "Ball ${selectedIndex! + 1}: ${accuracy[selectedIndex!].toStringAsFixed(0)}%",
        bg: const Color(0xFF0B1220).withValues(alpha: 0.90),
        fg: const Color(0xFFFFD700),
      );
    } else if (bestIndex >= 0 && bestIndex < pts.length) {
      final p = pts[bestIndex];
      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -14),
        text: "Best ${bestAcc.toStringAsFixed(0)}%",
        bg: const Color(0xFF1F1402).withValues(alpha: 0.86),
        fg: const Color(0xFFFFD700),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
