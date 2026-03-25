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
    with WidgetsBindingObserver {
  List<double> speedHistory = [];
  int currentSessionIndex = 0;
  List<List<double>> sessions = [];
  String userName = "Player";
  String? _currentUid;
  StreamSubscription<User?>? _authSub;
  late ConfettiController _confettiController;
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

      await _loadCertificateName();
      _lastSpeedLoadAt = DateTime.now();
      if (mounted) setState(() {});
    } finally {
      _loadingSpeedHistory = false;
    }
  }

  Future<void> _clearAllSessions() async {
    await _speedBox.delete('allSpeeds_${_storageUid}');
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
    await _speedBox.put('allSpeeds_${_storageUid}', rebuiltFlat);

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

    final storedSpeeds = _speedBox.get('allSpeeds_${_storageUid}') as List?;
    List<double> flatSpeeds = [];

    if (storedSpeeds != null) {
      flatSpeeds = storedSpeeds.map((e) => (e as num).toDouble()).toList();
    }

    flatSpeeds.addAll(newSpeeds);

    await _speedBox.put('allSpeeds_${_storageUid}', flatSpeeds);

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

  int get _sessionCount => sessions.length;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _confettiController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final sessionCount = _sessionCount;
    final accuracyScores = _deriveAccuracyScores(speedHistory);
    final avgAccuracy = _avgAccuracyPercent(speedHistory);
    final topSpeed = speedHistory.isEmpty
        ? 0.0
        : speedHistory.reduce((a, b) => a > b ? a : b).toDouble();
    final canGenerateCertificate =
        speedHistory.isNotEmpty && topSpeed >= 95 && avgAccuracy > 72;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF00FF88),
          backgroundColor: const Color(0xFF0F172A),
          notificationPredicate: (notification) {
            return PremiumService.isPremiumActive &&
                notification.depth == 0;
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
              Text(
                "Performance Insights",
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 25),

              // ===== TOP STATS =====
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStat(
                    "🔥 Top Speed",
                    topSpeed,
                    const Color(0xFF00FF88),
                  ),
                  _buildStat(
                    "Average",
                    speedHistory.isEmpty
                        ? 0.0
                        : (speedHistory.reduce((a, b) => a + b) /
                                  speedHistory.length)
                              .toDouble(),
                    const Color(0xFF38BDF8),
                  ),
                  _buildStat(
                    "Lowest",
                    speedHistory.isEmpty
                        ? 0.0
                        : speedHistory
                              .reduce((a, b) => a < b ? a : b)
                              .toDouble(),
                    const Color(0xFFFF4D4D),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ===== ACCURACY (Derived from speed consistency) =====
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFFFFD700),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Accuracy (derived): ${avgAccuracy == 0 ? '--' : '${avgAccuracy.toStringAsFixed(0)}%'}",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      "Consistency",
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              const SizedBox(height: 15),

              if (sessionCount > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: currentSessionIndex > 0
                          ? () {
                              setState(() {
                                currentSessionIndex--;
                                speedHistory =
                                    currentSessionIndex < sessions.length
                                    ? sessions[currentSessionIndex]
                                    : <double>[];
                              });
                            }
                          : null,
                      child: const Text("Previous"),
                    ),
                    Text(
                      "Session ${currentSessionIndex + 1}/$sessionCount",
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: currentSessionIndex < sessionCount - 1
                          ? () {
                              setState(() {
                                currentSessionIndex++;
                                speedHistory =
                                    currentSessionIndex < sessions.length
                                    ? sessions[currentSessionIndex]
                                    : <double>[];
                              });
                            }
                          : null,
                      child: const Text("Next"),
                    ),
                  ],
                ),

              const SizedBox(height: 10),

              if (sessionCount > 0)
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    label: const Text(
                      "Delete",
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onPressed: () async {
                      final choice = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF0F172A),
                          title: const Text(
                            "Delete Options",
                            style: TextStyle(color: Colors.white),
                          ),
                          content: const Text(
                            "What would you like to delete?",
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, "specific"),
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

                      if (choice == "specific") {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF0F172A),
                            title: const Text(
                              "Delete This Session?",
                              style: TextStyle(color: Colors.white),
                            ),
                            content: Text(
                              "Session ${currentSessionIndex + 1} will be permanently deleted. This cannot be recovered.\n\nContinue?",
                              style: const TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("No"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  "Yes, Delete",
                                  style: TextStyle(color: Colors.orangeAccent),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await _deleteCurrentSession();
                        }
                      } else if (choice == "all") {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF0F172A),
                            title: const Text(
                              "Delete All Sessions?",
                              style: TextStyle(color: Colors.white),
                            ),
                            content: const Text(
                              "This will permanently delete all your bowling sessions. This action cannot be recovered.\n\nAre you sure?",
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("No"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  "Yes, Delete",
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await _clearAllSessions();
                        }
                      }
                    },
                  ),
                ),

              const SizedBox(height: 10),

              // ===== GRAPH =====
              Container(
                height: 300,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: speedHistory.isEmpty
                    ? Center(
                        child: Text(
                          "No speed data yet.",
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : InteractiveSpeedChart(speeds: speedHistory),
              ),

              const SizedBox(height: 16),

              // ===== ACCURACY GRAPH =====
              Container(
                height: 260,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: accuracyScores.isEmpty
                    ? Center(
                        child: Text(
                          "No accuracy data yet.",
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : InteractiveAccuracyChart(accuracy: accuracyScores),
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: speedHistory.isEmpty
                    ? null
                    : () async {
                        final currentSpeeds = List<double>.from(speedHistory);
                        final double top = currentSpeeds.isEmpty
                            ? 0.0
                            : currentSpeeds
                                  .reduce((a, b) => a > b ? a : b)
                                  .toDouble();
                        final double avg = currentSpeeds.isEmpty
                            ? 0.0
                            : (currentSpeeds.reduce((a, b) => a + b) /
                                      currentSpeeds.length)
                                  .toDouble();
                        // Use the same accuracy used in Insights tab (not upload/video).
                        final accuracyPercent = _avgAccuracyPercent(
                          currentSpeeds,
                        );

                        if (top < 95 || accuracyPercent <= 72) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF111827),
                              content: Text(
                                "Certificate unlocks at 95+ KMPH and above 72% accuracy. "
                                "Your session: ${top.toStringAsFixed(0)} KMPH, ${accuracyPercent.toStringAsFixed(0)}%.",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                          return;
                        }

                        _confettiController.play();
                        final sessionXp = currentSpeeds.length * 12;
                        final sessionId =
                            "${DateTime.now().millisecondsSinceEpoch}";
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
                      },
                icon: const Icon(Icons.workspace_premium),
                label: const Text("Generate Certificate"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canGenerateCertificate
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF1F2937),
                  foregroundColor: canGenerateCertificate
                      ? Colors.black
                      : Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: canGenerateCertificate ? 10 : 0,
                  shadowColor: canGenerateCertificate
                      ? const Color(0xFF00FF88).withValues(alpha: 0.35)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String title, double value, Color color) {
    return Column(
      children: [
        Text(
          "${value.toStringAsFixed(1)} km/h",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
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
          child: CustomPaint(
            painter: SpeedChartPainter(
              widget.speeds,
              selectedIndex: _selectedIndex,
            ),
            child: const SizedBox.expand(),
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
          child: CustomPaint(
            painter: AccuracyChartPainter(
              widget.accuracy,
              selectedIndex: _selectedIndex,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class SpeedChartPainter extends CustomPainter {
  final List<double> speeds;
  final int? selectedIndex;

  SpeedChartPainter(this.speeds, {this.selectedIndex});

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
        ..color = Colors.white.withOpacity(0.10)
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
      ..color = const Color(0xFF334155).withOpacity(0.55)
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
      ..color = const Color(0xFF00FF88).withOpacity(0.18)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 10);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00FF88).withOpacity(0.18),
          const Color(0xFF00FF88).withOpacity(0.0),
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

    // Avoid collisions: the peak point gets a single "Top" pill instead of
    // drawing both the Top label and the per-dot value pill.

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
        ..color = const Color(0xFF38BDF8).withOpacity(isSel ? 0.32 : 0.20)
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

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < points.length) {
      final p = points[selectedIndex!];
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = Colors.white.withOpacity(0.10)
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
          ..color = const Color(0xFFFFD700).withOpacity(0.85)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
      );

      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -34),
        text:
            "Ball ${selectedIndex! + 1}: ${speeds[selectedIndex!].toStringAsFixed(0)}",
        bg: const Color(0xFF0B1220).withOpacity(0.90),
        fg: const Color(0xFF38BDF8),
      );
    } else if (peakIndex >= 0 && peakIndex < points.length) {
      final p = points[peakIndex];
      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -14),
        text: "Top ${peakSpeed.toStringAsFixed(0)}",
        bg: const Color(0xFF1F1402).withOpacity(0.86),
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

  AccuracyChartPainter(this.accuracy, {this.selectedIndex});

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
        ..color = Colors.white.withOpacity(0.10)
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
      ..color = const Color(0xFF334155).withOpacity(0.55)
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
      ..color = const Color(0xFFFFD700).withOpacity(0.18)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 10);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFFD700).withOpacity(0.18),
          const Color(0xFFFFD700).withOpacity(0.0),
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
        ..color = const Color(0xFFFFD700).withOpacity(isSel ? 0.32 : 0.20)
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

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < pts.length) {
      final p = pts[selectedIndex!];
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = Colors.white.withOpacity(0.10)
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
          ..color = const Color(0xFFFFD700).withOpacity(0.85)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
      );

      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -34),
        text:
            "Ball ${selectedIndex! + 1}: ${accuracy[selectedIndex!].toStringAsFixed(0)}%",
        bg: const Color(0xFF0B1220).withOpacity(0.90),
        fg: const Color(0xFFFFD700),
      );
    } else if (bestIndex >= 0 && bestIndex < pts.length) {
      final p = pts[bestIndex];
      _paintValuePill(
        canvas: canvas,
        size: size,
        anchor: p + const Offset(0, -14),
        text: "Best ${bestAcc.toStringAsFixed(0)}%",
        bg: const Color(0xFF1F1402).withOpacity(0.86),
        fg: const Color(0xFFFFD700),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
