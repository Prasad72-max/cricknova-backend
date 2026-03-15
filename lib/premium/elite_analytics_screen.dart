import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../services/weekly_stats_service.dart';

class EliteAnalyticsScreen extends StatefulWidget {
  const EliteAnalyticsScreen({super.key});

  @override
  State<EliteAnalyticsScreen> createState() => _EliteAnalyticsScreenState();
}

class _EliteAnalyticsScreenState extends State<EliteAnalyticsScreen> {
  bool _loading = true;
  bool _generating = false;
  String? _savedPath;

  WeeklyStats? _stats;
  Map<String, Map<String, int>> _daily = <String, Map<String, int>>{};

  @override
  void initState() {
    super.initState();
    _loadWeeklyUsage();
  }

  Future<void> _loadWeeklyUsage() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "guest";

    final stats = await WeeklyStatsService.loadCurrentWeek(uid);
    final daily = await WeeklyStatsService.loadCurrentWeekDaily(uid);

    if (!mounted) return;
    setState(() {
      _stats = stats;
      _daily = daily;
      _loading = false;
    });
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
    ], text: "CrickNova Weekly Usage Report");
  }

  int _activeDays(WeeklyStats stats, Map<String, Map<String, int>> daily) {
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final d = stats.weekStart.add(Duration(days: i));
      final key = _dateKey(d);
      final m = daily[key] ?? const <String, int>{};
      if (_isActiveDay(m)) count++;
    }
    return count;
  }

  List<List<String>> _activeDayRows(
    WeeklyStats stats,
    Map<String, Map<String, int>> daily,
  ) {
    final rows = <List<String>>[];
    for (int i = 0; i < 7; i++) {
      final d = stats.weekStart.add(Duration(days: i));
      final key = _dateKey(d);
      final m = daily[key] ?? const <String, int>{};
      if (!_isActiveDay(m)) continue;
      rows.add([
        _fmtDay(d),
        "${m[WeeklyStatsService.fieldAppOpens] ?? 0}",
        "${m[WeeklyStatsService.fieldAiChat] ?? 0}",
        "${m[WeeklyStatsService.fieldAnalyseAi] ?? 0}",
        "${m[WeeklyStatsService.fieldMistakeDetection] ?? 0}",
      ]);
    }
    return rows;
  }

  bool _isActiveDay(Map<String, int> m) {
    return (m[WeeklyStatsService.fieldAppOpens] ?? 0) > 0 ||
        (m[WeeklyStatsService.fieldAiChat] ?? 0) > 0 ||
        (m[WeeklyStatsService.fieldAnalyseAi] ?? 0) > 0 ||
        (m[WeeklyStatsService.fieldMistakeDetection] ?? 0) > 0 ||
        (m[WeeklyStatsService.fieldAppMinutes] ?? 0) > 0;
  }

  Future<void> _generatePdfReport() async {
    if (_generating) return;
    final stats = _stats;
    if (stats == null) return;

    setState(() {
      _generating = true;
      _savedPath = null;
    });

    try {
      final doc = pw.Document();
      final now = DateTime.now();
      final daily = _daily;
      final activeDays = _activeDays(stats, daily);
      final rows = _activeDayRows(stats, daily);

      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Text(
              "CrickNova Weekly Usage Report",
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              "Week: ${_fmtDate(stats.weekStart)} – ${_fmtDate(stats.weekEnd)}",
            ),
            pw.Text("Generated: ${now.toLocal()}"),
            pw.SizedBox(height: 16),
            pw.Text("Summary", style: const pw.TextStyle(fontSize: 16)),
            pw.Bullet(text: "App opens: ${stats.appOpens}"),
            pw.Bullet(text: "Active days: $activeDays / 7"),
            pw.Bullet(text: "AI Coach chats: ${stats.aiChats}"),
            pw.Bullet(text: "Analyse Yourself uses: ${stats.analyseAi}"),
            pw.Bullet(
              text: "Mistake Detection uses: ${stats.mistakeDetection}",
            ),
            if (stats.appMinutes > 0)
              pw.Bullet(text: "Time in app: ${_fmtUsage(stats.appMinutes)}"),
            pw.SizedBox(height: 16),
            pw.Text("Daily Breakdown", style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: const [
                "Day",
                "App opens",
                "AI chats",
                "Analyse",
                "Mistake",
              ],
              data: rows.isEmpty
                  ? const [
                      ["No activity yet", "0", "0", "0", "0"],
                    ]
                  : rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      );

      final dir = await _reportDirectory();
      final filename =
          "CrickNova_Weekly_Usage_${now.millisecondsSinceEpoch}.pdf";
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

  static String _fmtDate(DateTime d) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}";
  }

  static String _fmtDay(DateTime d) {
    const wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final w = wd[(d.weekday - 1).clamp(0, 6)];
    return "$w ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}";
  }

  static String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return "$y-$m-$day";
  }

  static String _fmtUsage(int minutes) {
    if (minutes <= 0) return "0 min";
    final hrs = minutes ~/ 60;
    final mins = minutes % 60;
    if (hrs <= 0) return "${mins} min";
    if (mins == 0) return "${hrs} hr";
    return "${hrs} hr ${mins} min";
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final activeDays = stats == null ? 0 : _activeDays(stats, _daily);

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        title: Text(
          "Weekly Usage Report",
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
              onRefresh: _loadWeeklyUsage,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (stats != null) ...[
                    _UsageSummaryRow(stats: stats, activeDays: activeDays),
                    const SizedBox(height: 16),
                    _DailyUsageCard(stats: stats, daily: _daily),
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

class _UsageSummaryRow extends StatelessWidget {
  final WeeklyStats stats;
  final int activeDays;

  const _UsageSummaryRow({required this.stats, required this.activeDays});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _StatChip(label: "App Opens", value: stats.appOpens.toString()),
            const SizedBox(width: 10),
            _StatChip(
              label: "Time Used",
              value: _EliteAnalyticsScreenState._fmtUsage(stats.appMinutes),
            ),
            const SizedBox(width: 10),
            _StatChip(label: "Active Days", value: "$activeDays/7"),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatChip(label: "AI Chats", value: stats.aiChats.toString()),
            const SizedBox(width: 10),
            _StatChip(label: "Analyse", value: stats.analyseAi.toString()),
            const SizedBox(width: 10),
            _StatChip(
              label: "Mistake",
              value: stats.mistakeDetection.toString(),
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyUsageCard extends StatelessWidget {
  final WeeklyStats stats;
  final Map<String, Map<String, int>> daily;

  const _DailyUsageCard({required this.stats, required this.daily});

  @override
  Widget build(BuildContext context) {
    final active = <Widget>[];
    for (int i = 0; i < 7; i++) {
      final d = stats.weekStart.add(Duration(days: i));
      final key = _EliteAnalyticsScreenState._dateKey(d);
      final m = daily[key] ?? const <String, int>{};
      final opens = m[WeeklyStatsService.fieldAppOpens] ?? 0;
      final chats = m[WeeklyStatsService.fieldAiChat] ?? 0;
      final analyse = m[WeeklyStatsService.fieldAnalyseAi] ?? 0;
      final mistake = m[WeeklyStatsService.fieldMistakeDetection] ?? 0;
      final minutes = m[WeeklyStatsService.fieldAppMinutes] ?? 0;
      final isActive =
          opens > 0 || chats > 0 || analyse > 0 || mistake > 0 || minutes > 0;
      if (!isActive) continue;

      active.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: Text(
                  _EliteAnalyticsScreenState._fmtDay(d),
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Opens: $opens  •  Time: ${_EliteAnalyticsScreenState._fmtUsage(minutes)}  •  AI: $chats  •  Analyse: $analyse  •  Mistake: $mistake",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12.2,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
            "Daily usage (real)",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (active.isEmpty)
            Text(
              "No activity yet this week.",
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12.5),
            )
          else
            ...active,
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
            "Generate your weekly usage PDF (app opens + AI feature usage by day).",
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
