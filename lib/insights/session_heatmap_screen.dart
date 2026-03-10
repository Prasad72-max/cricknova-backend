import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SessionHeatmapScreen extends StatefulWidget {
  const SessionHeatmapScreen({
    super.key,
    required this.sessionId,
    required this.points,
  });

  final int sessionId;
  final List<Map<String, dynamic>> points;

  @override
  State<SessionHeatmapScreen> createState() => _SessionHeatmapScreenState();
}

class _SessionHeatmapScreenState extends State<SessionHeatmapScreen> {
  static const double _pitchWidthM = 3.05;
  static const double _pitchLengthM = 20.12;
  static const double _clusterRadiusM = 1.5;

  int? _selectedIndex;

  List<_HeatmapPoint> get _points => widget.points
      .map(_HeatmapPoint.fromMap)
      .where((point) => point != null)
      .cast<_HeatmapPoint>()
      .toList(growable: false);

  int get _largestCluster {
    final points = _points;
    if (points.isEmpty) return 0;

    var best = 1;
    for (final center in points) {
      var count = 0;
      for (final point in points) {
        final dx = center.x - point.x;
        final dy = center.y - point.y;
        final distance = math.sqrt((dx * dx) + (dy * dy));
        if (distance <= _clusterRadiusM) {
          count++;
        }
      }
      if (count > best) best = count;
    }
    return best;
  }

  bool get _hasClusteringBadge => _largestCluster >= 4;

