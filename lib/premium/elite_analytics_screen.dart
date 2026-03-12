import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../upload/upload_screen.dart';

class EliteAnalyticsScreen extends StatefulWidget {
  const EliteAnalyticsScreen({super.key});

  @override
  State<EliteAnalyticsScreen> createState() => _EliteAnalyticsScreenState();
}

class _EliteAnalyticsScreenState extends State<EliteAnalyticsScreen> {
  bool _loading = true;
  List<double> _speeds = <double>[];
  List<double> _accuracy = <double>[];
  bool _generating = false;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "guest";

    final box = await Hive.openBox('speedBox');
    final stored = box.get('allSpeeds_$uid') as List?;

    var speeds = <double>[];
    if (stored != null) {
      speeds = stored.map((e) => (e as num).toDouble()).toList();
    }

    if (speeds.length > 7) {
      speeds = speeds.sublist(speeds.length - 7);
    }

    final accuracy = _deriveAccuracyScores(speeds);

    if (!mounted) return;
    setState(() {
      _speeds = speeds;
      _accuracy = accuracy;
      _loading = false;
    });
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

  Future<Directory> _reportDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> _shareReport(String path) async {
    await Share.shareXFiles([
      XFile(path),
    ], text: "CrickNova Weekly Progress Report");
  }

