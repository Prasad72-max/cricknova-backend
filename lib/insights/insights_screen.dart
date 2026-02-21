import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:url_launcher/url_launcher.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> with WidgetsBindingObserver {
  List<double> speedHistory = [];
  int currentSessionIndex = 0;
  List<List<double>> sessions = [];
  List<String> sessionDocIds = [];
  String userName = "Player";
  String? _currentUid;
  StreamSubscription<User?>? _authSub;
  final GlobalKey _certificateKey = GlobalKey();
  late ConfettiController _confettiController;
  late Box _speedBox;

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
        speedHistory.clear();
        sessions.clear();
        currentSessionIndex = 0;
        if (mounted) setState(() {});
        return;
      }

      final newUid = user.uid;

      if (_currentUid == newUid) return;

      _currentUid = newUid;
      await _loadSpeedHistory();
    });

    // Initial load
    final initialUser = FirebaseAuth.instance.currentUser;
    _currentUid = initialUser?.uid ?? "guest";
    // _loadSpeedHistory();  // REMOVED: will load after Hive box opens
  }

  Future<void> _initHive() async {
    _speedBox = await Hive.openBox('speedBox');
    await _loadSpeedHistory();
  }


  Future<void> _loadSpeedHistory() async {
    if (!Hive.isBoxOpen('speedBox')) return;
    sessions.clear();
    speedHistory.clear();
    currentSessionIndex = 0;

    final storedSpeeds = _speedBox.get('allSpeeds') as List?;

    if (storedSpeeds != null) {
      final List<double> flatSpeeds =
          storedSpeeds.map((e) => (e as num).toDouble()).toList();

      sessions.clear();

      for (int i = 0; i < flatSpeeds.length; i += 6) {
        final end = (i + 6 <= flatSpeeds.length)
            ? i + 6
            : flatSpeeds.length;
        sessions.add(flatSpeeds.sublist(i, end));
      }

      if (sessions.isNotEmpty) {
        currentSessionIndex = sessions.length - 1;
        speedHistory = sessions[currentSessionIndex];
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _clearAllSessions() async {
    await _speedBox.delete('sessions');
    sessions.clear();
    speedHistory.clear();
    currentSessionIndex = 0;

    if (mounted) setState(() {});
  }

  Future<void> _deleteCurrentSession() async {
    if (sessions.isEmpty) return;

    sessions.removeAt(currentSessionIndex);

    await _speedBox.put('sessions', sessions);

    if (sessions.isNotEmpty) {
      if (currentSessionIndex >= sessions.length) {
        currentSessionIndex = sessions.length - 1;
      }
      speedHistory = sessions[currentSessionIndex];
    } else {
      currentSessionIndex = 0;
      speedHistory.clear();
    }

    if (mounted) setState(() {});
  }

  Future<void> addNewSession(List<double> newSpeeds) async {
    if (newSpeeds.isEmpty) return;

    final storedSpeeds = _speedBox.get('allSpeeds') as List?;
    List<double> flatSpeeds = [];

    if (storedSpeeds != null) {
      flatSpeeds =
          storedSpeeds.map((e) => (e as num).toDouble()).toList();
    }

    flatSpeeds.addAll(newSpeeds);

    await _speedBox.put('allSpeeds', flatSpeeds);

    // Rebuild sessions
    sessions.clear();

    for (int i = 0; i < flatSpeeds.length; i += 6) {
      final end = (i + 6 <= flatSpeeds.length)
          ? i + 6
          : flatSpeeds.length;
      sessions.add(flatSpeeds.sublist(i, end));
    }

    currentSessionIndex = sessions.length - 1;
    speedHistory = sessions.last;

    if (mounted) setState(() {});
  }


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

  @override
  Widget build(BuildContext context) {


    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF00FF88),
          backgroundColor: const Color(0xFF0F172A),
          onRefresh: () async {
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
                    speedHistory.isEmpty
                        ? 0.0
                        : speedHistory.reduce((a, b) => a > b ? a : b).toDouble(),
                    const Color(0xFF00FF88),
                  ),
                  _buildStat(
                    "Average",
                    speedHistory.isEmpty
                        ? 0.0
                        : (speedHistory.reduce((a, b) => a + b) / speedHistory.length).toDouble(),
                    const Color(0xFF38BDF8),
                  ),
                  _buildStat(
                    "Lowest",
                    speedHistory.isEmpty
                        ? 0.0
                        : speedHistory.reduce((a, b) => a < b ? a : b).toDouble(),
                    const Color(0xFFFF4D4D),
                  ),
                ],
              ),

              const SizedBox(height: 14),


              const SizedBox(height: 25),

              const SizedBox(height: 15),

              if (sessions.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: currentSessionIndex > 0
                          ? () {
                              setState(() {
                                currentSessionIndex--;
                                speedHistory = sessions[currentSessionIndex];
                              });
                            }
                          : null,
                      child: const Text("Previous"),
                    ),
                    Text(
                      "Session ${currentSessionIndex + 1}/${sessions.length}",
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: currentSessionIndex < sessions.length - 1
                          ? () {
                              setState(() {
                                currentSessionIndex++;
                                speedHistory = sessions[currentSessionIndex];
                              });
                            }
                          : null,
                      child: const Text("Next"),
                    ),
                  ],
                ),

              const SizedBox(height: 10),

              if (sessions.isNotEmpty)
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
                    : CustomPaint(
                        painter: SpeedChartPainter(speedHistory),
                        child: const SizedBox.expand(),
                      ),
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: speedHistory.isEmpty
                    ? null
                    : () async {
                        // Show analysing dialog
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => Dialog(
                            backgroundColor: const Color(0xFF0F172A),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(
                                    color: Color(0xFF00FF88),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    "Generating your official performance certificate...",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        // Artificial 7-second delay
                        await Future.delayed(const Duration(seconds: 4));

                        // Close analysing dialog
                        Navigator.pop(context);
                        _confettiController.play();

                        final currentSpeeds = List<double>.from(speedHistory);
                        final double top = currentSpeeds.isEmpty
                            ? 0.0
                            : currentSpeeds.reduce((a, b) => a > b ? a : b).toDouble();
                        final double lowest = currentSpeeds.isEmpty
                            ? 0.0
                            : currentSpeeds.reduce((a, b) => a < b ? a : b).toDouble();
                        final double avg = currentSpeeds.isEmpty
                            ? 0.0
                            : (currentSpeeds.reduce((a, b) => a + b) / currentSpeeds.length)
                                .toDouble();


                        // Show actual certificate dialog (existing UI continues below unchanged)
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.transparent,
                            child: RepaintBoundary(
                              key: _certificateKey,
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF0F172A),
                                      Color(0xFF020617),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  border: Border.all(
                                    color: top >= 100
                                        ? const Color(0xFFFFD700) // Gold
                                        : top >= 80
                                            ? const Color(0xFFC0C0C0) // Silver
                                            : const Color(0xFF00FF88),
                                    width: 3,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: ConfettiWidget(
                                        confettiController: _confettiController,
                                        blastDirectionality: BlastDirectionality.explosive,
                                        shouldLoop: false,
                                        numberOfParticles: 40,
                                        maxBlastForce: 25,
                                        minBlastForce: 10,
                                        emissionFrequency: 0.05,
                                        gravity: 0.3,
                                      ),
                                    ),
                                    // ===== Background Cricket Pattern =====
                                    Positioned.fill(
                                      child: Opacity(
                                        opacity: 0.05,
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.sports_cricket,
                                            size: 220,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Opacity(
                                          opacity: 0.04,
                                          child: Center(
                                            child: Transform.rotate(
                                              angle: -0.4,
                                              child: Text(
                                                "CRICKNOVA",
                                                style: GoogleFonts.poppins(
                                                  fontSize: 80,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 8,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "CRICKNOVA PERFORMANCE CERTIFICATE",
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          userName,
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFFFFD700),
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          "Top Speed: ${top.toStringAsFixed(1)} km/h",
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFF00FF88),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "Average Speed: ${avg.toStringAsFixed(1)} km/h",
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFF38BDF8),
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "Lowest Speed: ${lowest.toStringAsFixed(1)} km/h",
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFFFF4D4D),
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        const Divider(color: Colors.white24),
                                        const SizedBox(height: 12),

                                        Text(
                                          "This certificate is more than just a digital file. It is a testament to every drop of sweat you’ve shed on the pitch and every ball you’ve bowled with passion.\n\nAt CrickNova, our mission is to turn your hard work into elite performance. I am personally signing this to recognize your dedication to the game.\n\nWear this achievement with pride. Your journey to becoming a legend has just begun.",
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            height: 1.6,
                                          ),
                                        ),

                                        const SizedBox(height: 28),

                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    "Prasad D. Dukare",
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    "Founder of CrickNova-AI",
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.white54,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(height: 30),

                                        Divider(
                                          color: Colors.white24,
                                          thickness: 1,
                                        ),

                                        const SizedBox(height: 12),

                                        Text(
                                          "© CrickNova • Where Cricket Meets Intelligence",
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white38,
                                            fontSize: 10,
                                            letterSpacing: 1,
                                          ),
                                        ),

                                        const SizedBox(height: 20),

                                        // --- Begin Slogan & Link Block ---
                                        // --- End Slogan & Link Block ---
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            ElevatedButton(
                                              onPressed: () async {
                                                try {
                                                  RenderRepaintBoundary boundary =
                                                      _certificateKey.currentContext!.findRenderObject()
                                                          as RenderRepaintBoundary;

                                                  ui.Image image = await boundary.toImage(pixelRatio: 3.0);
                                                  ByteData? byteData =
                                                      await image.toByteData(format: ui.ImageByteFormat.png);

                                                  if (byteData == null) return;

                                                  Uint8List pngBytes = byteData.buffer.asUint8List();

                                                  final tempDir = await getTemporaryDirectory();
                                                  final file = await File(
                                                    '${tempDir.path}/cricknova_certificate.png',
                                                  ).create();

                                                  await file.writeAsBytes(pngBytes);

                                                  await Share.shareXFiles(
                                                    [XFile(file.path)],
                                                    text:
                                                        '🔥 My Bowling Performance by CrickNova AI\nTop: ${top.toStringAsFixed(1)} km/h\nAverage: ${avg.toStringAsFixed(1)} km/h\n\n🌐 Visit: https://cricknova-5f94f.web.app',
                                                  );

                                                  // Open website externally after share
                                                  final Uri url = Uri.parse("https://cricknova-5f94f.web.app");
                                                  if (await canLaunchUrl(url)) {
                                                    await launchUrl(url, mode: LaunchMode.externalApplication);
                                                  }
                                                } catch (e) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text("Failed to share certificate")),
                                                  );
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFFFA500), // Neon Orange for stronger share urge
                                                foregroundColor: Colors.black,
                                              ),
                                              child: const Text("Share"),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                Navigator.pop(context);
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF1F2937),
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text("Close"),
                                            ),
                                          ],
                                        )
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.workspace_premium),
                label: const Text("Generate Certificate"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
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

class SpeedChartPainter extends CustomPainter {
  final List<double> speeds;

  SpeedChartPainter(this.speeds);

  @override
  void paint(Canvas canvas, Size size) {
    if (speeds.isEmpty) return;

    const double minSpeed = 40;
    const double maxSpeed = 160;

    final axisPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );

    for (int value = 40; value <= 160; value += 20) {
      final normalized =
          ((value - minSpeed) / (maxSpeed - minSpeed)).clamp(0.0, 1.0);
      final double y = size.height - (normalized * size.height);

      canvas.drawLine(Offset(40, y), Offset(size.width, y), axisPaint);

      textPainter.text = TextSpan(
        text: value.toString(),
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - 6));
    }


    final int ballsToShow = speeds.length >= 6 ? 6 : speeds.length;
    final double usableWidth = size.width - 40;
    final double stepX =
        ballsToShow > 1 ? usableWidth / (ballsToShow - 1) : 0;

    final Path path = Path();

    for (int i = 0; i < ballsToShow; i++) {
      final normalized =
          ((speeds[i] - minSpeed) / (maxSpeed - minSpeed)).clamp(0.0, 1.0);

      final double x = 40 + (stepX * i);
      final double y = size.height - (normalized * size.height);

      if (ballsToShow > 1) {
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawCircle(Offset(x, y), 5, dotPaint);

      textPainter.text = TextSpan(
        text: "Ball ${i + 1}",
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - 15, size.height + 4));
    }

    final List<double> visibleSpeeds =
        speeds.length >= 6 ? speeds.sublist(0, 6) : speeds;

    double peakSpeed = visibleSpeeds.reduce((a, b) => a > b ? a : b);
    int peakIndex = visibleSpeeds.indexOf(peakSpeed);

    final normalizedPeak =
        ((peakSpeed - minSpeed) / (maxSpeed - minSpeed)).clamp(0.0, 1.0);

    final double peakX = 40 + (stepX * peakIndex);
    final double peakY = size.height - (normalizedPeak * size.height);

    textPainter.text = const TextSpan(
      text: "🔥 Top",
      style: TextStyle(
        color: Color(0xFFFFD700),
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(peakX - 20, peakY - 25));

    if (speeds.length > 1) {
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}