  Offset _offsetForPoint(_HeatmapPoint point, Size size) {
    final x = (point.x / _pitchWidthM).clamp(0.0, 1.0) * size.width;
    final y =
        size.height - ((point.y / _pitchLengthM).clamp(0.0, 1.0) * size.height);
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          "Session ${widget.sessionId} Heatmap",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => setState(() => _selectedIndex = null),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10203E), Color(0xFF08111F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: const Color(0xFF1E3A5F)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Landing Map",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Top-down bounce positions for the 6-ball session, mapped against a 20.12m x 3.05m pitch.",
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _summaryChip(
                          label: "Balls Tracked",
                          value: "${points.length}/6",
                          accent: const Color(0xFF38BDF8),
                        ),
                        _summaryChip(
                          label: "Cluster Radius",
                          value: "1.5m",
                          accent: const Color(0xFFFACC15),
                        ),
                        _summaryChip(
                          label: "Best Cluster",
                          value: "$_largestCluster balls",
                          accent: const Color(0xFFFB7185),
                        ),
                      ],
                    ),
                    if (_hasClusteringBadge) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14532D),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF22C55E)),
                        ),
                        child: Text(
                          "CLUSTERING MASTER",
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFBBF7D0),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF1E293B)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 560,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CustomPaint(
                                size: size,
                                painter: _HeatmapPitchPainter(
                                  pitchLengthM: _pitchLengthM,
                                ),
                              ),
                              for (int i = 0; i < points.length; i++)
                                _buildMarker(
                                  size: size,
                                  point: points[i],
                                  index: i,
                                ),
                              if (_selectedIndex != null &&
                                  _selectedIndex! >= 0 &&
                                  _selectedIndex! < points.length)
                                _buildPopup(
                                  size: size,
                                  point: points[_selectedIndex!],
                                  index: _selectedIndex!,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        _ZoneLegend(
                          color: Color(0xFFFDE68A),
                          label: "Full / Yorker",
                        ),
                        _ZoneLegend(
                          color: Color(0xFFBAE6FD),
                          label: "Good Length",
                        ),
                        _ZoneLegend(
                          color: Color(0xFFFECACA),
                          label: "Short Pitch",
                        ),
                      ],
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

  Widget _summaryChip({
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF08111F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              color: accent,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildMarker({
    required Size size,
    required _HeatmapPoint point,
    required int index,
  }) {
    final offset = _offsetForPoint(point, size);
    return Positioned(
      left: offset.dx - 13,
      top: offset.dy - 13,
      child: GestureDetector(
        onTap: () => setState(() => _selectedIndex = index),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF38BDF8),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA38BDF8),
                blurRadius: 16,
                spreadRadius: 3,
              ),
            ],
            border: Border.all(color: Colors.white, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            "${point.ball}",
            style: GoogleFonts.poppins(
              color: const Color(0xFF020617),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopup({
    required Size size,
    required _HeatmapPoint point,
    required int index,
  }) {
    final offset = _offsetForPoint(point, size);
    final left = (offset.dx - 74).clamp(8.0, size.width - 156.0).toDouble();
    final top = (offset.dy - 84).clamp(8.0, size.height - 96.0).toDouble();

    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 148,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xEE020617),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF38BDF8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Ball #${point.ball}",
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF38BDF8),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text("Speed: ${point.speedText}"),
                Text("Swing: ${point.swing}"),
                Text(
                  "Zone: ${point.zone}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeatmapPitchPainter extends CustomPainter {
  const _HeatmapPitchPainter({required this.pitchLengthM});

  final double pitchLengthM;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fullZone = Paint()..color = const Color(0xFFFDE68A);
    final goodZone = Paint()..color = const Color(0xFFBAE6FD);
    final shortZone = Paint()..color = const Color(0xFFFECACA);

    double yForMeters(double meters) {
      return size.height -
          ((meters / pitchLengthM).clamp(0.0, 1.0) * size.height);
    }

    final yorkerTop = yForMeters(4.0);
    final goodTop = yForMeters(7.0);

    final pitchRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    );

    canvas.drawRRect(pitchRect, shortZone);
    canvas.drawRect(Rect.fromLTRB(0, goodTop, size.width, yorkerTop), goodZone);
    canvas.drawRect(
      Rect.fromLTRB(0, yorkerTop, size.width, size.height),
      fullZone,
    );
    canvas.drawRRect(pitchRect, borderPaint);

    final centerLine = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerLine,
    );

    final creasePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    final battingCreaseY = size.height - 28;
    canvas.drawLine(
      Offset(24, battingCreaseY),
      Offset(size.width - 24, battingCreaseY),
      creasePaint,
    );

    final stumpPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final stumpGlow = Paint()
      ..color = const Color(0x55FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final stumpTop = size.height - 46;
    final stumpBottom = size.height - 12;
    final spacing = 10.0;

    for (int i = -1; i <= 1; i++) {
      final centerX = (size.width / 2) + (i * spacing);
      final rect = Rect.fromLTWH(
        centerX - 2.4,
        stumpTop,
        4.8,
        stumpBottom - stumpTop,
      );
      canvas.drawRect(rect, stumpGlow);
      canvas.drawRect(rect, stumpPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPitchPainter oldDelegate) {
    return oldDelegate.pitchLengthM != pitchLengthM;
  }
}

class _ZoneLegend extends StatelessWidget {
  const _ZoneLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _HeatmapPoint {
  _HeatmapPoint({
    required this.ball,
    required this.x,
    required this.y,
    required this.swing,
    required this.zone,
    this.speed,
  });

  final int ball;
  final double x;
  final double y;
  final double? speed;
  final String swing;
  final String zone;

  String get speedText => speed != null && speed!.isFinite
      ? "${speed!.toStringAsFixed(1)} km/h"
      : "--";

  static _HeatmapPoint? fromMap(Map<String, dynamic> raw) {
    final xRaw = raw["x"];
    final yRaw = raw["y"];
    if (xRaw is! num || yRaw is! num) return null;

    final ballRaw = raw["ball"];
    final speedRaw = raw["speed"];

    return _HeatmapPoint(
      ball: ballRaw is num ? ballRaw.toInt() : 0,
      x: xRaw.toDouble(),
      y: yRaw.toDouble(),
      speed: speedRaw is num ? speedRaw.toDouble() : null,
      swing: (raw["swing"]?.toString() ?? "UNKNOWN").toUpperCase(),
      zone: (raw["zone"]?.toString() ?? "GOOD LENGTH").toUpperCase(),
    );
  }
}