  Future<void> _generatePdfReport() async {
    if (_generating) return;
    if (_speeds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No progress yet. Upload a session first."),
          backgroundColor: Color(0xFF0B1220),
        ),
      );
      return;
    }

    setState(() {
      _generating = true;
      _savedPath = null;
    });

    try {
      final doc = pw.Document();
      final now = DateTime.now();
      final avgSpeed = _speeds.reduce((a, b) => a + b) / _speeds.length;
      final maxSpeed = _speeds.reduce(math.max);
      final avgAccuracy = _accuracy.isEmpty
          ? 0
          : _accuracy.reduce((a, b) => a + b) / _accuracy.length;

      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Text(
              "CrickNova Weekly Progress Report",
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text("Generated: ${now.toLocal()}"),
            pw.SizedBox(height: 16),
            pw.Text("Summary", style: pw.TextStyle(fontSize: 16)),
            pw.Bullet(text: "Avg Speed: ${avgSpeed.toStringAsFixed(1)} km/h"),
            pw.Bullet(text: "Top Speed: ${maxSpeed.toStringAsFixed(1)} km/h"),
            pw.Bullet(
              text: "Accuracy Index: ${avgAccuracy.toStringAsFixed(0)}%",
            ),
            pw.SizedBox(height: 16),
            pw.Text("Progress Details", style: pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: const ["Session", "Speed (km/h)", "Accuracy (%)"],
              data: List.generate(_speeds.length, (i) {
                final speed = _speeds[i].toStringAsFixed(1);
                final acc = _accuracy.isNotEmpty
                    ? _accuracy[i].toStringAsFixed(0)
                    : "--";
                return ["${i + 1}", speed, acc];
              }),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(),
            ),
          ],
        ),
      );

      final dir = await _reportDirectory();
      final filename = "CrickNova_Report_${now.millisecondsSinceEpoch}.pdf";
      final file = File("${dir.path}/$filename");
      await file.writeAsBytes(await doc.save());

      if (!mounted) return;
      setState(() {
        _savedPath = file.path;
        _generating = false;
      });

      await _shareReport(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Report saved to ${file.path}"),
          backgroundColor: const Color(0xFF0B1220),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("PDF generation failed: $e"),
          backgroundColor: const Color(0xFF0B1220),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        title: Text(
          "Deep-Dive Analytics",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD86B)),
            )
          : RefreshIndicator(
              color: const Color(0xFFFFD86B),
              backgroundColor: const Color(0xFF0F172A),
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    "Last 7 sessions (derived)",
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_speeds.isEmpty)
                    _AnalyticsEmptyState(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const UploadScreen(),
                          ),
                        );
                      },
                    )
                  else ...[
                    _SummaryRow(speeds: _speeds, accuracy: _accuracy),
                    const SizedBox(height: 18),
                    _LineChartCard(
                      title: "Speed (km/h)",
                      values: _speeds,
                      lineColor: const Color(0xFF60A5FA),
                      fillColor: const Color(0xFF1E3A8A),
                    ),
                    const SizedBox(height: 16),
                    _LineChartCard(
                      title: "Accuracy Index",
                      values: _accuracy,
                      lineColor: const Color(0xFFFFD86B),
                      fillColor: const Color(0xFF3B2F12),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Accuracy is derived from speed consistency.",
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ProgressList(speeds: _speeds, accuracy: _accuracy),
                    const SizedBox(height: 18),
                    _PdfActionCard(
                      generating: _generating,
                      savedPath: _savedPath,
                      onGenerate: _generatePdfReport,
                      onDownload: _savedPath == null
                          ? null
                          : () => _shareReport(_savedPath!),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _AnalyticsEmptyState extends StatelessWidget {
  final VoidCallback onTap;

  const _AnalyticsEmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "No analytics yet",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Upload your first training video to unlock speed and accuracy charts.",
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD86B),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onTap,
              child: const Text(
                "Start Your First Analysis",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<double> speeds;
  final List<double> accuracy;

  const _SummaryRow({required this.speeds, required this.accuracy});

  @override
  Widget build(BuildContext context) {
    final avgSpeed = speeds.isEmpty
        ? 0
        : speeds.reduce((a, b) => a + b) / speeds.length;
    final maxSpeed = speeds.isEmpty ? 0 : speeds.reduce(math.max);
    final avgAccuracy = accuracy.isEmpty
        ? 0
        : accuracy.reduce((a, b) => a + b) / accuracy.length;

    return Row(
      children: [
        _StatChip(
          label: "Avg Speed",
          value: avgSpeed == 0 ? "--" : "${avgSpeed.toStringAsFixed(1)} km/h",
        ),
        const SizedBox(width: 10),
        _StatChip(
          label: "Top Speed",
          value: maxSpeed == 0 ? "--" : "${maxSpeed.toStringAsFixed(1)} km/h",
        ),
        const SizedBox(width: 10),
        _StatChip(
          label: "Accuracy",
          value: avgAccuracy == 0 ? "--" : "${avgAccuracy.toStringAsFixed(0)}%",
        ),
      ],
    );
  }
}

class _ProgressList extends StatelessWidget {
  final List<double> speeds;
  final List<double> accuracy;

  const _ProgressList({required this.speeds, required this.accuracy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Progress Summary",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(speeds.length, (index) {
            final speed = speeds[index].toStringAsFixed(1);
            final acc = accuracy.isNotEmpty
                ? "${accuracy[index].toStringAsFixed(0)}%"
                : "--";
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "D${index + 1}",
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Speed $speed km/h",
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                  Text(
                    acc,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFFFD86B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PdfActionCard extends StatelessWidget {
  final bool generating;
  final String? savedPath;
  final VoidCallback onGenerate;
  final VoidCallback? onDownload;

  const _PdfActionCard({
    required this.generating,
    required this.savedPath,
    required this.onGenerate,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Weekly PDF Report",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your progress summary is ready. Generate a PDF and download it to your phone.",
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (generating) ...[
            const LinearProgressIndicator(
              minHeight: 3,
              color: Color(0xFFFFD86B),
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 8),
            Text(
              "Generating report...",
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD86B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onGenerate,
                child: const Text(
                  "Generate PDF",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (savedPath != null && onDownload != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD86B),
                    side: const BorderSide(color: Color(0xFFFFD86B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onDownload,
                  child: const Text("Download PDF"),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11.5),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineChartCard extends StatelessWidget {
  final String title;
  final List<double> values;
  final Color lineColor;
  final Color fillColor;

  const _LineChartCard({
    required this.title,
    required this.values,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = values.isEmpty ? 0 : values.reduce(math.max);
    final minY = values.isEmpty ? 0 : values.reduce(math.min);
    final padding = (maxY - minY).abs() * 0.2;
    final chartMin = (minY - padding).clamp(0, double.infinity);
    final chartMax = maxY + padding;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(0, values.length - 1).toDouble(),
                minY: chartMin.toDouble(),
                maxY: chartMax.toDouble(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: values.isEmpty
                      ? 5
                      : (chartMax - chartMin) / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.white.withValues(alpha: 0.08),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: values.isEmpty ? 5 : (chartMax - chartMin) / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(0),
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= values.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            "D${idx + 1}",
                            style: GoogleFonts.poppins(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < values.length; i++)
                        FlSpot(i.toDouble(), values[i]),
                    ],
                    isCurved: true,
                    color: lineColor,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: fillColor.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
