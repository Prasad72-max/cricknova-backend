import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/leaderboard_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _scopeMaharashtra = true;

  @override
  void initState() {
    super.initState();
    // Warm the box to make the screen feel instant.
    Future.microtask(() async {
      await Hive.openBox(LeaderboardService.boxName);
    });
  }

  List<Map<String, dynamic>> _applyScope(List<Map<String, dynamic>> entries) {
    if (!_scopeMaharashtra) return entries;
    return entries
        .where((e) {
          final region = (e['region'] ?? '').toString().toLowerCase();
          return region.contains('maharashtra') || region == 'mh';
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final title = _scopeMaharashtra ? 'Maharashtra Top 200' : 'India Top 200';

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.30),
        elevation: 0,
        title: Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.20),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<Box>(
          future: Hive.openBox(LeaderboardService.boxName),
          builder: (context, snap) {
            final box = snap.data;
            if (box == null) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
              );
            }
            return ValueListenableBuilder<Box>(
              valueListenable: box.listenable(keys: const ['entries']),
              builder: (context, box, _) {
                final raw = box.get('entries');
                final entries = raw is List
                    ? raw
                          .whereType<Map>()
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList()
                    : <Map<String, dynamic>>[];
                final scoped = _applyScope(entries);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  children: [
                    _scopeToggle(),
                    const SizedBox(height: 14),
                    _headerCard(),
                    const SizedBox(height: 16),
                    if (scoped.isEmpty)
                      _emptyState()
                    else
                      _leaderboardList(scoped),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _scopeToggle() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ChoiceChip(
              label: const Text('Maharashtra'),
              selected: _scopeMaharashtra,
              onSelected: (v) => setState(() => _scopeMaharashtra = true),
              selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.20),
              backgroundColor: Colors.transparent,
              labelStyle: TextStyle(
                color: _scopeMaharashtra ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: _scopeMaharashtra
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ChoiceChip(
              label: const Text('India'),
              selected: !_scopeMaharashtra,
              onSelected: (v) => setState(() => _scopeMaharashtra = false),
              selectedColor: const Color(0xFF22C55E).withValues(alpha: 0.18),
              backgroundColor: Colors.transparent,
              labelStyle: TextStyle(
                color: !_scopeMaharashtra ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: !_scopeMaharashtra
                    ? const Color(0xFF22C55E).withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0B1220),
            const Color(0xFF020617).withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.10),
            blurRadius: 26,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFF7A00)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.25),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Final Power Score',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Speed (25%) + Accuracy (25%) + AI Rating (50%). Flagged data is removed.',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No leaderboard entries yet.',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Upload a few clips, then run Mistake Detection at least once so AI Rating is available.',
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardList(List<Map<String, dynamic>> entries) {
    final rows = <Widget>[];
    for (int i = 0; i < entries.length; i++) {
      rows.add(_row(rank: i + 1, entry: entries[i]));
      if (i == LeaderboardService.cutoffRank - 1) {
        rows.add(const SizedBox(height: 10));
        rows.add(_cutoffLine());
        rows.add(const SizedBox(height: 10));
      } else {
        rows.add(const SizedBox(height: 10));
      }
    }
    return Column(children: rows);
  }

  Widget _cutoffLine() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF2D2D).withValues(alpha: 0.55),
        ),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF2D2D).withValues(alpha: 0.20),
            Colors.transparent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF2D2D).withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFFFF2D2D),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Final Camp Cut-off',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Text(
            '#${LeaderboardService.cutoffRank}',
            style: GoogleFonts.poppins(
              color: const Color(0xFFFFB4B4),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({required int rank, required Map<String, dynamic> entry}) {
    final score = (entry['total_score'] as num?)?.toDouble() ?? 0.0;
    final name = (entry['name'] ?? 'Player').toString();
    final metrics = entry['metrics'];
    final speed = metrics is Map
        ? (metrics['speed_kmph'] as num?)?.toDouble()
        : null;
    final acc = metrics is Map
        ? (metrics['accuracy_percent'] as num?)?.toDouble()
        : null;
    final ai = metrics is Map
        ? (metrics['ai_rating'] as num?)?.toDouble()
        : null;

    final eliteGlow = rank <= LeaderboardService.cutoffRank;
    final medalColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
        ? const Color(0xFFC0C0C0)
        : rank == 3
        ? const Color(0xFFCD7F32)
        : Colors.white.withValues(alpha: 0.22);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: eliteGlow
              ? const Color(0xFFFFD700).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: medalColor.withValues(alpha: 0.65)),
              color: Colors.black.withValues(alpha: 0.18),
            ),
            child: Text(
              '#$rank',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF111827),
              boxShadow: eliteGlow
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
              border: Border.all(
                color: eliteGlow
                    ? const Color(0xFFFFD700).withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Center(
              child: Text(
                _initials(name),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _pill(
                      icon: Icons.speed_rounded,
                      label: speed == null
                          ? 'Speed: —'
                          : 'Speed: ${speed.toStringAsFixed(0)}',
                      color: const Color(0xFF38BDF8),
                    ),
                    _pill(
                      icon: Icons.center_focus_strong_rounded,
                      label: acc == null
                          ? 'Accuracy: —'
                          : 'Accuracy: ${acc.toStringAsFixed(0)}%',
                      color: const Color(0xFF22C55E),
                    ),
                    _pill(
                      icon: Icons.auto_awesome_rounded,
                      label: ai == null
                          ? 'AI: —'
                          : 'AI: ${ai.toStringAsFixed(1)}/10',
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF38BDF8).withValues(alpha: 0.18),
                  const Color(0xFF22D3EE).withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  score.toStringAsFixed(1),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Power',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        color: Colors.black.withValues(alpha: 0.16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.92)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}
